"""Repository trust and verified project devShell environments."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from urllib.parse import quote


class InvalidContext(Exception):
    pass


class PreparationError(Exception):
    pass


def executable(name):
    path = shutil.which(name)
    return str(Path(path).resolve(strict=True)) if path else None


def git_environment():
    return {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }


def git_path(directory, option):
    result = subprocess.run(
        ["git", "-C", str(directory), "rev-parse", "--path-format=absolute", option],
        env=git_environment(),
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.rstrip("\n")).resolve(strict=True)


def metadata_target(path, prefix=""):
    if path.is_symlink():
        raise InvalidContext("symlinked Git metadata pointer")
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) != 1 or not lines[0].startswith(prefix):
        raise InvalidContext("invalid Git metadata pointer")
    target = lines[0][len(prefix) :].strip()
    if not target:
        raise InvalidContext("empty Git metadata pointer")
    return (path.parent / target).resolve(strict=True)


@dataclass(frozen=True)
class Repository:
    root: Path
    git_dir: Path
    common_dir: Path
    _linked_only: bool = field(default=False, compare=False, repr=False)
    _allow_gitfile: bool = field(default=False, compare=False, repr=False)

    @classmethod
    def discover(cls, directory, linked_only=False, *, allow_gitfile=False):
        try:
            root = git_path(directory, "--show-toplevel")
            git_dir = git_path(root, "--git-dir")
            common = git_path(root, "--git-common-dir")
            pointer = root / ".git"
            if pointer.is_symlink():
                raise InvalidContext("symlinked worktree metadata")
            if git_dir == common:
                # Unlinked gitfiles have no ownership backlink; only explicit
                # commands may accept them, never automatic trust or raw launch.
                if linked_only or not (
                    (pointer.is_dir() and pointer.resolve() == common)
                    or (
                        allow_gitfile
                        and pointer.is_file()
                        and metadata_target(pointer, "gitdir:") == git_dir
                    )
                ):
                    raise InvalidContext(
                        "current directory is not a linked Git worktree"
                    )
            elif not (
                metadata_target(pointer, "gitdir:") == git_dir
                and metadata_target(git_dir / "commondir") == common
                and git_dir.parent == common / "worktrees"
                and metadata_target(git_dir / "gitdir") == pointer
            ):
                raise InvalidContext(
                    "linked worktree metadata ownership does not match"
                )
            return cls(root, git_dir, common, linked_only, allow_gitfile)
        except (
            OSError,
            ValueError,
            RuntimeError,
            subprocess.CalledProcessError,
        ) as error:
            raise InvalidContext("cannot resolve Git worktree metadata") from error

    def check_unchanged(self, identity):
        if (
            self.discover(
                self.root, self._linked_only, allow_gitfile=self._allow_gitfile
            )
            != self
            or self.identity() != identity
        ):
            raise InvalidContext("worktree metadata changed during preparation")

    def identity(self):
        stat = self.common_dir.stat()
        return {
            "common_dir": str(self.common_dir),
            "device": stat.st_dev,
            "inode": stat.st_ino,
        }


def trust_file(repo):
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    directory = (state / "devshell-env/trust").resolve()
    ancestor = directory
    while not ancestor.exists():
        ancestor = ancestor.parent
    result = subprocess.run(
        ["git", "-C", str(ancestor), "rev-parse", "--git-dir"],
        env=git_environment(),
        capture_output=True,
    )
    if result.returncode == 0 or directory.is_relative_to(repo.common_dir):
        raise InvalidContext(
            "trust state must be outside repositories and Git metadata"
        )
    digest = hashlib.sha256(os.fsencode(repo.common_dir)).hexdigest()
    return directory / (digest + ".json")


def trusted(repo):
    path = trust_file(repo)
    if path.is_symlink():
        raise InvalidContext("symlinked trust record")
    try:
        return json.loads(path.read_text()) == repo.identity()
    except FileNotFoundError:
        return False


def trust_command(command, repo):
    path = trust_file(repo)
    if command == "trust":
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=path.parent, delete=False
        ) as output:
            json.dump(repo.identity(), output)
        os.replace(output.name, path)
    elif command == "untrust":
        path.unlink(missing_ok=True)
    state = "trusted" if trusted(repo) else "untrusted"
    flake = "flake present" if (repo.root / "flake.nix").is_file() else "no flake"
    print(f"devshell-env: {state}; {flake}; {repo.root}")


def selected_output(repo):
    explicit = os.environ.get("DEVSHELL_ENV_OUTPUT")
    if explicit:
        if not all(
            part and all(c.isalnum() or c in "_-" for c in part)
            for part in explicit.split(".")
        ):
            raise PreparationError(
                "DEVSHELL_ENV_OUTPUT must name an output in the current flake"
            )
        return explicit
    release = Path("/proc/sys/kernel/osrelease")
    wsl = bool(os.environ.get("WSL_DISTRO_NAME")) or (
        release.is_file()
        and any(word in release.read_text().lower() for word in ("microsoft", "wsl"))
    )
    return "wsl" if wsl and (repo.root / ".wsl-browser-free").is_file() else "default"


def prepared_context(repo):
    files = {}
    for name in ("flake.nix", "flake.lock"):
        path = repo.root / name
        files[name] = (
            hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
        )
    return json.dumps(
        {
            "root": str(repo.root),
            "repository": repo.identity(),
            "output": selected_output(repo),
            "files": files,
        },
        sort_keys=True,
    )


def prepare_environment(
    repo, inherited, require_trust=True, timeout=None, *, isolated=False
):
    identity = repo.identity()
    repo.check_unchanged(identity)
    if require_trust and not trusted(repo):
        raise PreparationError("untrusted repository; run devshell-env trust")
    if not (repo.root / "flake.nix").is_file():
        raise PreparationError("no flake.nix at the worktree root")
    output = selected_output(repo)
    context = prepared_context(repo)
    nix = executable("nix")
    bash = executable("bash")
    if not nix or not bash:
        raise PreparationError("nix and bash are required")
    # Do not feed inherited secrets or direnv's Nix selection into persisted Nix output.
    bootstrap = {
        key: inherited[key]
        for key in (
            "HOME",
            "USER",
            "LOGNAME",
            "PATH",
            "XDG_CACHE_HOME",
            "NIX_REMOTE",
            "NIX_SSL_CERT_FILE",
            "SSL_CERT_FILE",
        )
        if key in inherited
    }
    bootstrap["TMPDIR"] = "/tmp"
    if isolated:
        # These values were created by the outer launcher after isolation.
        # Human/Claude preparation keeps its existing bootstrap contract.
        for key in (
            "NIX_CONFIG",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "http_proxy",
            "https_proxy",
            "NO_PROXY",
            "no_proxy",
        ):
            if key in inherited:
                bootstrap[key] = inherited[key]
    result = subprocess.run(
        [
            nix,
            "--extra-experimental-features",
            "nix-command flakes",
            "print-dev-env",
            "--no-write-lock-file",
            f"git+file://{quote(str(repo.root), safe='/')}#{output}",
        ],
        cwd=repo.root,
        env=bootstrap,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode:
        raise PreparationError(
            f"Nix preparation failed ({result.returncode}): {result.stderr.strip()}"
        )
    # Shell code and its environment travel through pipes, never a project environment cache.
    script = """
