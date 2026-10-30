"""保護された環境を準備し、repo の canonical 検証を一度だけ実行する。"""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

sys.dont_write_bytecode = True

from verification_env import new_runtime, write_json


WORKER = """
import importlib.util, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
spec = importlib.util.spec_from_file_location('canonical_preparation', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
raise SystemExit(module.prepare(*map(Path, sys.argv[2:])))
"""


def save(directory, result):
    write_json(directory / "result.json", result)


def prepare(source, directory, hook):
    result = {"phase": "preparation", "status": "running", "canonical": None}
    save(directory, result)
    try:
        binary = Path(os.environ.get("IMPECCABLE_BIN", "")).resolve(strict=True)
        if not binary.is_relative_to("/nix/store") or not binary.is_file():
            raise ValueError("選択された Nix output の IMPECCABLE_BIN が必要です")
        with (directory / "playwright-build.log").open("wb") as log:
            output = subprocess.check_output(
                [
                    "nix",
                    "build",
                    "--impure",
                    "--no-link",
                    "--print-out-paths",
                    "--file",
                    "tests/helpers/playwright-runtime-package.nix",
                ],
                cwd=source,
                stderr=log,
                text=True,
            ).splitlines()
        if len(output) != 1:
            raise ValueError("Playwright package の output が1件ではありません")
        package = Path(output[0])
        if not package.is_relative_to("/nix/store") or not package.is_dir():
            raise ValueError("Playwright package output が不正です")
        environment = os.environ.copy()
        environment.update(
            IMPECCABLE_HOOK_RUNTIME=str(hook),
            TEST_PLAYWRIGHT_PACKAGE=str(package),
        )
        (directory / "runtime-input.json").write_text(
            json.dumps(
                {
                    key: environment[key]
                    for key in (
                        "IMPECCABLE_HOOK_RUNTIME",
                        "IMPECCABLE_BIN",
                        "TEST_PLAYWRIGHT_PACKAGE",
                    )
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        )
        count = subprocess.check_output(
            ["bats", "--count", "tests/"], cwd=source, env=environment, text=True
        ).strip()
        if not count.isdecimal() or int(count) < 1:
            raise ValueError("source の Bats 件数が不正です")
        result.update(phase="canonical", source_test_count=int(count))
        save(directory, result)
        process = subprocess.Popen(
            [sys.executable, str(source / "scripts/verify-canonical.py")],
            cwd=source,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        with (directory / "canonical.log").open("w") as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if line.startswith("検証記録: "):
                    path = Path(line.removeprefix("検証記録: ").strip())
                    if path.parent != source / "tmp" or not path.name.startswith(
                        "canonical-run."
                    ):
                        process.terminate()
                        process.wait()
                        raise ValueError("canonical の記録先が不正です")
                    result["canonical"] = str(path)
                    (directory / "canonical-path").write_text(str(path) + "\n")
                    save(directory, result)
        status = process.wait()
        status = status if status >= 0 else 128 - status
        if status == 0:
            if result["canonical"] is None:
                raise ValueError("canonical の記録先が取得できません")
            canonical = json.loads(
                (Path(result["canonical"]) / "result.json").read_text()
            )
            if canonical["exit_code"] != 0 or canonical["tap"]["plan"] != int(count):
                raise ValueError("canonical 結果と source 件数が一致しません")
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
        status = 1
    result.update(status="passed" if status == 0 else "failed", exit_code=status)
    save(directory, result)
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", choices=("default", "wsl"), default="default")
    parser.add_argument("--no-codex-build", action="store_true")
    arguments = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    try:
        hook = Path(
            os.environ.get("IMPECCABLE_HOOK_RUNTIME")
            or Path.home() / ".agents/skills/impeccable/scripts/impeccable"
        ).resolve(strict=True)
        if not hook.is_file() or not os.access(hook, os.X_OK):
            raise ValueError("導入済みの実行可能な Impeccable hook runtime が必要です")
        directory = new_runtime("canonical-env.")
    except (OSError, ValueError) as error:
        print(f"環境準備を開始できません: {error}", file=sys.stderr)
        return 1
    print(f"環境準備の記録: {directory}", flush=True)
    save(directory, {"phase": "environment", "status": "running", "canonical": None})
    command = [
        sys.executable,
        str(source / "scripts/verify-ai-tools.py"),
        str(source),
        "--shell",
        arguments.shell,
        "--read-only",
        str(hook.parent.parent),
    ]
    if arguments.no_codex_build:
        command.append("--no-codex-build")
    command.extend(
        [
            "--",
            sys.executable,
            "-I",
            "-B",
            "-c",
            WORKER,
            str(Path(__file__).resolve()),
            str(source),
            str(directory),
            str(hook),
        ]
    )

    def interrupted(received, _frame):
        raise SystemExit(128 + received)

    for received in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(received, interrupted)
    process = None
    try:
        with (directory / "environment.log").open("w") as log:
            process = subprocess.Popen(
                command, cwd=source, stdout=log, stderr=subprocess.STDOUT
            )
            announced = False
            while process.poll() is None:
                progress = json.loads((directory / "result.json").read_text())
                if progress.get("canonical") and not announced:
                    print(
                        f"canonical 検証の記録: {progress['canonical']}",
                        flush=True,
                    )
                    announced = True
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            status = process.returncode
            status = status if status >= 0 else 128 - status
    except BaseException as error:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait()
        result = json.loads((directory / "result.json").read_text())
        status = (
            130 if isinstance(error, KeyboardInterrupt) else getattr(error, "code", 1)
        )
        result.update(
            status="interrupted"
            if isinstance(error, (KeyboardInterrupt, SystemExit))
            else "failed",
            exit_code=status,
        )
        save(directory, result)
        raise
    result = json.loads((directory / "result.json").read_text())
    result.update(status="passed" if status == 0 else "failed", exit_code=status)
    save(directory, result)
    print(
        f"canonical 検証: {result['status']}（exit {status}、{directory}）", flush=True
    )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
