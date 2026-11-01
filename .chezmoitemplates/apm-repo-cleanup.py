import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import uuid
from contextlib import ExitStack


root = Path(sys.argv[1]).resolve()
targets = (
    ".agents", ".codex/agents", ".codex/hooks.json", ".codex/skills",
    ".claude/agents", ".claude/commands", ".claude/hooks",
    ".claude/skills", ".claude/apm-hooks.json",
)


def in_scope(path):
    return any(path == target or path.startswith(target + "/") for target in targets)


def hold(path, reason):
    print(f"orphan-claude-skills: 保持 {root / path}: {reason}", file=sys.stderr)


def identity(info):
    return info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns


hashes = {}
for dependency in json.load(sys.stdin)["dependencies"]:
    for path, digest in dependency.get("deployed_file_hashes", {}).items():
        if not in_scope(path):
            continue
        if (
            str(PurePosixPath(path)) != path
            or ".." in PurePosixPath(path).parts
            or path not in dependency["deployed_files"]
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
            or (path in hashes and hashes[path] != digest)
        ):
            raise ValueError(f"APM 台帳が不正または競合しています: {path}")
        hashes[path] = digest

if not shutil.which("mountpoint"):
    hold(".", "mountpoint がなく配備先の安全を確認できません")
    sys.exit(0)


directory_identities = {}


def remember_directory(path, descriptor):
    info = os.fstat(descriptor)
    observed = info.st_dev, info.st_ino
    if directory_identities.setdefault(path, observed) != observed:
        raise OSError("検査中に directory が変更されました")


def open_parent(path, stack):
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    stack.callback(os.close, descriptor)
    remember_directory(".", descriptor)
    parent = root
    for part in PurePosixPath(path).parts[:-1]:
        parent = parent / part
        mounted = subprocess.run(
            ["mountpoint", "-q", str(parent)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode
        if mounted != 32:
            raise OSError("mounted directory または mount の検査失敗")
        descriptor = os.open(
            part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor
        )
        stack.callback(os.close, descriptor)
        remember_directory(str(parent.relative_to(root)), descriptor)
    return descriptor


directories = set()
for path, digest in sorted(hashes.items()):
    try:
        before_claim = (root / path).lstat()
        if not stat.S_ISREG(before_claim.st_mode):
            raise OSError("通常 file ではありません")
        with ExitStack() as stack:
            parent = open_parent(path, stack)
            name = PurePosixPath(path).name
            quarantine = ".apm-retire." + uuid.uuid4().hex
            os.mkdir(quarantine, mode=0o700, dir_fd=parent)
            quarantine_fd = os.open(
                quarantine, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent
            )
            stack.callback(os.close, quarantine_fd)
            claimed = False
            try:
                # 元の path への並行書込みと、撤去する inode を分ける。
                os.rename(name, "payload", src_dir_fd=parent, dst_dir_fd=quarantine_fd)
                claimed = True
                descriptor = os.open(
                    "payload", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                    dir_fd=quarantine_fd,
                )
                with os.fdopen(descriptor, "rb") as stream:
                    before = os.fstat(stream.fileno())
                    if not stat.S_ISREG(before.st_mode):
                        raise OSError("通常 file ではありません")
                    contents = stream.read()
                    after = os.fstat(stream.fileno())
                if identity(before_claim) != identity(before) or identity(before) != identity(after):
                    raise OSError("検査中に file が変更されました")
                if digest not in {
                    "sha256:" + hashlib.sha256(value).hexdigest()
                    for value in (contents, contents.replace(b"\r\n", b"\n"))
                }:
                    hold(path, "APM 台帳と内容が一致しません")
                    continue
                open_parent(path, stack)
                current = os.stat("payload", dir_fd=quarantine_fd, follow_symlinks=False)
                if identity(after) != identity(current):
                    raise OSError("検査中に file が変更されました")
                os.unlink("payload", dir_fd=quarantine_fd)
                claimed = False
                for directory in PurePosixPath(path).parents:
                    if in_scope(str(directory)):
                        directories.add(str(directory))
            finally:
                if claimed:
                    try:
                        # 既に作成された新しい file を上書きせず、元の directory へ戻す。
                        os.link(
                            "payload", name, src_dir_fd=quarantine_fd,
                            dst_dir_fd=parent, follow_symlinks=False,
                        )
                        os.unlink("payload", dir_fd=quarantine_fd)
                    except OSError as error:
                        hold(str(PurePosixPath(path).parent / quarantine / "payload"),
                             f"元の path へ復元できないため退避を保持します: {error}")
                try:
                    os.rmdir(quarantine, dir_fd=parent)
                except OSError as error:
                    hold(str(PurePosixPath(path).parent / quarantine), str(error))
    except FileNotFoundError:
        continue
    except OSError as error:
        hold(path, str(error))

for path in sorted(directories, key=lambda value: (value.count("/"), value), reverse=True):
    try:
        with ExitStack() as stack:
            parent = open_parent(path, stack)
            info = os.stat(PurePosixPath(path).name, dir_fd=parent, follow_symlinks=False)
            if directory_identities.get(path) != (info.st_dev, info.st_ino):
                raise OSError("撤去前に directory が変更されました")
            os.rmdir(PurePosixPath(path).name, dir_fd=parent)
    except OSError as error:
        hold(path, str(error))

for path in targets:
    try:
        (root / path).lstat()
    except FileNotFoundError:
        continue
    except OSError as error:
        hold(path, str(error))
    else:
        hold(path, "台帳で撤去を確認できない項目が残っています")
