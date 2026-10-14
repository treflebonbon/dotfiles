"""隔離 HOME の user / repo devShell で候補 AI output と実起動を照合する。"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--shell", choices=("default", "wsl"), default="default")
    cli = sys.argv[1:]
    separator = cli.index("--") if "--" in cli else len(cli)
    arguments = parser.parse_args(cli[:separator])
    command = cli[separator + 1 :]
    source = arguments.source.resolve(strict=True)
    (source / "tmp").mkdir(exist_ok=True)
    runtime = Path(tempfile.mkdtemp(prefix="ai-tools-", dir=source / "tmp"))
    environment = os.environ.copy()
    for key, directory in (
        ("HOME", "home"),
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_RUNTIME_DIR", "runtime"),
        ("XDG_CACHE_HOME", "cache"),
        ("XDG_STATE_HOME", "state"),
    ):
        path = runtime / directory
        path.mkdir(mode=0o700)
        environment[key] = str(path)
    for key in ("CODEX_HOME", "CLAUDE_CONFIG_DIR", "FORCE_COLOR"):
        environment.pop(key, None)
    environment.update(
        AI_TOOL_SOURCE=str(source),
        AI_TOOL_SHELL=arguments.shell,
        AI_TOOL_SELECTION=json.dumps(TOOLS),
    )
    print(f"検証ログ: {runtime}", flush=True)
    with (runtime / "evaluation.log").open("w") as log:
        result = subprocess.run(
            [
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
        status = (
            result.returncode if result.returncode >= 0 else 128 - result.returncode
        )
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
            invocation, cwd=source, env=environment, stdout=log, stderr=log
        ).returncode
    status = status if status >= 0 else 128 - status
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
