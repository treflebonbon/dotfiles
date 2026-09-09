"""Verify the public with-env package through the real raw Codex sandbox."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

source = Path(__file__).resolve().parents[2]
fixture = Path(tempfile.mkdtemp(prefix="with-env-257-preflight-", dir="/tmp"))
# Read-only exceptions beneath denied /tmp are hidden by Codex's Linux mount plan.
# Installed home tools live outside /tmp; exercise that real deployment layout too.
home = Path(tempfile.mkdtemp(prefix="with-env-257-home-", dir=Path.home()))
config = home / ".codex"
config.mkdir()
repo = fixture / "repo"
work = fixture / "worktree"
sibling = fixture / "sibling"
runtime = home / ".local/bin"
runtime.mkdir(parents=True)
env = dict(os.environ, HOME=str(home), CODEX_HOME=str(config), TMPDIR="/tmp")
env["XDG_STATE_HOME"] = str(home / "state")
env["XDG_CACHE_HOME"] = str(home / "cache")
env["PATH"] = str(runtime) + os.pathsep + os.environ["PATH"]
env.pop("DEVSHELL_ENV_CONTEXT", None)
env.pop("DEVSHELL_ENV_OUTPUT", None)
dummy = str(uuid.uuid4())
inherited_dummy = str(uuid.uuid4())
env["INHERITED_257"] = inherited_dummy


def run(args, **kwargs):
    return subprocess.run(args, env=env, text=True, capture_output=True, **kwargs)


run(["git", "init", "-q", str(repo)], check=True)
for key, value in [("user.name", "Test"), ("user.email", "test@example.com")]:
    run(["git", "-C", str(repo), "config", key, value], check=True)
run(
    ["git", "-C", str(repo), "commit", "--allow-empty", "-qm", "test: fixture"],
    check=True,
)
for branch, directory in [("task", work), ("sibling", sibling)]:
    run(
        ["git", "-C", str(repo), "worktree", "add", "-qb", branch, str(directory)],
        check=True,
    )
nixpkgs = run(
    [
        "nix",
        "eval",
        "--offline",
        "--impure",
        "--raw",
        "--expr",
        f"(builtins.getFlake {json.dumps(str(source))}).inputs.nixpkgs.outPath",
    ],
    check=True,
).stdout
system = run(
    ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], check=True
).stdout
(work / "flake.nix").write_text(f'''{{
  inputs.nixpkgs.url = "path:{nixpkgs}";
  inputs.dotfiles.url = "git+file://{source}";
  outputs = {{ nixpkgs, dotfiles, ... }}: {{
    devShells.{system}.default = let pkgs = import nixpkgs {{ system = "{system}"; }}; in pkgs.mkShell {{
      packages = [ dotfiles.packages.{system}.with-env pkgs.hello
        (pkgs.writeShellScriptBin "git" ''exec ${{pkgs.git}}/bin/git "$@"'')
      ];
      PROJECT_257 = "prepared";
      shellHook = ''
        test -z "''${{DOTENV_257+x}}"
        test -z "''${{INHERITED_257+x}}"
        printf 'hook\\n' >> hook-calls
        export HOOK_257=ready
      '';
    }};
  }};
}}''')
run(["git", "-C", str(work), "add", "flake.nix"], check=True)
managed = run(
    [
        "chezmoi",
        "--source",
        str(source),
        "execute-template",
        "-f",
        str(source / "private_dot_config/codex/config.toml.tmpl"),
    ],
    check=True,
).stdout
# Include both local and inherited extra roots; the read grant must reach neither.
(config / "config.toml").write_text(
    managed.replace('extends = ":workspace"', 'extends = "fixture-parent"', 1)
    + f"""\n[permissions.fixture-parent]
extends = ":workspace"
[permissions.fixture-parent.workspace_roots]
{json.dumps(str(sibling))} = true
[permissions.dotfiles-secure.workspace_roots]
{json.dumps(str(repo))} = true
"""
)
for name in ("codex-worktree", "devshell-env", "git-push-topic"):
    shutil.copyfile(
        source / ("private_dot_local/bin/executable_" + name), runtime / name
    )
    (runtime / name).chmod(0o755)
cli = str(runtime / "devshell-env")
adapter = str(runtime / "codex-worktree")
(work / ".env").write_text("DOTENV_257=" + dummy + "\n")
(work / ".envrc").write_text("touch envrc-was-read\n")
protected = [
    work / "sub/.env",
    work / "sub/deep/.env",
    work / ".env.local",
    work / ".env-secret",
    work / ".envrc.local",
    work / ".env.example.local",
    *[
        work / name
        for name in (
            "private.pem",
            "private.key",
            "private.pfx",
            "private.p12",
            "credentials.json",
            "credentials.dev.json",
            "secret.json",
            "secrets.json",
            "service-account-test.json",
        )
    ],
    repo / ".env",
    sibling / ".env",
    fixture / ".env",
    home / "other-repo/.env",
    home / ".ssh/config",
    home / ".aws/credentials",
    home / ".config/gcloud/credentials.json",
    runtime / ".env",
    home / ".config/git/.env",
    home / ".config/gh/.env",
]
for path in protected:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("protected\n")
(work / "protected.json").write_text(json.dumps([str(path) for path in protected]))
(work / "observe.py").write_text("""import os, subprocess, shutil
from pathlib import Path
import json
assert "DOTENV_257" not in os.environ
assert os.environ["INHERITED_257"]
Path("temporary-path").write_text(os.environ["TMPDIR"])
assert os.environ["PROJECT_257"] == "prepared" and os.environ["HOOK_257"] == "ready"
assert Path("hook-calls").read_text() == "hook\\n"
assert not Path("envrc-was-read").exists()
assert Path(".env").read_text().startswith("DOTENV_257=")
for path in [Path(".env"), *map(Path, json.loads(Path("protected.json").read_text()))]:
    if path != Path(".env"):
        try:
            path.read_bytes()
        except OSError:
            pass
        else:
            raise AssertionError("unexpected read: " + str(path))
    try:
        with path.open("a"):
            pass
    except OSError:
        pass
    else:
        raise AssertionError("unexpected write: " + str(path))
