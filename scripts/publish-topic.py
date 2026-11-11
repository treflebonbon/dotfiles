"""topic branch の引継ぎ対象を照合し、push と PR 公開確認を別々に記録する。"""

import argparse
from contextlib import contextmanager
import fcntl
import importlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True

from verification_env import SCRATCH_ROOT, new_runtime, write_json


def dependencies():
    library = Path(os.environ.get("TREFLEBONBON_SKILLS_LIB", "")).resolve(strict=True)
    if library.parts[:3] != ("/", "nix", "store"):
        raise ValueError("ユーザー devShell の固定版 skills library が必要です")
    sys.path.insert(0, str(library))
    return importlib.import_module(
        "treflebonbon_skills.git_context"
    ), library.parent.parent


def record_path(directory):
    scratch = SCRATCH_ROOT.lstat()
    if (
        SCRATCH_ROOT.is_symlink()
        or not stat.S_ISDIR(scratch.st_mode)
        or scratch.st_uid != os.getuid()
        or scratch.st_mode & 0o077
        or directory.is_symlink()
    ):
        raise ValueError("公開記録の一時領域が不正です")
    directory = directory.resolve(strict=True)
    metadata = directory.stat()
    if (
        not directory.is_relative_to(SCRATCH_ROOT.resolve(strict=True))
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_mode & 0o077
    ):
        raise ValueError(
            "記録先は /tmp/codex 内の本人所有の private directory が必要です"
        )
    path = directory / "publication.json"
    if path.is_symlink():
        raise ValueError("公開記録を symlink として利用できません")
    return path


def valid_repo(repo):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("repository は OWNER/REPO で指定してください")


def topic_identity(source, repo):
    valid_repo(repo)
    context, _ = dependencies()
    try:
        worktree = context.Repository.discover(source, linked_only=True)
    except context.InvalidContext as error:
        raise ValueError("validated linked task worktree が必要です") from error
    environment = context.git_environment()

    def git(*args):
        return subprocess.check_output(
            ["git", *args], cwd=worktree.root, env=environment, text=True
        ).strip()

    origin = git("remote", "get-url", "origin")
    if origin.removesuffix(".git").casefold() != f"https://github.com/{repo}".casefold():
        raise ValueError("origin と指定した repository が一致しません")
    branch = git("branch", "--show-current")
    if not branch or branch in ("main", "master"):
        raise ValueError("topic branch が必要です")
    return {
        "source": str(worktree.root),
        "repo": repo,
        "branch": branch,
        "head": git("rev-parse", "HEAD"),
    }


def valid_pr_observation(observed):
    return (
        isinstance(observed, dict)
        and all(
            isinstance(observed.get(key), str)
            for key in ("headRefOid", "headRefName", "state", "url")
        )
        and re.fullmatch(r"[0-9a-fA-F]{40}", observed["headRefOid"]) is not None
    )


