"""準備済み環境で全Batsを一度実行し、同じ実行の証拠を照合する手動入口。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time


# bf31e700 の承認済みfixture。変更中のテストや今回のTAPから導出しない。
REQUIRED_TESTS = (
    "materialized quiet Design Hook reports an immediate-tier finding on the edit",
    "materialized quiet Design Hook emits the full self-serve policy once per session",
    "materialized Design Hook self-serve ignore persists only a reasoned detector value",
    "materialized quiet Design Hook stays silent for clean, non-UI, sensitive, and generated files",
    "materialized quiet Design Hook defers non-immediate findings to the Stop deep pass and surfaces them once",
    "materialized quiet Design Hook emits native Codex Stop output for a turn-scoped deep-pass finding",
    "global materialized hooks check new projects without opt-in for both providers",
    "materialized Codex apply_patch checks a symlinked monorepo target and converges",
    "materialized hooks preserve project config and disposable cache ownership",
    "materialized quiet Design Hook Stop pass converges silently on a file with findings in both tiers",
    "materialized quiet Design Hook Stop pass stays silent for an untouched session and when re-entered",
    "materialized quiet Design Hook dedupes repeated findings and suppresses a new finding after the edit threshold",
    "Design Hook remains unwired for Antigravity, Cursor, and GitHub Copilot",
    "Playwright runtime keeps locks and fails closed across records and process failures",
    "distributed Playwright package protects the direct CLI and retains shared FDs",
)


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def read_record(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"記録fileが欠落またはsymlinkです: {path.name}")
    return path.read_bytes().decode()


def source_record(source, environment):
    def git(*arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=source,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout

    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).removesuffix("\n"))
    directory = Path(
        os.fsdecode(git("rev-parse", "--absolute-git-dir")).removesuffix("\n")
    )
    common = Path(
        os.fsdecode(
            git("rev-parse", "--path-format=absolute", "--git-common-dir")
        ).removesuffix("\n")
    )
    if root.resolve() != source or directory.resolve() == common.resolve():
        raise ValueError("対象はlinked task worktreeである必要があります")
    files = {}
    for name in git("ls-files", "-z").split(b"\0"):
        if not name:
            continue
        path = source / os.fsdecode(name)
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            kind, content = "symlink", os.fsencode(os.readlink(path))
        elif stat.S_ISREG(mode):
            kind, content = "file", path.read_bytes()
        else:
            raise ValueError(f"記録できないtracked fileです: {path}")
        files[os.fsdecode(name)] = {
            "kind": kind,
            "mode": stat.S_IMODE(mode),
            "sha256": hashlib.sha256(content).hexdigest(),
        }
    return {
        "root": str(source),
        "git_dir": str(directory),
        "common_dir": str(common),
        "head": git("rev-parse", "HEAD").decode().strip(),
        "status": os.fsdecode(git("status", "--porcelain=v1", "-z")),
        "files": files,
    }


def runtime_record(environment):
    paths = {}
    for name in (
        "IMPECCABLE_HOOK_RUNTIME",
        "IMPECCABLE_BIN",
        "TEST_PLAYWRIGHT_PACKAGE",
    ):
        value = environment.get(name)
        if not value or not Path(value).is_absolute():
            raise ValueError(f"{name}に準備済みruntimeの絶対パスが必要です")
        paths[name] = value
    package = Path(paths.pop("TEST_PLAYWRIGHT_PACKAGE"))
    paths.update(
        {
            "playwright_owner": str(package / "bin/managed-chrome-owner"),
            "playwright_launcher": str(package / "libexec/playwright-runtime"),
            "playwright_module": str(
                package / "share/playwright-cli/playwright-runtime.mjs"
            ),
            "playwright_lock": str(package / "share/playwright-cli/browser-lock.mjs"),
            "verifier_python": sys.executable,
        }
    )
    for name in ("TEST_MANAGED_CHROME_OWNER", "TEST_PLAYWRIGHT_RUNTIME_MODULE"):
        if value := environment.get(name):
            paths[name] = value
    for name in ("python3", "with-env", "lefthook", "bun", "bats", "node"):
        value = shutil.which(name, path=environment.get("PATH"))
        if not value:
            raise ValueError(f"準備済み環境に{name}がありません")
        paths[name] = value
    result = {}
    for name, value in paths.items():
        path = Path(value)
        if not path.is_absolute() or not path.is_file():
            raise ValueError(f"runtimeが準備されていません: {name}")
        if name not in (
            "playwright_module",
            "playwright_lock",
            "TEST_PLAYWRIGHT_RUNTIME_MODULE",
        ) and not os.access(path, os.X_OK):
            raise ValueError(f"runtimeを実行できません: {name}")
        with path.open("rb") as content:
            digest = hashlib.file_digest(content, "sha256").hexdigest()
        result[name] = {
            "declared": value,
            "resolved": str(path.resolve(strict=True)),
            "sha256": digest,
        }
    return result


def tap_record(path):
    plans, rows, errors = [], [], []
    content = read_record(path)
    for line in content.splitlines():
        if plan := re.fullmatch(r"1\.\.([0-9]+)\s*", line):
            plans.append(int(plan[1]))
        elif row := re.fullmatch(r"(not ok|ok) ([0-9]+)(?: (.*))?", line):
            name = row[3] or ""
            directive = re.search(r"\s+#\s*skip\b", name, re.IGNORECASE)
            rows.append(
                (
                    int(row[2]),
                    name[: directive.start()] if directive else name,
                    row[1] == "ok",
                    bool(directive),
                )
            )
        elif line.startswith("Bail out!"):
            errors.append("TAPに中断宣言があります")
    if plans != [len(rows)] or [row[0] for row in rows] != list(
        range(1, len(rows) + 1)
    ):
        errors.append("TAPの計画・件数・連番が不整合です")
    required = []
    for name in REQUIRED_TESTS:
        matches = [row for row in rows if row[1] == name]
        if len(matches) != 1 or not matches[0][2] or matches[0][3]:
            errors.append(f"必須fixtureが欠落・重複・失敗・skipしています: {name}")
        else:
            required.append(name)
    return {
        "sha256": hashlib.sha256(content.encode()).hexdigest(),
        "plan": plans[0] if len(plans) == 1 else None,
        "pass": sum(ok and not skipped for _, _, ok, skipped in rows),
        "skip": sum(ok and skipped for _, _, ok, skipped in rows),
        "fail": sum(not ok for _, _, ok, _ in rows),
        "required": required,
    }, errors


def runner_directory(receipt, temporary):
    directory = Path(read_record(receipt).removesuffix("\n"))
    if (
        directory.parent != temporary
        or not directory.name.startswith("test-run.")
        or directory.resolve(strict=True) != directory
    ):
        raise ValueError("runnerのログ先が不正です")
    if read_record(directory / "canonical-receipt") != str(receipt) + "\n":
        raise ValueError("異なる実行のrunnerログです")
    return directory


def run_command(command, source, environment, output):
    process, interrupted = None, None

    def stop(signum, _frame):
        nonlocal interrupted
        if interrupted is None:
            interrupted = signum
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass

    previous = {
        sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        if interrupted is not None:
            return None, None, interrupted
        started = time.monotonic()
        process = subprocess.Popen(
            command,
            cwd=source,
            env=environment,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        if interrupted is not None:
            stop(interrupted, None)
        status = process.wait()
        elapsed = time.monotonic() - started
        if interrupted is not None:
            try:
                directory = runner_directory(
                    Path(environment["DOTFILES_TEST_RUN_RECEIPT"]), source / "tmp"
                )
            except (OSError, ValueError):
                pass
            else:
                # shortcut: 終了記録は5秒まで待機、runnerの停止猶予を延ばす場合は合わせて更新する。
                deadline = time.monotonic() + 5
                while (
                    not (directory / "exit-code").is_file()
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.01)
        return status if status >= 0 else 128 - status, elapsed, interrupted
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    source = Path(__file__).resolve().parent.parent
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    attempt = None
    result = {
        "command": ["lefthook", "run", "test"],
        "command_exit": None,
        "runner_exit": None,
        "elapsed_seconds": None,
        "tap": None,
        "runner_environment": None,
        "signal": None,
        "errors": [],
    }
    errors = result["errors"]
    try:
        before_source = source_record(source, environment)
        if before_source["status"]:
            raise ValueError("開始時の作業ツリーがcleanではありません")
        temporary = source / "tmp"
        if temporary.is_symlink():
            raise ValueError("tmpをsymlinkとして利用できません")
        temporary.mkdir(exist_ok=True)
        attempt = Path(tempfile.mkdtemp(prefix="canonical-run.", dir=temporary))
        print(f"検証記録: {attempt}", flush=True)
        before = {"source": before_source, "runtime": runtime_record(environment)}
        save_json(attempt / "before.json", before)
        receipt = attempt / "runner-path"
        environment["DOTFILES_TEST_RUN_RECEIPT"] = str(receipt)
        with (attempt / "command.log").open("wb") as output:
            result["command_exit"], result["elapsed_seconds"], result["signal"] = (
                run_command(result["command"], source, environment, output)
            )
        try:
            after = {
                "source": source_record(source, environment),
                "runtime": runtime_record(environment),
            }
            save_json(attempt / "after.json", after)
            if before["source"] != after["source"]:
                errors.append("source/HEADの前後記録が不一致です")
            if before["runtime"] != after["runtime"]:
                errors.append("runtimeの前後記録が不一致です")
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            errors.append(f"終了後の記録が不完全です: {error}")
        directory = runner_directory(receipt, temporary)
        runner_exit = read_record(directory / "exit-code")
        if not re.fullmatch(r"[0-9]+\n?", runner_exit) or int(runner_exit) > 255:
            raise ValueError("runnerの終了コード記録が不正です")
        result["runner_exit"] = int(runner_exit)
        if result["runner_exit"] != result["command_exit"]:
            errors.append("コマンドとrunnerの終了コードが不一致です")
        observed = read_record(directory / "environment")
        runtimes = {}
        for line in observed.splitlines():
            name, separator, value = line.partition(": ")
            if (
                name not in ("python3", "with-env")
                or name in runtimes
                or not separator
                or value != before["runtime"][name]["resolved"]
            ):
                raise ValueError("実行runtimeの記録が宣言値と不一致です")
            runtimes[name] = value
        if set(runtimes) != {"python3", "with-env"}:
            raise ValueError("実行runtimeの記録が欠落しています")
        result["runner_environment"] = observed
        result["tap"], tap_errors = tap_record(directory / "tap.log")
        errors.extend(tap_errors)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        errors.append(str(error))
    result["exit_code"] = (
        (128 + result["signal"])
        if result["signal"]
        else result["command_exit"]
        or (1 if errors or result["tap"] is None or result["tap"]["fail"] else 0)
    )
    if attempt is not None:
        save_json(attempt / "result.json", result)
    outcome = "PASS" if result["exit_code"] == 0 else "REJECT"
    command_exit = (
        result["command_exit"] if result["command_exit"] is not None else "未実行"
    )
    print(
        f"{outcome}: canonical検証 exit {result['exit_code']}（lefthook: {command_exit}）"
    )
    if result["elapsed_seconds"] is not None:
        print(f"全Batsコマンド実測: {result['elapsed_seconds']:.3f}秒")
    if tap := result["tap"]:
        print(
            f"TAP: plan={tap['plan']} pass={tap['pass']} skip={tap['skip']} fail={tap['fail']} 必須={len(tap['required'])}/{len(REQUIRED_TESTS)}"
        )
    for error in errors:
        print(f"REJECT: {error}", file=sys.stderr)
    return result["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
