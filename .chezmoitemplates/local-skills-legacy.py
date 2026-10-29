"""ADR-0082 の旧配備比較と、既知の旧 CLI の復旧用保存。"""

import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


baseline = json.loads(sys.argv[1])
action, *arguments = sys.argv[2:]


def matches_file(path, expected):
    try:
        info = path.stat()
        return (
            stat.S_ISREG(info.st_mode)
            and bool(info.st_mode & 0o111) == expected["executable"]
            and hashlib.sha256(path.read_bytes()).hexdigest() == expected["sha256"]
        )
    except OSError:
        return False


def save_once(path, payload, mode):
    # 同じ directory から完成済みの file だけを公開し、中断した書込みを復旧資産にしない。
    with tempfile.NamedTemporaryFile(dir=path.parent) as temporary:
        temporary.write(payload)
        temporary.flush()
        os.fchmod(temporary.fileno(), mode)
        os.link(temporary.name, path)


def check_skill(name, root):
    expected = baseline["skills"][name]
    if not root.exists() and not root.is_symlink():
        return True
    if root.is_symlink() or not root.is_dir():
        print(f"skills migration: 保持 {root}: 実 directory と確認できません", file=sys.stderr)
        return False
    observed = set()
    differences = []

    def walk_error(error):
        raise error

    try:
        for directory, dirs, files in os.walk(root, onerror=walk_error):
            for entry in dirs + files:
                path = Path(directory) / entry
                relative = path.relative_to(root).as_posix()
                if path.is_symlink():
                    differences.append(f"{relative}: symlink")
                elif path.is_dir():
                    if not any(key.startswith(relative + "/") for key in expected):
                        differences.append(f"{relative}: 追加 directory")
                else:
                    observed.add(relative)
                    if relative not in expected:
                        differences.append(f"{relative}: 追加項目（内容は読取りません）")
                    elif not matches_file(path, expected[relative]):
                        differences.append(f"{relative}: 既知の移行前内容・mode と不一致")
        differences.extend(f"{key}: 欠損" for key in sorted(expected.keys() - observed))
    except OSError as error:
        differences.append(f"読取りを確認できません: {error.strerror}")
    if differences:
        print(f"skills migration: 保持 {root}", file=sys.stderr)
        for difference in differences:
            print(f"  {difference}", file=sys.stderr)
    return not differences


def prepare():
    home = Path(os.environ["HOME"]).resolve()
    state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state"))).resolve()
    destination = state / "treflebonbon-skills/legacy" / baseline["revision"]
    for path in reversed([destination, *destination.parents]):
        if path.is_symlink():
            raise ValueError(f"復旧先が symlink です: {path}")
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    manifest = destination / "baseline.json"
    contents = json.dumps(baseline, sort_keys=True, ensure_ascii=False) + "\n"
    if manifest.is_symlink():
        raise ValueError("復旧用の比較基準が symlink です")
    if manifest.exists():
        if manifest.read_text() != contents:
            raise ValueError("復旧用の比較基準が既知の revision と一致しません")
    else:
        save_once(manifest, contents.encode(), 0o600)
    for relative, expected in baseline["cli"].items():
        source = home / relative
        target = destination / relative
        if any(parent.is_symlink() for parent in target.parents):
            raise ValueError("復旧先の親が symlink です")
        if target.exists() or target.is_symlink():
            if target.is_symlink() or not matches_file(target, expected):
                raise ValueError(f"保存済みの旧 CLI が不正です: {relative}")
            continue
        if not source.exists() and not source.is_symlink():
            continue
        alias = source.with_name("git-push-topic")
        known_alias = False
        if source.is_symlink() and relative == ".local/bin/git-push-reviewed":
            known_alias = os.readlink(source) == "git-push-topic" and not alias.is_symlink()
        if (source.is_symlink() and not known_alias) or not source.resolve().is_relative_to(home):
            print(f"skills migration: 保持 {source}: 未知の CLI 参照先", file=sys.stderr)
            continue
        if not matches_file(source, expected):
            print(f"skills migration: 保持 {source}: 既知の旧 CLI と不一致", file=sys.stderr)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = source.read_bytes()
        if hashlib.sha256(payload).hexdigest() != expected["sha256"]:
            raise ValueError(f"旧 CLI の内容が保存中に変化しました: {relative}")
        save_once(target, payload, 0o755 if expected["executable"] else 0o644)


try:
    if action == "prepare":
        prepare()
    elif action == "check-skill":
        raise SystemExit(0 if check_skill(arguments[0], Path(arguments[1])) else 1)
    else:
        raise ValueError(f"不明な処理: {action}")
except (OSError, ValueError) as error:
    raise SystemExit(f"skills migration: {error}") from None