result = subprocess.run(["with-env", "--prepared", "--", "python3", "child.py", "two words", "", shutil.which("git")])
assert result.returncode == 23
assert "DOTENV_257" not in os.environ
assert Path("hook-calls").read_text() == "hook\\n"
Path("git-write.txt").write_text("fixture\\n")
subprocess.run(["git", "add", "git-write.txt"], check=True)
subprocess.run(["git", "commit", "-qm", "test: sandboxed write"], check=True)
assert Path.home().joinpath(".local/bin/git-push-topic").read_text().startswith("#!/")
assert os.environ.get("CODEX_NETWORK_PROXY_ACTIVE")
subprocess.run(["curl", "--silent", "--show-error", "--fail", "--max-time", "20",
                "https://registry.npmjs.org/-/ping"], check=True, stdout=subprocess.DEVNULL)
r = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "20",
                    "https://example.com/"], capture_output=True, text=True)
assert r.returncode != 0 and "response 403" in r.stderr
print("sandbox environment, secrets, Git, tools and network passed")
""")
(work / "child.py").write_text("""import os, subprocess, sys, shutil
from pathlib import Path
assert sys.argv[1:3] == ["two words", ""]
assert shutil.which("git") == sys.argv[3]
assert os.environ["DOTENV_257"] == Path(".env").read_text().strip().split("=", 1)[1]
subprocess.run(["hello"], check=True)
subprocess.run(["sh", "-c", 'test -n "$DOTENV_257"'], check=True)
sys.exit(23)
""")


def sandbox(label, command, success=True):
    result = run(
        [adapter, "sandbox", "-P", "dotfiles-secure", "--", *command], cwd=work
    )
    assert dummy not in result.stdout + result.stderr
    assert inherited_dummy not in result.stdout + result.stderr
    (fixture / (label + ".log")).write_text(result.stdout + result.stderr)
    assert (result.returncode == 0) == success, (
        f"{label}: {result.stderr} {result.stdout}"
    )
    print(f"{label}: exit={result.returncode}", flush=True)


sandbox("untrusted", ["cat", ".env"], False)
run([cli, "trust", str(work)], check=True)
sandbox("trusted", ["python3", "observe.py"])
app = run(
    ["nix", "eval", "--raw", f"{source}#apps.{system}.with-env.program"], check=True
).stdout.strip()
run([cli, "untrust", str(work)], check=True)
sandbox("revoked", ["cat", ".env"], False)
run([cli, "trust", str(work)], check=True)
(work / ".env").rename(work / ".env.saved")
sandbox(
    "absent",
    ["with-env", "--prepared", "--", "sh", "-c", 'test "${DOTENV_257-unset}" = unset'],
)
(work / ".env").symlink_to(repo / ".env")
sandbox(
    "external-symlink", ["with-env", "--prepared", "--", "touch", "launched"], False
)
(work / ".env").rename(work / ".env.link")
(work / ".env.saved").rename(work / ".env")
(work / ".env").write_text('INVALID="' + dummy)
sandbox("malformed", ["with-env", "--prepared", "--", "touch", "launched"], False)
(work / ".env").write_text("DOTENV_257=" + dummy + "\n")
(work / "flake.nix").write_text("invalid nix")
sandbox("preparation-failed", ["cat", ".env"], False)
sandbox("unprepared-entry", [app, "--prepared", "--", "touch", "launched"], False)
assert not (work / "launched").exists()
for directory in (home, fixture, Path((work / "temporary-path").read_text())):
    for path in directory.rglob("*"):
        if path.is_file() and not path.is_symlink() and path != work / ".env":
            content = path.read_bytes()
            assert dummy.encode() not in content, f"persisted dotenv in {path}"
            assert inherited_dummy.encode() not in content, (
                f"persisted inherited value in {path}"
            )
print(f"Evidence: {fixture}; isolated home: {home}")