set -e
eval "$(cat)" >&2
exec "$1" -I -c 'import json,os; print(json.dumps(dict(os.environ)))'
"""
    result = subprocess.run(
        [bash, "--noprofile", "--norc", "-c", script, "devshell-env", sys.executable],
        input=result.stdout,
        cwd=repo.root,
        env=bootstrap,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode:
        raise PreparationError(
            f"shellHook preparation failed ({result.returncode}): {result.stderr.strip()}"
        )
    prepared = json.loads(result.stdout)
    if not isinstance(prepared, dict) or not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in prepared.items()
    ):
        raise PreparationError("invalid devShell environment output")
    environment = inherited.copy()
    for key, value in prepared.items():
        if key in {
            "HOME",
            "USER",
            "LOGNAME",
            "PWD",
            "OLDPWD",
            "TMPDIR",
            "SHLVL",
            "_",
            "SHELL",
            "BASH_ENV",
            "ENV",
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_RUNTIME_DIR",
        }:
            continue
        if key.startswith(("GIT_", "CODEX_", "DEVSHELL_ENV_")):
            continue
        if bootstrap.get(key) != value:
            environment[key] = value
    paths = (prepared.get("PATH", "") + os.pathsep + inherited.get("PATH", "")).split(
        os.pathsep
    )
    environment["PATH"] = os.pathsep.join(dict.fromkeys(path for path in paths if path))
    repo.check_unchanged(identity)
    if prepared_context(repo) != context:
        raise PreparationError("flake changed during preparation; restart the session")
    environment["DEVSHELL_ENV_CONTEXT"] = context
    print(f"devshell-env: ready; {repo.root}#{output}", file=sys.stderr)
    return environment


def reuse_environment(repo, inherited):
    identity = repo.identity()
    repo.check_unchanged(identity)
    context = inherited.get("DEVSHELL_ENV_CONTEXT")
    if not context:
        raise PreparationError("no prepared devShell; restart through codex-worktree")
    if context != prepared_context(repo):
        raise PreparationError(
            "prepared devShell belongs to another root or flake; restart the session"
        )
    repo.check_unchanged(identity)
    return inherited
