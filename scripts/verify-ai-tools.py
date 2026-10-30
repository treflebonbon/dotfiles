"""隔離 HOME の user / repo devShell で候補 AI output と実起動を照合する。"""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

sys.dont_write_bytecode = True

from verification_env import create_environment, new_runtime, sandbox_prefix


TOOLS = {
    "claude-code": "claude",
    "codex": "codex",
    "copilot-cli": "copilot",
    "antigravity-cli": "agy",
    "apm": "apm",
    "herdr": "herdr",
}
EXPRESSION = """let
  source = builtins.getEnv "AI_TOOL_SOURCE";
  flake = builtins.getFlake ("git+file://" + source + "?dir=private_dot_config/nix-devshell");
  shell = flake.devShells.${builtins.currentSystem}.${builtins.getEnv "AI_TOOL_SHELL"};
  tools = builtins.fromJSON (builtins.getEnv "AI_TOOL_SELECTION");
in builtins.map (name:
  let matches = builtins.filter (p: (p.pname or "") == name) shell.nativeBuildInputs;
      package = builtins.head matches;
  in assert builtins.length matches == 1; {
    name = tools.${name};
    path = "${package}/bin/${tools.${name}}";
    version = package.version;
  }
) (builtins.attrNames tools)
"""
PROBE = """
set -eu
metadata=$1
shift
while IFS="$(printf '\\t')" read -r tool expected; do
  actual=$(command -v "$tool") || { printf 'REJECT: %s がありません\\n' "$tool" >&2; exit 1; }
  if [ "$actual" != "$expected" ]; then
    printf 'REJECT: %s のoutput不一致: 期待=%s 実際=%s\\n' "$tool" "$expected" "$actual" >&2
    exit 1
  fi
  printf '%s: %s\\n' "$tool" "$actual"
  "$tool" --version
done < "$metadata"
if [ "$#" -gt 0 ]; then exec "$@"; fi
"""


def shell_exit_code(returncode):
    return returncode if returncode >= 0 else 128 - returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--shell", choices=("default", "wsl"), default="default")
    parser.add_argument(
        "--no-codex-build",
        action="store_true",
        help="Codex の既存 output または binary cache を使い、新規ビルドが必要なら停止する",
    )
    cli = sys.argv[1:]
    separator = cli.index("--") if "--" in cli else len(cli)
    arguments = parser.parse_args(cli[:separator])
    command = cli[separator + 1 :]
    # SIGTERM / SIGHUP は atexit を飛ばす。SystemExit に変えて後始末を走らせ、subprocess.run に子を止めさせる。
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, lambda received, _frame: sys.exit(128 + received))
    source = arguments.source.resolve(strict=True)
    runtime = new_runtime("ai-tools-")
    print(f"検証ログ: {runtime}", flush=True)
    try:
        prefix = sandbox_prefix(source, runtime, Path(os.environ["HOME"]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        (runtime / "exit-code").write_text("1\n")
        print(f"REJECT: 書込み境界を準備できません: {error}", file=sys.stderr)
        return 1
    environment = create_environment(runtime)
    environment.update(
        AI_TOOL_SOURCE=str(source),
        AI_TOOL_SHELL=arguments.shell,
        AI_TOOL_SELECTION=json.dumps(TOOLS),
    )
    with (runtime / "evaluation.log").open("w") as log:
        result = subprocess.run(
            [
                *prefix,
                "nix",
                "eval",
                "--impure",
                "--json",
                "--no-write-lock-file",
                "--expr",
                EXPRESSION,
            ],
            env=environment,
            cwd=source,
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
        )
    if result.returncode:
        status = shell_exit_code(result.returncode)
        (runtime / "exit-code").write_text(f"{status}\n")
        print(
            f"REJECT: Nix評価exit {status}（{runtime / 'evaluation.log'}）",
            file=sys.stderr,
        )
        return status
    (runtime / "metadata.json").write_text(result.stdout)
    paths = runtime / "paths.tsv"
    try:
        metadata = json.loads(result.stdout)
        if {entry["name"] for entry in metadata} != set(TOOLS.values()) or len(
            metadata
        ) != len(TOOLS):
            raise ValueError("候補AI CLIのmetadataが欠落または重複しています")
        paths.write_text(
            "".join(f"{entry['name']}\t{entry['path']}\n" for entry in metadata)
        )
    except (ValueError, TypeError, KeyError) as error:
        diagnostic = f"REJECT: 候補AI metadata不正: {error}\n"
        with (runtime / "evaluation.log").open("a") as log:
            log.write(diagnostic)
        (runtime / "exit-code").write_text("1\n")
        print(diagnostic, file=sys.stderr, end="")
        return 1
    if arguments.no_codex_build:
        codex_output = next(
            Path(entry["path"]).parent.parent
            for entry in metadata
            if entry["name"] == "codex"
        )
        # output path を直接指定し、derivation のビルドへフォールバックさせない。
        with (runtime / "codex-cache.log").open("w") as log:
            result = subprocess.run(
                [
                    *prefix,
                    "nix",
                    "build",
                    "--out-link",
                    str(runtime / "codex"),
                    "--max-jobs",
                    "0",
                    "--builders",
                    "",
                    str(codex_output),
                ],
                cwd=source,
                env=environment,
                stdout=log,
                stderr=log,
            )
        if result.returncode:
            status = shell_exit_code(result.returncode)
            (runtime / "exit-code").write_text(f"{status}\n")
            print(
                f"REJECT: Codex をビルドせず確保できません（{runtime / 'codex-cache.log'}）",
                file=sys.stderr,
            )
            return status
    invocation = [
        "nix",
        "develop",
        f"{source}/private_dot_config/nix-devshell#{arguments.shell}",
        "--no-write-lock-file",
        "--cores",
        "1",
        "--max-jobs",
        "1",
        "--command",
        "nix",
        "develop",
        f"{source}#{arguments.shell}",
        "--no-write-lock-file",
        "--command",
        "bash",
        "-c",
        PROBE,
        "verify-ai-tools",
        str(paths),
        *command,
    ]
    with (runtime / "startup.log").open("w") as log:
        status = subprocess.run(
            [*prefix, *invocation], cwd=source, env=environment, stdout=log, stderr=log
        ).returncode
    status = shell_exit_code(status)
    (runtime / "exit-code").write_text(f"{status}\n")
    if status:
        print(
            f"REJECT: 起動検証exit {status}（{runtime / 'startup.log'}）",
            file=sys.stderr,
        )
    else:
        print("PASS: 6 CLIの候補outputと実起動が一致しました", flush=True)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
