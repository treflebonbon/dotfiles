"""ADR-0082 の旧配備比較と、既知の旧 CLI の復旧用保存。"""

import errno
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


LEGACY_REVISION = "6d5b73dd8b9c88531a74e724ca9d83fa34b44b35"
LEGACY_MANIFEST_SHA256 = "557fbf74853aef1bd89bf5a39d4fb4a45b68123c384167eab832f2eb83ce92ab"
LEGACY_SKILL_NAMES = {
    "dogfood",
    "domain-modeling-studio",
    "herdr-peer-refactor",
    "marp",
    "md-agents-review",
    "md-claude-review",
    "orca-peer-refactor",
    "pr-screenshots",
    "rop",
    "ui-grill-with-docs",
    "worktree-gc",
}
GLOBAL_CLI_NAMES = (
    "git-push-topic",
    "git-push-reviewed",
    "gh-review-thread",
    "orca-send",
    "codex-reviewer",
)


baseline = json.loads(sys.argv[1])


def entry_info(path):
    try:
        return path.lstat()
    except FileNotFoundError:
        return None


def is_symlink(path):
    info = entry_info(path)
    return info is not None and stat.S_ISLNK(info.st_mode)


def matches_file(path, expected):
    flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    descriptor = os.open(path, flags)
    try:
        opened = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened.st_mode)
            or stat.S_IMODE(opened.st_mode) != expected["mode"]
        ):
            return False
        digest = hashlib.sha256()
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
        after_read = os.fstat(descriptor)
        current = entry_info(path)
        return (
            current is not None
            and stat.S_ISREG(current.st_mode)
            and (opened.st_dev, opened.st_ino)
            == (after_read.st_dev, after_read.st_ino)
            == (current.st_dev, current.st_ino)
            and (opened.st_mode, opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns)
            == (
                after_read.st_mode,
                after_read.st_size,
                after_read.st_mtime_ns,
                after_read.st_ctime_ns,
            )
            and digest.hexdigest() == expected["sha256"]
        )
    finally:
        os.close(descriptor)


def save_once(path, payload, mode):
    # 同じ directory から完成済みの file だけを公開し、中断した書込みを復旧資産にしない。
    with tempfile.NamedTemporaryFile(dir=path.parent) as temporary:
        temporary.write(payload)
        temporary.flush()
        os.fchmod(temporary.fileno(), mode)
        os.link(temporary.name, path)


def state_home(home):
    configured = os.environ.get("XDG_STATE_HOME")
    if configured:
        state = Path(configured).expanduser()
        if not state.is_absolute():
            raise ValueError("XDG_STATE_HOME must be absolute")
        return state
    return home / ".local/state"


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
    if stat.S_ISLNK(info.st_mode):
        print(f"skills migration: 保持 {root}: symlink", file=sys.stderr)
        return False
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
                elif not stat.S_ISREG(info.st_mode):
                    differences.append(f"{relative}: 特殊 file")
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


def hold(path, reason):
    print(f"skills migration: 保持 {path}: {reason}", file=sys.stderr)