def inspect_topic(source, repo, pr=None):
    if pr is not None and pr < 1:
        raise ValueError("PR 番号は正の整数が必要です")
    identity = topic_identity(source, repo)
    context, _ = dependencies()
    fields = "number,headRefOid,headRefName,state,url"
    command = ["gh", "pr"]
    if pr is None:
        command.extend(["list", "--head", identity["branch"], "--state", "all"])
    else:
        command.extend(["view", str(pr)])
    try:
        response = subprocess.run(
            [*command, "--repo", repo, "--json", fields],
            env=context.git_environment(),
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        # 認証値の漏えいを防ぐため、stderr から許可した診断値だけを記録する。
        http_status = re.search(r"\bHTTP ([45][0-9]{2})\b", error.stderr or "")
        if error.returncode == 4:
            reason = "認証が必要"
        elif http_status:
            reason = f"HTTP {http_status[1]}"
        else:
            reason = "API コマンド失敗"
        raise ValueError(f"PR API の照合失敗（exit {error.returncode}、{reason}）") from None
    observations = json.loads(response.stdout)
    if pr is not None:
        observations = [observations]
    if not isinstance(observations, list) or any(
        not valid_pr_observation(item)
        or type(item.get("number")) is not int
        or item["number"] < 1
        or (pr is not None and item["number"] != pr)
        for item in observations
    ):
        raise ValueError("PR API の応答形式が不正です")
    status = "not_created"
    if len(observations) > 1:
        status = "ambiguous"
    elif observations:
        observed = observations[0]
        status = (
            "confirmed"
            if observed["headRefName"] == identity["branch"]
            and observed["headRefOid"] == identity["head"]
            else "mismatch"
        )
    return {**identity, "status": status, "observations": observations}


@contextmanager
def locked_record(directory):
    path = record_path(directory)
    # JSON は置換されるので、同じ inode を保つ記録 directory をロックする。
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield path
    finally:
        os.close(descriptor)


def push(source, repo, directory):
    valid_repo(repo)
    with locked_record(directory) as path:
        return _push(source, repo, path)


def _push(source, repo, path):
    if path.exists():
        raise ValueError(
            "既存の公開記録は verify で再開してください。push は再実行しません"
        )
    if any(path.parent.iterdir()):
        raise ValueError("新しい空の記録 directory を指定してください")
    context, public = dependencies()
    identity = topic_identity(source, repo)
    environment = context.git_environment()
    if subprocess.check_output(
        ["git", "status", "--porcelain"],
        cwd=identity["source"],
        env=environment,
        text=True,
    ).strip():
        raise ValueError("公開する task worktree を commit して clean にしてください")
    receipt = {
        "schema_version": 1,
        **identity,
        "push": {"status": "started"},
        "verification": None,
    }
    path.touch(mode=0o600, exist_ok=False)
    write_json(path, receipt)
    print(f"公開記録: {path.parent}", flush=True)
    # HOME を切替済みでも、既存 GH_CONFIG_DIR で gh の credential helper を使う。
    environment.update(
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_TERMINAL_PROMPT="0",
        GIT_CONFIG_COUNT="2",
        GIT_CONFIG_KEY_0="credential.helper",
        GIT_CONFIG_VALUE_0="",
        GIT_CONFIG_KEY_1="credential.https://github.com.helper",
        GIT_CONFIG_VALUE_1="!gh auth git-credential",
    )
    with (
        (path.parent / "push.stdout.log").open("w") as output,
        (path.parent / "push.stderr.log").open("w") as error,
    ):
        result = subprocess.run(
            [str(public / "bin/git-push-topic")],
            cwd=identity["source"],
            env=environment,
            stdout=output,
            stderr=error,
            timeout=1800,
        )
    receipt["push"] = {
        "status": "succeeded" if result.returncode == 0 else "failed",
        "exit_code": result.returncode,
    }
    write_json(path, receipt)
    print(f"push 結果: {receipt['push']['status']} / 記録: {path.parent}", flush=True)
    return 0 if result.returncode == 0 else 1


def verify(directory, pr, timeout):
    with locked_record(directory) as path:
        return _verify(path, pr, timeout)


def _verify(path, pr, timeout):
    receipt = json.loads(path.read_text())
    if (
        receipt.get("schema_version") != 1
        or not re.fullmatch(r"[0-9a-f]{40}", receipt.get("head", ""))
        or not isinstance(receipt.get("branch"), str)
        or receipt.get("push", {}).get("status")
        not in ("started", "succeeded", "failed")
        or pr < 1
        or not 0 <= timeout <= 300
    ):
        raise ValueError("公開記録または照合条件が不正です")
    valid_repo(receipt["repo"])
    previous = receipt.get("verification")
    if previous and previous["observations"] and previous["pr"] != pr:
        raise ValueError("同じ公開記録の照合先 PR は変更できません")
    verification = {
        "pr": pr,
        "status": "pending",
        "observations": previous["observations"] if previous else [],
    }
    receipt["verification"] = verification
    write_json(path, receipt)
    context, _ = dependencies()
    deadline = time.monotonic() + timeout
    while True:
        try:
            response = subprocess.run(
                [
                    "gh",
                    "pr",
                    "view",
                    str(pr),
                    "--repo",
                    receipt["repo"],
                    "--json",
                    "headRefOid,headRefName,state,url",
                ],
                env=context.git_environment(),
                capture_output=True,
                text=True,
                timeout=max(1, min(15, deadline - time.monotonic())),
                check=True,
            )
            observed = json.loads(response.stdout)
            if not valid_pr_observation(observed):
                raise ValueError("PR API の応答形式が不正です")
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            verification.update(status="api_error", error=type(error).__name__)
            write_json(path, receipt)
            print(
                f"push の結果は保存済みです。PR 照合に失敗しました: {path.parent}",
                file=sys.stderr,
            )
            return 1
        verification["observations"].append(observed)
        if observed["headRefName"] != receipt["branch"]:
            verification["status"] = "mismatch"
        elif observed["state"] != "OPEN":
            verification["status"] = "closed"
        elif observed["headRefOid"] == receipt["head"]:
            verification["status"] = "confirmed"
        write_json(path, receipt)
        if verification["status"] != "pending":
            print(
                f"PR 照合: {verification['status']} / 記録: {path.parent}", flush=True
            )
            return 0 if verification["status"] == "confirmed" else 1
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print(
                f"push の結果は保存済みです。PR 照合は未完了です。verify で再開してください: {path.parent}",
                file=sys.stderr,
            )
            return 2
        time.sleep(min(2, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspection = commands.add_parser(
        "inspect", help="引継ぎ用に現在の branch・HEAD・PR を照合する"
    )
    inspection.add_argument("--repo", required=True)
    inspection.add_argument("--pr", type=int, help="照合する PR（省略時は branch から検索）")
    publish = commands.add_parser("push", help="topic を1回だけ push して記録する")
    publish.add_argument("--repo", required=True)
    publish.add_argument(
        "--record", type=Path, help="空の private directory（省略時は作成）"
    )
    check = commands.add_parser(
        "verify", help="記録した commit の PR 公開を読み取りだけで確認する"
    )
    check.add_argument("record", type=Path)
    check.add_argument("--pr", required=True, type=int)
    check.add_argument(
        "--timeout", default=30, type=float, help="確認を待つ秒数（0〜300、既定30）"
    )
    arguments = parser.parse_args()
    try:
        if arguments.command == "inspect":
            result = inspect_topic(Path.cwd(), arguments.repo, arguments.pr)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0 if result["status"] in ("confirmed", "not_created") else 1
        if arguments.command == "push":
            directory = arguments.record or new_runtime("topic-publication.")
            return push(Path.cwd(), arguments.repo, directory)
        return verify(arguments.record, arguments.pr, arguments.timeout)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"公開処理を停止しました: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
