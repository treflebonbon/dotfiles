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


def entry_info(path):
    try:
        return path.lstat()
    except FileNotFoundError:
        return None


def is_symlink(path):
    info = entry_info(path)
    return info is not None and stat.S_ISLNK(info.st_mode)


def matches_file(path, expected):
    info = path.stat(follow_symlinks=False)
    return (
        stat.S_ISREG(info.st_mode)
        and stat.S_IMODE(info.st_mode) == expected["mode"]
        and hashlib.sha256(path.read_bytes()).hexdigest() == expected["sha256"]
    )


def save_once(path, payload, mode):
    # 同じ directory から完成済みの file だけを公開し、中断した書込みを復旧資産にしない。
    with tempfile.NamedTemporaryFile(dir=path.parent) as temporary:
        temporary.write(payload)
        temporary.flush()
        os.fchmod(temporary.fileno(), mode)
        os.link(temporary.name, path)


def check_skill(name, root):
    expected = baseline["skills"][name]
    expected_dirs = baseline["directories"][name]
    try:
        info = entry_info(root)
    except OSError as error:
        print(f"skills migration: 保持 {root}: 検査できません ({error.strerror})", file=sys.stderr)
        return False
    if info is None:
        return True
    if not stat.S_ISDIR(info.st_mode):
        print(f"skills migration: 保持 {root}: 実 directory と確認できません", file=sys.stderr)
        return False
    observed = set()
    differences = []
    if stat.S_IMODE(info.st_mode) != expected_dirs["."]:
        differences.append(".: directory の permission が不一致")

    def walk_error(error):
        raise error

    try:
        for directory, dirs, files in os.walk(root, onerror=walk_error):
            for entry in dirs + files:
                path = Path(directory) / entry
                relative = path.relative_to(root).as_posix()
                info = entry_info(path)
                if info is None:
                    differences.append(f"{relative}: 検査中に消失")
                elif stat.S_ISLNK(info.st_mode):
                    differences.append(f"{relative}: symlink")
                elif stat.S_ISDIR(info.st_mode):
                    if relative not in expected_dirs:
                        differences.append(f"{relative}: 追加 directory")
                    elif stat.S_IMODE(info.st_mode) != expected_dirs[relative]:
                        differences.append(f"{relative}: directory の permission が不一致")
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
        if is_symlink(path):
            raise ValueError(f"復旧先が symlink です: {path}")
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    manifest = destination / "baseline.json"
    contents = json.dumps(baseline, sort_keys=True, ensure_ascii=False) + "\n"
    if is_symlink(manifest):
        raise ValueError("復旧用の比較基準が symlink です")
    if entry_info(manifest) is not None:
        if manifest.read_text() != contents:
            raise ValueError("復旧用の比較基準が既知の revision と一致しません")
    else:
        save_once(manifest, contents.encode(), 0o600)
    for relative, expected in baseline["cli"].items():
        source = home / relative
        target = destination / relative
        if any(is_symlink(parent) for parent in target.parents):
            raise ValueError("復旧先の親が symlink です")
        if entry_info(target) is not None:
            if is_symlink(target) or not matches_file(target, expected):
                raise ValueError(f"保存済みの旧 CLI が不正です: {relative}")
            continue
        if entry_info(source) is None:
            continue
        alias = source.with_name("git-push-topic")
        known_alias = False
        if is_symlink(source) and relative == ".local/bin/git-push-reviewed":
            known_alias = os.readlink(source) == "git-push-topic" and not is_symlink(alias)
        if (is_symlink(source) and not known_alias) or not source.resolve(strict=True).is_relative_to(home):
            print(f"skills migration: 保持 {source}: 未知の CLI 参照先", file=sys.stderr)
            continue
        if known_alias:
            source = alias
        if not matches_file(source, expected):
            print(f"skills migration: 保持 {source}: 既知の旧 CLI と不一致", file=sys.stderr)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = source.read_bytes()
        if hashlib.sha256(payload).hexdigest() != expected["sha256"]:
            raise ValueError(f"旧 CLI の内容が保存中に変化しました: {relative}")
        save_once(target, payload, expected["mode"])


try:
    if action == "prepare":
        prepare()
    elif action == "check-skill":
        raise SystemExit(0 if check_skill(arguments[0], Path(arguments[1])) else 1)
    else:
        raise ValueError(f"不明な処理: {action}")
except (OSError, ValueError) as error:
    raise SystemExit(f"skills migration: {error}") from None