def canonical_file(path, mode=None):
    info = entry_info(path)
    return (
        info is not None
        and stat.S_ISREG(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and (mode is None or stat.S_IMODE(info.st_mode) == mode)
    )


def verified_plugin_state(source_root, encoded_managed, encoded_plugin):
    try:
        managed = json.loads(encoded_managed)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError(f"managed config 検証結果が JSON ではありません: {error}") from None
    try:
        state = json.loads(encoded_plugin)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError(f"plugin 検証結果が JSON ではありません: {error}") from None
    if (
        not isinstance(managed, dict)
        or managed.get("status") != "verified"
        or not isinstance(state, dict)
        or state.get("status") != "verified"
    ):
        raise ValueError("skills plugin の現在状態が verified ではありません")

    pin_path = source_root / "private_dot_config/nix-devshell/skills-plugin.json"
    if not canonical_file(pin_path):
        raise ValueError(f"固定 pin がありません: {pin_path}")
    pin = json.loads(pin_path.read_text(encoding="utf-8"))
    if state.get("pin") != pin:
        raise ValueError("skills plugin の現在 pin が dotfiles の固定 pin と一致しません")
    if managed.get("pin") != pin:
        raise ValueError("Codex managed config の現在 pin が dotfiles の固定 pin と一致しません")

    source_value = state.get("source")
    if not isinstance(source_value, str) or not Path(source_value).is_absolute():
        raise ValueError("skills plugin の現在 source path が不正です")
    source = Path(source_value)
    if source.resolve(strict=True) != source:
        raise ValueError("skills plugin の現在 source path が canonical ではありません")

    for name in GLOBAL_CLI_NAMES:
        path = source / "bin" / name
        if not canonical_file(path) or not path.stat(follow_symlinks=False).st_mode & 0o111:
            raise ValueError(f"pinned global CLI がありません: {path}")
    module = source / "lib/python/treflebonbon_skills/devshell_environment.py"
    if not canonical_file(module, 0o644):
        raise ValueError(f"pinned global CLI module がありません: {module}")

    rendered_shims = {}
    for name in GLOBAL_CLI_NAMES:
        template = source_root / "private_dot_local/bin" / f"executable_{name}.tmpl"
        if not canonical_file(template):
            raise ValueError(f"global CLI shim template がありません: {template}")
        template_info = template.stat(follow_symlinks=False)
        raw = template.read_bytes()
        guard, separator, body = raw.partition(b"\n")
        if (
            not separator
            or not guard.startswith(bytes((123, 123)) + b'- output "python3"')
            or b"preflight-cli-cutover" not in guard
            or not guard.endswith(b"-}}")
        ):
            raise ValueError(f"global CLI shim に切替 preflight がありません: {template}")
        rendered_shims[name] = (body, stat.S_IMODE(template_info.st_mode))

    home = Path(os.environ["HOME"]).resolve(strict=True)
    for directory in (home / ".local", home / ".local/bin"):
        info = entry_info(directory)
        if info is None or stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ValueError(f"global CLI shim parent が確認できません: {directory}")
    for name, (expected_body, expected_mode) in rendered_shims.items():
        wrapper = home / ".local/bin" / name
        try:
            info = wrapper.stat(follow_symlinks=False)
        except FileNotFoundError:
            info = None
        if (
            info is None
            or not stat.S_ISREG(info.st_mode)
            or stat.S_IMODE(info.st_mode) != expected_mode
            or wrapper.read_bytes() != expected_body
        ):
            raise ValueError(f"current global CLI shim が source と一致しません: {wrapper}")

    homes = state.get("codex_homes")
    if (
        not isinstance(homes, list)
        or not homes
        or any(not isinstance(item, str) or not Path(item).is_absolute() for item in homes)
        or len(set(homes)) != len(homes)
    ):
        raise ValueError("current Codex homes が不正です")
    if managed.get("codex_homes") != homes:
        raise ValueError("Codex managed config と plugin verifier の current homes が一致しません")
    managed_results = managed.get("results")
    managed_codex = managed_results.get("codex") if isinstance(managed_results, dict) else None
    if (
        not isinstance(managed_codex, list)
        or [record.get("codex_home") for record in managed_codex if isinstance(record, dict)] != homes
        or any(not isinstance(record.get("profiles"), list) for record in managed_codex)
    ):
        raise ValueError("Codex managed config の current home/profile 結果が不正です")
    canonical_homes = []
    for item in homes:
        candidate = Path(item)
        if candidate.resolve(strict=True) != candidate or not candidate.is_dir():
            raise ValueError(f"current Codex home を確認できません: {candidate}")
        canonical_homes.append(candidate)
    return home, canonical_homes


def validate_fixed_baseline():
    if baseline.get("revision") != LEGACY_REVISION:
        raise ValueError("旧 skill baseline revision が固定値と一致しません")
    canonical_baseline = json.dumps(
        baseline, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    if hashlib.sha256(canonical_baseline).hexdigest() != LEGACY_MANIFEST_SHA256:
        raise ValueError("旧 skill baseline 内容が固定値と一致しません")
    skills = baseline.get("skills")
    directories = baseline.get("directories")
    if (
        not isinstance(skills, dict)
        or not isinstance(directories, dict)
        or set(skills) != LEGACY_SKILL_NAMES
        or set(directories) != LEGACY_SKILL_NAMES
        or sum(len(entries) for entries in skills.values()) != 113
        or sum(len(entries) for entries in directories.values()) != 39
    ):
        raise ValueError("旧 skill baseline が固定の11 skills / 113 files / 39 directories と一致しません")


def safe_parent_chain(home, parent):
    current = home
    snapshot = []
    for part in parent.parts:
        current = current / part
        info = entry_info(current)
        if info is None:
            return None
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            hold(current, "親 path が symlink または directory ではありません")
            return None
        snapshot.append((current, info.st_dev, info.st_ino, info.st_mode))
    return snapshot


def directory_snapshot(root, expected_dirs):
    snapshot = []
    for relative in sorted(expected_dirs, key=lambda item: (item.count("/"), item)):
        path = root if relative == "." else root / relative
        info = entry_info(path)
        if (
            info is None
            or stat.S_ISLNK(info.st_mode)
            or not stat.S_ISDIR(info.st_mode)
            or stat.S_IMODE(info.st_mode) != expected_dirs[relative]
        ):
            hold(path, "directory inventory が固定 baseline と一致しません")
            return None
        snapshot.append((path, info.st_dev, info.st_ino, info.st_mode))
    return snapshot


def directories_unchanged(snapshot, *, required=None):
    selected = snapshot if required is None else [item for item in snapshot if item[0] in required]
    for path, device, inode, mode in selected:
        info = entry_info(path)
        if (
            info is None
            or stat.S_ISLNK(info.st_mode)
            or not stat.S_ISDIR(info.st_mode)
            or (info.st_dev, info.st_ino, info.st_mode) != (device, inode, mode)
        ):
            hold(path, "親 directory が初回確認後に変わりました")
            return False
    return True


def remove_known_skill(name, target, parent_snapshot):
    if entry_info(target) is None:
        return
    if not check_skill(name, target):
        return
    expected_dirs = baseline["directories"][name]
    skill_snapshot = directory_snapshot(target, expected_dirs)
    if skill_snapshot is None:
        return
    expected = baseline["skills"][name]
    current_path = target
    try:
        for relative in sorted(expected, key=lambda item: (item.count("/"), item), reverse=True):
            path = target / relative
            current_path = path
            parent_relatives = {target}
            if relative != ".":
                relative_parent = Path(relative).parent
                while str(relative_parent) != ".":
                    parent_relatives.add(target / relative_parent)
                    relative_parent = relative_parent.parent
            if (
                not directories_unchanged(parent_snapshot)
                or not directories_unchanged(skill_snapshot, required=parent_relatives)
            ):
                return
            if not matches_file(path, expected[relative]):
                hold(path, "unlink 直前の内容・mode 再照合に失敗しました")
                return
            current = entry_info(path)
            if (
                current is None
                or not stat.S_ISREG(current.st_mode)
                or stat.S_IMODE(current.st_mode) != expected[relative]["mode"]
                or not directories_unchanged(parent_snapshot)
                or not directories_unchanged(skill_snapshot, required=parent_relatives)
            ):
                hold(path, "unlink 直前の path・親 directory 再照合に失敗しました")
                return
            path.unlink()
        for relative in sorted(
            (item for item in expected_dirs if item != "."),
            key=lambda item: (item.count("/"), item),
            reverse=True,
        ):
            path = target / relative
            current_path = path
            required = {target}
            relative_parent = Path(relative)
            while str(relative_parent) != ".":
                required.add(target / relative_parent)
                relative_parent = relative_parent.parent
            if (
                not directories_unchanged(parent_snapshot)
                or not directories_unchanged(skill_snapshot, required=required)
            ):
                return
            info = entry_info(path)
            if (
                info is None
                or not stat.S_ISDIR(info.st_mode)
                or stat.S_IMODE(info.st_mode) != expected_dirs[relative]
            ):
                hold(path, "directory の unlink 直前再照合に失敗しました")
                return
            path.rmdir()
        if not directories_unchanged(parent_snapshot):
            return
        if not directories_unchanged(skill_snapshot, required={target}):
            return
        current_path = target
        info = entry_info(target)
        if (
            info is None
            or not stat.S_ISDIR(info.st_mode)
            or stat.S_IMODE(info.st_mode) != expected_dirs["."]
        ):
            hold(target, "root directory の unlink 直前再照合に失敗しました")
            return
        target.rmdir()
        print(f"skills migration: 旧 baseline copy を撤去しました: {target}", file=sys.stderr)
    except OSError as error:
        if error.errno == errno.ENOTEMPTY:
            try:
                for entry in os.scandir(current_path):
                    hold(Path(entry.path), "撤去中に追加された項目が残りました")
            except OSError:
                hold(current_path, f"撤去中に内容を検査できません ({error.strerror})")
        else:
            hold(current_path, f"撤去中に検査できない項目が残りました ({error.strerror})")


def retire_known_skills(source_root, encoded_managed, encoded_plugin, apm_names):
    validate_fixed_baseline()
    home, codex_homes = verified_plugin_state(source_root, encoded_managed, encoded_plugin)
    protected = set(apm_names)
    targets = [(home, Path(".agents/skills")), (home, Path(".claude/skills"))]
    targets.extend((candidate, Path("skills")) for candidate in codex_homes)
    seen = set()
    for base, relative_root in targets:
        skills_root = base / relative_root
        if skills_root in seen:
            continue
        seen.add(skills_root)
        parent_snapshot = safe_parent_chain(base, relative_root)
        if parent_snapshot is None:
            continue
        for name in sorted(LEGACY_SKILL_NAMES):
            if name in protected:
                hold(skills_root / name, "現在の APM lock が所有しています")
                continue
            remove_known_skill(name, skills_root / name, parent_snapshot)


def prepare():
    home = Path(os.environ["HOME"]).resolve()
    state = state_home(home)
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


def preflight_cli_cutover(source_root):
    home = Path(os.environ["HOME"]).resolve()
    state = state_home(home)
    destination = state / "treflebonbon-skills/legacy" / baseline["revision"]
    cli_names = (
        "git-push-topic",
        "git-push-reviewed",
        "gh-review-thread",
        "orca-send",
        "codex-reviewer",
    )
    source_root = Path(source_root).resolve(strict=True)

    def shim_template(name):
        source = source_root / "private_dot_local/bin" / f"executable_{name}.tmpl"
        source_info = entry_info(source)
        if (
            source_info is None
            or not stat.S_ISREG(source_info.st_mode)
            or not source_info.st_mode & 0o111
        ):
            raise ValueError(f"新しい CLI shim がありません: {source}")
        source_template = source.read_bytes()
        guard, separator, rendered = source_template.partition(b"\n")
        if (
            not separator
            or not guard.startswith(bytes((123, 123, 45)) + b' output "python3"')
            or b"preflight-cli-cutover" not in guard
            or not guard.endswith(bytes((45, 125, 125)))
        ):
            raise ValueError(f"新しい CLI shim に切替 preflight がありません: {source}")
        return rendered, stat.S_IMODE(source_info.st_mode)

    rendered_shims = {name: shim_template(name) for name in cli_names}

    def require_saved_backup(relative):
        manifest = destination / "baseline.json"
        info = entry_info(manifest)
        expected_manifest = (
            json.dumps(baseline, sort_keys=True, ensure_ascii=False) + "\n"
        )
        if (
            info is None
            or not stat.S_ISREG(info.st_mode)
            or stat.S_IMODE(info.st_mode) != 0o600
            or manifest.read_text(encoding="utf-8") != expected_manifest
        ):
            raise ValueError(
                "旧 CLI 切替を保留します: 固定 backup manifest がありません"
            )
        expected = baseline["cli"][relative]
        saved = destination / relative
        if (
            entry_info(saved) is None
            or is_symlink(saved)
            or not matches_file(saved, expected)
        ):
            raise ValueError(
                f"旧 CLI 切替を保留します: 既知 backup がありません: {relative}"
            )

    for name in cli_names:
        relative = f".local/bin/{name}"
        current = home / relative
        rendered, mode = rendered_shims[name]
        current_info = entry_info(current)
        if current_info is None:
            continue
        if stat.S_ISREG(current_info.st_mode) and matches_file(
            current,
            {
                "sha256": hashlib.sha256(rendered).hexdigest(),
                "mode": mode,
            },
        ):
            continue

        expected = baseline["cli"][relative]
        known_legacy = not is_symlink(current) and matches_file(current, expected)
        if name == "git-push-reviewed" and is_symlink(current):
            alias = home / ".local/bin/git-push-topic"
            topic_rendered, topic_mode = rendered_shims["git-push-topic"]
            known_legacy = (
                os.readlink(current) == "git-push-topic"
                and not is_symlink(alias)
                and (
                    matches_file(alias, baseline["cli"][".local/bin/git-push-topic"])
                    or matches_file(
                        alias,
                        {
                            "sha256": hashlib.sha256(topic_rendered).hexdigest(),
                            "mode": topic_mode,
                        },
                    )
                )
            )
        if not known_legacy:
            raise ValueError(
                f"旧 CLI 切替を保留します: 未知の内容を保持します: {current}"
            )

        require_saved_backup(relative)
        if name == "codex-reviewer":
            require_saved_backup(".local/share/devshell-env/devshell_environment.py")


def main():
    action, *arguments = sys.argv[2:]
    try:
        if action == "prepare":
            prepare()
        elif action == "preflight-cli-cutover":
            preflight_cli_cutover(arguments[0])
        elif action == "retire-known-skills":
            retire_known_skills(
                Path(arguments[0]).resolve(strict=True), arguments[1], arguments[2], arguments[3:]
            )
        elif action == "check-skill":
            raise SystemExit(0 if check_skill(arguments[0], Path(arguments[1])) else 1)
        else:
            raise ValueError(f"不明な処理: {action}")
    except (OSError, ValueError) as error:
        raise SystemExit(f"skills migration: {error}") from None


if __name__ == "__main__":
    main()
