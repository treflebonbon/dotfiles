"""検証コマンドを、一時 HOME と通常 HOME への書込み境界の内側で実行する。"""

import argparse
import atexit
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


SCRATCH_ROOT = Path("/tmp/codex")


def new_runtime(prefix: str) -> Path:
    SCRATCH_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    metadata = SCRATCH_ROOT.stat(follow_symlinks=False)
    if (
        SCRATCH_ROOT.is_symlink()
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_mode & 0o077
    ):
        raise ValueError("/tmp/codex は本人所有の private directory が必要です")
    return Path(tempfile.mkdtemp(prefix=prefix, dir=SCRATCH_ROOT))


def _git_environment() -> dict[str, str]:
    # Nix 前の bootstrap なので公開 package を import せず、固定版との同一性をテストする。
    return {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }


def create_environment(runtime: Path) -> dict[str, str]:
    environment = _git_environment()
    if not environment.get("BROWSER_OWNERSHIP_DIR"):
        environment["BROWSER_OWNERSHIP_DIR"] = str(
            Path(
                environment.get("XDG_RUNTIME_DIR")
                or environment.get("TMPDIR")
                or "/tmp"
            )
            / "browser-ownership"
        )
    for key, name in (
        ("HOME", "home"),
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_RUNTIME_DIR", "runtime"),
        ("XDG_CACHE_HOME", "cache"),
        ("XDG_STATE_HOME", "state"),
        ("TMPDIR", "tmp"),
    ):
        path = runtime / name
        path.mkdir(mode=0o700)
        environment[key] = str(path)
        atexit.register(shutil.rmtree, path, ignore_errors=True)
    for key in (
        "CODEX_HOME",
        "CLAUDE_CONFIG_DIR",
        "CLAUDE_CODE_PLUGIN_CACHE_DIR",
        "FORCE_COLOR",
    ):
        environment.pop(key, None)
    return environment


def sandbox_prefix(source: Path, runtime: Path, original_home: Path) -> list[str]:
    if sys.platform != "linux":
        raise ValueError("書込み保護付き検証は Linux / WSL2 が必要です")
    launcher = shutil.which("bwrap")
    if not launcher:
        raise ValueError("書込み保護に必要な bwrap がありません")
    bwrap = str(Path(launcher).resolve(strict=True))
    if Path(bwrap).parts[:3] != ("/", "nix", "store"):
        raise ValueError("Nix store の bwrap が必要です")
    scratch = SCRATCH_ROOT.resolve(strict=True)
    metadata = SCRATCH_ROOT.stat(follow_symlinks=False)
    if (
        SCRATCH_ROOT.is_symlink()
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_mode & 0o077
        or not runtime.resolve(strict=True).is_relative_to(scratch)
    ):
        raise ValueError("検証用の一時領域が不正です")
    source = source.resolve(strict=True)
    original_home = original_home.resolve(strict=True)
    git_env = _git_environment()
    git_env.update(
        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0"
    )
    paths = subprocess.check_output(
        [
            "git",
            "rev-parse",
            "--path-format=absolute",
            "--show-toplevel",
            "--git-dir",
            "--git-common-dir",
        ],
        cwd=source,
        env=git_env,
        text=True,
    ).splitlines()
    if len(paths) != 3:
        raise ValueError("task worktree の Git metadata を解決できません")
    top, git_dir, common = (Path(path).resolve(strict=True) for path in paths)
    if (
        top != source
        or not (source / ".git").is_file()
        or git_dir.parent != common / "worktrees"
        or Path((git_dir / "gitdir").read_text().strip()).resolve(strict=True)
        != source / ".git"
    ):
        raise ValueError("検証は linked task worktree から実行してください")
    writable = (source, common, git_dir)
    if any(path == original_home or path in original_home.parents for path in writable):
        raise ValueError("通常 HOME 全体への書込みは許可できません")
    prefix = [
        bwrap,
        "--unshare-user",
        "--unshare-pid",
        "--unshare-ipc",
        "--unshare-uts",
        "--die-with-parent",
        "--new-session",
        "--cap-drop",
        "ALL",
        "--ro-bind",
        "/",
        "/",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--bind",
        str(scratch),
        str(scratch),
        "--ro-bind",
        str(original_home),
        str(original_home),
    ]
    for path in writable:
        prefix.extend(["--bind", str(path), str(path)])
    prefix.extend(["--chdir", str(source), "--"])
    (runtime / "boundary.json").write_text(
        json.dumps(
            {
                "source": str(source),
                "original_home": str(original_home),
                "writable_paths": [str(path) for path in writable],
                "scratch": str(scratch),
                "protection": "read-only-host-filesystem",
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    return prefix


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("-- の後に検証コマンドを指定してください")
    runtime = new_runtime("verification-env.")
    print(f"検証ログ: {runtime}", file=sys.stderr, flush=True)
    try:
        prefix = sandbox_prefix(args.source, runtime, Path(os.environ["HOME"]))
        environment = create_environment(runtime)
        result = subprocess.run([*prefix, *command], env=environment)
        status = (
            result.returncode if result.returncode >= 0 else 128 - result.returncode
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"検証環境の起動を拒否しました: {error}", file=sys.stderr)
        status = 1
    (runtime / "exit-code").write_text(f"{status}\n")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
