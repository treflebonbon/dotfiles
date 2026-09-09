#!/usr/bin/env python3
"""Exercise explicit worktree input admission for the #270 isolation prototype."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import runpy
import shutil
import ssl
import stat
import subprocess
import sys
import tempfile
import uuid


DEVENV = runpy.run_path(str(Path(__file__).resolve().parents[1] / "private_dot_local/bin/executable_devshell-env"))
Repository = DEVENV["Repository"]


def git_environment(root, git_dir=None):
    environment = {
        "PATH": os.environ["PATH"],
        "HOME": "/nonexistent",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    if git_dir is not None:
        environment.update(GIT_DIR=str(git_dir), GIT_WORK_TREE=str(root))
    return environment


def git(root, *arguments, git_dir=None, input=None):
    result = subprocess.run(
        ["git", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", str(root), *arguments],
        env=git_environment(root, git_dir), capture_output=True, input=input,
    )
    if result.returncode:
        raise ValueError(f"Git {arguments[0]} failed; no input was published")
    return result.stdout


def read_input(root, name):
    parts = PurePosixPath(name).parts
    if not parts or name != str(PurePosixPath(name)) or any(part in ("/", ".", "..", ".git") for part in parts):
        raise ValueError("input must be a relative file outside Git metadata")
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    finally:
        os.close(directory)
    with os.fdopen(descriptor, "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ValueError("input must be a regular file with one link")
        data = source.read()
        after = os.fstat(source.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise ValueError("input changed while being read")
    return data, {"sha256": hashlib.sha256(data).hexdigest(), "executable": bool(before.st_mode & 0o111)}


def approve(repo, policy, head, names):
    if git(repo.root, "rev-parse", "HEAD").decode().strip() != head:
        raise ValueError("approval must name the current full Git HEAD")
    if policy.resolve().is_relative_to(repo.root) or policy.resolve().is_relative_to(repo.common_dir):
        raise ValueError("input policy must be outside the worktree and Git metadata")
    files = {name: read_input(repo.root, name)[1] for name in names}
    if git(repo.root, "diff", "--cached", "--name-only"):
        raise ValueError("initial approval requires an index matching HEAD")
    if not files:
        raise ValueError("name the public input files explicitly")
    record = {
        "version": 1, "root": str(repo.root), "repository": repo.identity(),
        "git_head": head, "index_tree": git(repo.root, "write-tree").decode().strip(), "files": files,
    }
    with policy.open("x") as destination:
        os.chmod(policy, 0o600)
        json.dump(record, destination, indent=2)
        destination.write("\n")


def prepare(repo, policy, output):
    record = json.loads(read_input(policy.parent, policy.name)[0])
    if record.get("version") != 1 or record.get("root") != str(repo.root) or record.get("repository") != repo.identity():
        raise ValueError("input approval belongs to another worktree or repository")
    head = git(repo.root, "rev-parse", "HEAD").decode().strip()
    if record["git_head"] != head:
        raise ValueError("Git HEAD changed since input approval")
    if git(repo.root, "write-tree").decode().strip() != record["index_tree"]:
        raise ValueError("host index changed since input approval")
    admitted = {}
    for name, expected in record["files"].items():
        data, fingerprint = read_input(repo.root, name)
        if fingerprint != expected:
            raise ValueError("public input changed since approval")
        admitted[name] = data
    branch = git(repo.root, "symbolic-ref", "HEAD").decode().strip()
    git(repo.root, "check-ref-format", branch)
    output.mkdir(mode=0o700)
    fs = output / "root"
    work = fs / str(repo.root).lstrip("/")
    common = fs / str(repo.common_dir).lstrip("/")
    metadata = fs / str(repo.git_dir).lstrip("/")
    work.mkdir(parents=True)
    common.mkdir(parents=True)
    pack = git(repo.root, "pack-objects", "--stdout", "--revs", input=f"{head}\n{record['index_tree']}\n".encode())
    git(common, "init", "--bare", "--quiet")
    git(work, "index-pack", "--stdin", git_dir=common, input=pack)
    git(work, "fsck", "--full", "--no-reflogs", git_dir=common)
    git(work, "config", "core.bare", "false", git_dir=common)
    git(work, "update-ref", branch, head, git_dir=common)
    metadata.mkdir(parents=True)
    (metadata / "HEAD").write_text(f"ref: {branch}\n")
    (metadata / "commondir").write_text(str(repo.common_dir) + "\n")
    (metadata / "gitdir").write_text(str(repo.root / ".git") + "\n")
    (work / ".git").write_text(f"gitdir: {repo.git_dir}\n")
    # Build the index without consulting the absolute pointers, which refer to
    # the original repository until this tree is mounted inside the namespace.
    git(work, "read-tree", record["index_tree"], git_dir=common)
    (common / "index").replace(metadata / "index")
    for name, data in admitted.items():
        target = work / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755 if record["files"][name]["executable"] else 0o644)
    if Repository.discover(repo.root, linked_only=True) != repo or repo.identity() != record["repository"]:
        raise ValueError("Git ownership changed while preparing input")
    if git(repo.root, "rev-parse", "HEAD").decode().strip() != head:
        raise ValueError("Git HEAD changed while preparing input")
    record.update(branch=branch, git_dir=str(repo.git_dir), common_dir=str(repo.common_dir), policy=str(policy.resolve()))
    (output / "session.json").write_text(json.dumps(record, indent=2) + "\n")
    print("public worktree snapshot prepared; host files are not mounted")


def run_isolated(repo, policy, output, command, services, ca_bundle=None):
    if "dependencies" in services and ca_bundle is None:
        raise ValueError("dependency access requires an explicitly selected public CA bundle")
    prepare(repo, policy, output)
    paths = {}
    for name in ("nix", "bash", "cat", "python3", "git", "codex", "gh", "bwrap"):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f"missing isolation tool: {name}")
        path = Path(executable).resolve(strict=True)
        if path.parts[:3] != ("/", "nix", "store"):
            raise ValueError(f"isolation tool must come from the Nix store: {name}")
        paths[name] = Path(*path.parts[:4])
    store = output / "store"
    bootstrap = output / "bootstrap"
    bootstrap.mkdir()
    environment = {
        "HOME": str(bootstrap), "PATH": os.pathsep.join(str(path / "bin") for path in paths.values()),
        "NIX_CONF_DIR": str(bootstrap), "NIX_CONFIG": "experimental-features = nix-command flakes\n",
    }
    with (output / "store-copy.log").open("w") as log:
        subprocess.run([str(paths["nix"] / "bin/nix"), "copy", "--to", str(store), "--no-check-sigs", *map(str, paths.values())],
                       env=environment, stdout=log, stderr=log, check=True, timeout=300)
    result = output / "result"
    result.mkdir()
    gateways = []
    mounts = []
    try:
        gateway_module = runpy.run_path(str(Path(__file__).with_name("secret-isolation-gateway.py")))
        for service in services:
            directory = output / f"gateway-{service}"
            gateways.append(gateway_module["start_gateway"](directory, service))
            mounts.extend(["--ro-bind", str(directory), f"/gateway/{service}"])
    except (KeyError, OSError, ValueError):
        raise ValueError("host tool login is unavailable; no isolated command was started") from None
    script = output / "inside.sh"
    startup = ""
    if "model" in services or "dependencies" in services:
        bridge_script = Path(__file__).with_name("secret-isolation-gateway.py").resolve()
        mounts.extend(["--ro-bind", str(bridge_script), "/gateway-bridge.py"])
        for service, port in (("model", 8123), ("dependencies", 8124)):
            if service not in services:
                continue
            startup += f"python3 /gateway-bridge.py /gateway/{service}/service.sock {port} </dev/null &\n"
            startup += f"python3 - {port} <<'PY'\n" + '''
import socket, sys, time
for attempt in range(100):
    try:
        with socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=1):
            break
    except OSError:
        time.sleep(0.01)
else:
    raise SystemExit('gateway bridge did not start')
PY
'''
    if "dependencies" in services:
        ca = output / "ca-bundle.crt"
        resolved_ca = ca_bundle.resolve(strict=True)
        if not resolved_ca.is_relative_to("/nix/store"):
            raise ValueError("select the public CA bundle from a trusted Nix tool closure")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_verify_locations(cafile=str(resolved_ca))
        ca.write_text("".join(ssl.DER_cert_to_PEM_cert(cert) for cert in context.get_ca_certs(binary_form=True)))
        mounts.extend(["--ro-bind", str(ca), "/ca-bundle.crt"])
        startup += '''export HTTPS_PROXY=http://127.0.0.1:8124 HTTP_PROXY=http://127.0.0.1:8124
export https_proxy=$HTTPS_PROXY http_proxy=$HTTP_PROXY
export NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1
export NIX_SSL_CERT_FILE=/ca-bundle.crt SSL_CERT_FILE=/ca-bundle.crt
'''
    script.write_text('''set -eu
''' + startup + '''
set +e
"$@"
command_status=$?
set -e
git rev-parse HEAD > /result/head
git write-tree > /result/index-tree
git ls-files --cached --others --exclude-standard -z > /result/files
index_commit=$(GIT_AUTHOR_NAME=Isolation GIT_AUTHOR_EMAIL=isolation@example.invalid GIT_COMMITTER_NAME=Isolation GIT_COMMITTER_EMAIL=isolation@example.invalid git commit-tree "$(cat /result/index-tree)" -p HEAD -m 'test: preserve isolated index')
git update-ref refs/isolation/index "$index_commit"
git bundle create /result/commits.bundle HEAD refs/isolation/index
printf '%s\n' "$command_status" > /result/exit-code
''')
    fs = output / "root"
    argv = [
        str(paths["bwrap"] / "bin/bwrap"), "--unshare-all", "--die-with-parent", "--new-session", "--cap-drop", "ALL", "--clearenv",
        "--tmpfs", "/", "--proc", "/proc", "--dev", "/dev", "--dir", "/tmp", "--dir", "/home/agent",
        "--bind", str(store / "nix"), "/nix",
        "--bind", str(fs / str(repo.root).lstrip("/")), str(repo.root),
        "--bind", str(fs / str(repo.common_dir).lstrip("/")), str(repo.common_dir),
        "--bind", str(result), "/result", "--ro-bind", str(script), "/inside.sh",
        *mounts,
        "--symlink", str(paths["bash"] / "bin/bash"), "/bin/sh",
        "--setenv", "HOME", "/home/agent", "--setenv", "PATH", environment["PATH"],
        "--setenv", "NIX_REMOTE", "local",
        "--setenv", "NIX_CONFIG", "experimental-features = nix-command flakes\nbuild-users-group =\nsandbox = false\nsubstituters =\n",
        "--chdir", str(repo.root), str(paths["bash"] / "bin/bash"), "/inside.sh", *command,
    ]
    try:
        completed = subprocess.run(argv, env=environment, timeout=180)
    finally:
        for gateway in gateways:
            gateway.shutdown()
            gateway.server_close()
    if completed.returncode:
        raise ValueError("isolated execution or export failed; the session is retained for recovery")
    return int(read_input(result, "exit-code")[0])


def tree_files(directory, revision):
    result = {}
    for entry in git(directory, "ls-tree", "-rz", revision).split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        if mode not in (b"100644", b"100755") or kind != b"blob":
            raise ValueError("result tree contains a linked or unsupported file")
        result[os.fsdecode(name)] = (mode, oid)
    return result


def check_host_file(root, name, expected):
    target = root
    for part in PurePosixPath(name).parts:
        if part in ("/", ".", "..", ".git"):
            raise ValueError("invalid result path")
        target = target / part
        if target.is_symlink():
            raise ValueError("result path crosses a host link")
    if expected is not None:
        if read_input(root, name)[1] != expected:
            raise ValueError("host input changed; result is retained for recovery")
    elif target.exists():
        raise ValueError("result would replace an unapproved host file")


def install_result_file(root, name, contents, expected):
    parts = PurePosixPath(name).parts
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            try:
                os.mkdir(part, mode=0o755, dir_fd=directory)
            except FileExistsError:
                pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        check_host_file(root, name, expected)
        if contents is None:
            os.unlink(parts[-1], dir_fd=directory)
            return
        data, fingerprint = contents
        temporary = ".isolation-" + uuid.uuid4().hex
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(data)
            os.fchmod(destination.fileno(), 0o755 if fingerprint["executable"] else 0o644)
        os.rename(temporary, parts[-1], src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        os.close(directory)


def return_result(repo, session):
    record = json.loads(read_input(session, "session.json")[0])
    if record["root"] != str(repo.root) or record["repository"] != repo.identity():
        raise ValueError("session belongs to another worktree or repository")
    before = record["git_head"]
    if git(repo.root, "rev-parse", "HEAD").decode().strip() != before or git(repo.root, "symbolic-ref", "HEAD").decode().strip() != record["branch"]:
        raise ValueError("host branch changed; result is retained for recovery")
    if git(repo.root, "write-tree").decode().strip() != record["index_tree"]:
        raise ValueError("host index changed; result is retained for recovery")
    head = read_input(session / "result", "head")[0].decode().strip()
    index_tree = read_input(session / "result", "index-tree")[0].decode().strip()
    if not all(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid) for oid in (head, index_tree)):
        raise ValueError("invalid result object")
    policy = Path(record["policy"])
    policy_before = read_input(policy.parent, policy.name)[0]
    original_policy = json.loads(policy_before)
    if any(original_policy[key] != record[key] for key in original_policy):
        raise ValueError("input approval changed; result is retained for recovery")
    quarantine = Path(tempfile.mkdtemp(prefix="return-", dir=session))
    git(quarantine, "init", "--bare", "--quiet")
    bundle = quarantine / "result.bundle"
    bundle.write_bytes(read_input(session / "result", "commits.bundle")[0])
    git(quarantine, "bundle", "unbundle", str(bundle))
    git(quarantine, "fsck", "--full", "--no-reflogs")
    git(quarantine, "merge-base", "--is-ancestor", before, head)
    old_tree = tree_files(quarantine, before)
    new_tree = tree_files(quarantine, head)
    staged_tree = tree_files(quarantine, index_tree)
    names = {os.fsdecode(name) for name in read_input(session / "result", "files")[0].split(b"\0") if name}
    names.update(record["files"])
    copied_worktree = session / "root" / str(repo.root).lstrip("/")
    files = {}
    for name in names:
        try:
            files[name] = read_input(copied_worktree, name)
        except FileNotFoundError:
            pass
    affected = set(record["files"]) | set(files)
    affected.update(name for name in set(old_tree) | set(new_tree) if old_tree.get(name) != new_tree.get(name))
    affected.update(name for name in set(new_tree) | set(staged_tree) if new_tree.get(name) != staged_tree.get(name))
    for name in affected:
        check_host_file(repo.root, name, record["files"].get(name))
    git(quarantine, "read-tree", index_tree)
    index_bytes = (quarantine / "index").read_bytes()
    git(repo.root, "bundle", "unbundle", str(bundle))
    index_lock = repo.git_dir / "index.lock"
    descriptor = os.open(index_lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(descriptor, "wb") as locked_index:
        locked_index.write(index_bytes)
    process = subprocess.Popen(
        ["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo.root), "update-ref", "--stdin"],
        env=git_environment(repo.root), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    published = False
    try:
        process.stdin.write(f"start\nupdate {record['branch']} {head} {before}\nprepare\n")
        process.stdin.flush()
        if process.stdout.readline().strip() != "start: ok" or process.stdout.readline().strip() != "prepare: ok":
            raise ValueError("host ref changed; result is retained for recovery")
        if Repository.discover(repo.root, linked_only=True) != repo or repo.identity() != record["repository"]:
            raise ValueError("host Git ownership changed")
        for name in sorted(affected):
            contents = files.get(name)
            expected = record["files"].get(name)
            if contents is None and expected is None:
                continue
            if contents is not None and contents[1] == expected:
                continue
            install_result_file(repo.root, name, contents, expected)
        index_lock.replace(repo.git_dir / "index")
        process.stdin.write("commit\n")
        process.stdin.flush()
        if process.stdout.readline().strip() != "commit: ok":
            raise ValueError("ref update failed; staged result is retained for recovery")
        published = True
    finally:
        process.stdin.close()
        process.wait(timeout=10)
        # This lock was exclusively created by this return operation.
        if not published:
            index_lock.unlink(missing_ok=True)
    original_policy.update(git_head=head, index_tree=index_tree, files={name: value[1] for name, value in files.items()})
    with tempfile.NamedTemporaryFile(mode="w", dir=policy.parent, delete=False) as destination:
        json.dump(original_policy, destination, indent=2)
        destination.write("\n")
    os.replace(destination.name, policy)
    print(f"returned HEAD {head}, index and ordinary worktree changes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("approve", "prepare", "run", "return"):
        command = sub.add_parser(name)
        command.add_argument("--root", type=Path, required=True)
        if name != "return":
            command.add_argument("--policy", type=Path, required=True)
        if name == "approve":
            command.add_argument("--git-head", required=True, help="explicitly approve this commit and its reachable Git history as public input")
            command.add_argument("files", nargs="+")
        elif name == "return":
            command.add_argument("--session", type=Path, required=True)
        else:
            command.add_argument("--output", type=Path, required=True)
            if name == "run":
                command.add_argument("--service", action="append", choices=("github", "model", "dependencies"), default=[])
                command.add_argument("--ca-bundle", type=Path)
                command.add_argument("argv", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        repo = Repository.discover(args.root, linked_only=True)
        if args.command == "approve":
            approve(repo, args.policy, args.git_head, args.files)
        elif args.command == "prepare":
            prepare(repo, args.policy, args.output)
        elif args.command == "run":
            command = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
            if not command:
                raise ValueError("run requires a command")
            return run_isolated(repo, args.policy, args.output, command, args.service, args.ca_bundle)
        else:
            return_result(repo, args.session)
    except (OSError, ValueError, DEVENV["InvalidContext"], subprocess.SubprocessError) as error:
        print(f"secret-isolation-worktree: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
