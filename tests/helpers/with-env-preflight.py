"""Reproduce Issue #257's unresolved sandbox premises with isolated dummy data."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


source = Path(__file__).resolve().parents[2]
fixture = Path(tempfile.mkdtemp(prefix="with-env-257-preflight-"))
home = fixture / "home"
config = home / ".codex"
config.mkdir(parents=True)
repo = fixture / "repo"
work = fixture / "worktree"
runtime = fixture / "bin"
runtime.mkdir()
env = dict(os.environ, HOME=str(home), CODEX_HOME=str(config), TMPDIR="/tmp")
env["XDG_STATE_HOME"] = str(fixture / "state")
env["XDG_CACHE_HOME"] = str(home / "cache")
env["PATH"] = str(runtime) + os.pathsep + os.environ["PATH"]


def run(args, **kwargs):
    return subprocess.run(args, env=env, text=True, capture_output=True, **kwargs)


run(["git", "init", "-q", str(repo)], check=True)
run(
    [
        "git",
        "-C",
        str(repo),
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.com",
        "commit",
        "--allow-empty",
        "-qm",
        "test: sandbox fixture",
    ],
    check=True,
)
run(["git", "-C", str(repo), "worktree", "add", "-qb", "task", str(work)], check=True)
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
(work / "flake.nix").write_text(
    f'{{ inputs.nixpkgs.url = "path:{nixpkgs}"; outputs = {{ nixpkgs, ... }}: '
    f'{{ devShells.{system}.default = (import nixpkgs {{ system = "{system}"; }}).mkShell {{ }}; }}; }}'
)
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
(config / "config.toml").write_text(managed)
shutil.copyfile(
    source / "private_dot_local/bin/executable_codex-worktree",
    runtime / "codex-worktree",
)
(runtime / "codex-worktree").chmod(0o755)
(runtime / "devshell-env").symlink_to(
    source / "private_dot_local/bin/executable_devshell-env"
)
run([str(runtime / "devshell-env"), "trust", str(work)], check=True)
(work / "sub").mkdir()
for path in [work / ".env", work / "sub/.env", repo / ".env"]:
    path.write_text("DUMMY=preflight\n")
app = run(
    ["nix", "build", "--no-link", "--print-out-paths", str(source) + "#with-env"],
    check=True,
).stdout.strip()
result = run(
    [
        str(runtime / "codex-worktree"),
        "sandbox",
        "-P",
        "dotfiles-secure",
        "--",
        app + "/bin/with-env",
        "touch",
        "launched",
    ],
    cwd=work,
)
(fixture / "public-app-sandbox.log").write_text(result.stdout + result.stderr)
print(
    f"public app in raw adapter sandbox: exit={result.returncode}, launched={(work / 'launched').exists()}"
)
assert result.returncode != 0 and not (work / "launched").exists()
assert "Nix preparation failed" in result.stderr

# Candidate only: do not publish these rules to the managed source or live config.
(config / "config.toml").write_text(
    managed.replace('"**/.env" = "deny"', '".env" = "deny"\n"*/**/.env" = "deny"')
)
base = [
    "codex",
    "sandbox",
    "-P",
    "dotfiles-secure",
    "-C",
    str(work),
    "-c",
    'permissions.dotfiles-secure.filesystem={":workspace_roots"={".env"="read"}}',
    "--",
]
for name, command, expected in [
    ("root-read", ["cat", ".env"], 0),
    ("root-write", ["sh", "-c", "echo wrong > .env"], 1),
    ("nested-read", ["cat", "sub/.env"], 1),
    ("other-repo-read", ["cat", str(repo / ".env")], 0),
]:
    result = run(base + command)
    (fixture / (name + ".log")).write_text(result.stdout + result.stderr)
    print(f"candidate {name}: exit={result.returncode}")
    assert (result.returncode == 0) == (expected == 0)
print(f"Evidence: {fixture}")
