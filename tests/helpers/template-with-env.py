"""Exercise exported templates in independent repositories using real Nix."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


LANGUAGES = {
    "go": ["go", "version"],
    "rust": ["rustc", "--version"],
    "elixir": ["elixir", "--version"],
    "perl": ["perl", "--version"],
    "gleam": ["gleam", "--version"],
    "bun": ["bun", "--version"],
}
SYSTEMS = ["x86_64-linux", "aarch64-linux", "aarch64-darwin"]
SOURCE = Path(__file__).resolve().parents[2]


def run(arguments, cwd, *, environment=None, expected=0):
    result = subprocess.run(
        arguments,
        cwd=cwd,
        env=environment,
        text=True,
        capture_output=True,
        timeout=1800,
    )
    with (cwd.parent / "commands.log").open("a") as log:
        log.write(f"{cwd}: {arguments!r}\n{result.stdout}{result.stderr}\n")
    assert result.returncode == expected, (
        f"{arguments!r}: exit {result.returncode}, expected {expected}\n"
        f"{result.stdout}{result.stderr}"
    )
    return result.stdout


def verify(language, evidence):
    repo = evidence / language
    repo.mkdir()
    run(["git", "init", "-q"], repo)
    run(["nix", "flake", "init", "-t", f"git+file://{SOURCE}#{language}"], repo)
    run(["git", "add", "flake.nix", ".gitignore", "DEVELOPMENT.md"], repo)
    run(["nix", "flake", "lock"], repo)
    run(["git", "add", "flake.lock"], repo)
    lock = (repo / "flake.lock").read_bytes()
    for system in SYSTEMS:
        app = run(["nix", "eval", "--raw", f".#apps.{system}.with-env.program"], repo)
        assert app.endswith("/bin/with-env"), app
    run(["nix", "flake", "check", "--no-build", "--all-systems"], repo)
    (repo / ".envrc").rename(repo / "envrc-original")
    entry = ["nix", "run", "--no-write-lock-file", ".#with-env", "--"]
    develop = ["nix", "develop", "--no-write-lock-file", ".#default", "-c"]
    run([*develop, *LANGUAGES[language]], repo)
    run([*entry, *LANGUAGES[language]], repo)
    run([*develop, "sh", "-c", "command -v with-env"], repo)
    print(
        f"{language}: three systems evaluated; devShell and with-env executed",
        flush=True,
    )

    # The same entry must work with or without .envrc, and must never source it.
    (repo / ".envrc").write_text("touch envrc-was-read\nexit 89\n")
    run([*develop, *LANGUAGES[language]], repo)
    run([*entry, *LANGUAGES[language]], repo)
    assert not (repo / "envrc-was-read").exists()

    dotenv_dummy, inherited_dummy = str(uuid.uuid4()), str(uuid.uuid4())
    dotenv = repo / ".env"
    dotenv.write_text(f"DOTENV_258={dotenv_dummy}\nOVERRIDE_258=dotenv\n")
    run(["git", "check-ignore", ".env"], repo)
    environment = os.environ | {"OVERRIDE_258": inherited_dummy}
    observer = """
import os, subprocess, sys
assert os.environ['DOTENV_258'] == sys.argv[1]
assert os.environ['OVERRIDE_258'] == sys.argv[2]
assert sys.argv[3:] == ['two words', '', '$(touch must-not-run)']
subprocess.run(['sh', '-c', 'test "$DOTENV_258" = "$1"', '_', sys.argv[1]], check=True)
sys.exit(23)
"""
    run(
        [
            *entry,
            sys.executable,
            "-c",
            observer,
            dotenv_dummy,
            inherited_dummy,
            "two words",
            "",
            "$(touch must-not-run)",
        ],
        repo,
        environment=environment,
        expected=23,
    )
    assert "DOTENV_258" not in os.environ
    assert not (repo / "must-not-run").exists()
    assert not (repo / "envrc-was-read").exists()

    nix_output = run(
        ["nix", "print-dev-env", "--no-write-lock-file"], repo, environment=environment
    )
    host = run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], repo
    )
    derivation = run(
        ["nix", "derivation", "show", f".#devShells.{host}.default"],
        repo,
        environment=environment,
    )
    metadata = json.loads(run(["nix", "flake", "metadata", "--json"], repo))
    source = Path(metadata["path"])
    assert not (source / ".env").exists()
    for dummy in (dotenv_dummy, inherited_dummy):
        assert dummy not in nix_output and dummy not in derivation
        for directory in (
            source,
            Path(os.environ["XDG_CACHE_HOME"]),
            Path(os.environ["HOME"]),
        ):
            for path in directory.rglob("*"):
                if path.is_file():
                    assert dummy.encode() not in path.read_bytes(), path
    (evidence / f"{language}-nix-output").write_text(nix_output)
    (evidence / f"{language}-derivation.json").write_text(derivation)

    dotenv.write_text('BROKEN="dummy\n')
    failure = [*entry, "touch", "launched"]
    run(failure, repo, expected=1)
    dotenv.write_text("DOTENV_258=unreadable\n")
    dotenv.chmod(0)
    try:
        run(failure, repo, expected=1)
    finally:
        dotenv.chmod(0o600)
    dotenv.rename(repo / "dotenv-original")
    dotenv.symlink_to(evidence / ".env")
    run(failure, repo, expected=1)
    dotenv.rename(repo / "dotenv-external-link")
    assert not (repo / "launched").exists()

    # A linked worktree cannot inherit dotenv from main, its parent or its cwd.
    run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "-qm",
            "test: initialize generated template",
        ],
        repo,
    )
    worktree = evidence / f"{language}-worktree"
    run(["git", "worktree", "add", "-qb", "task", str(worktree)], repo)
    (repo / ".env").write_text("DOTENV_258=main\n")
    sub = worktree / "sub"
    sub.mkdir()
    (sub / ".env").write_text("DOTENV_258=subdirectory\n")
    root_entry = ["nix", "run", "--no-write-lock-file", "..#with-env", "--"]
    run([*root_entry, "sh", "-c", 'test "${DOTENV_258-unset}" = unset'], sub)
    (worktree / ".env").write_text("DOTENV_258=current-root\n")
    run(
        [
            *root_entry,
            "sh",
            "-c",
            'test "$DOTENV_258" = current-root && test "$PWD" = "$1"',
            "_",
            str(sub),
        ],
        sub,
    )

    # WSL without a marker uses the provided default even with ambient direnv state.
    wsl_environment = environment | {
        "WSL_DISTRO_NAME": "fixture",
        "DIRENV_ROOT": str(repo),
        "IN_NIX_SHELL": "impure",
    }
    run([*entry, *LANGUAGES[language]], worktree, environment=wsl_environment)
    (worktree / ".wsl-browser-free").touch()
    run(failure, worktree, environment=wsl_environment, expected=1)
    run(
        [*entry, *LANGUAGES[language]],
        worktree,
        environment=wsl_environment | {"DEVSHELL_ENV_OUTPUT": "default"},
    )
    run(
        failure,
        worktree,
        environment=environment | {"DEVSHELL_ENV_OUTPUT": "missing"},
        expected=1,
    )
    assert not (worktree / "launched").exists()
    assert (repo / "flake.lock").read_bytes() == lock
    assert (worktree / "flake.lock").read_bytes() == lock
    print(
        f"{language}: dotenv, isolation, failures, WSL and explicit output passed",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", choices=LANGUAGES, action="append")
    arguments = parser.parse_args()
    evidence = Path(tempfile.mkdtemp(prefix="template-with-env-258-", dir="/tmp"))
    print(f"Evidence: {evidence}", flush=True)
    for key in list(os.environ):
        if key.startswith(("GIT_", "DEVSHELL_ENV_")):
            os.environ.pop(key)
    for name in ("home", "cache"):
        (evidence / name).mkdir()
    os.environ.update(
        HOME=str(evidence / "home"), XDG_CACHE_HOME=str(evidence / "cache")
    )
    (evidence / ".env").write_text("DOTENV_258=parent\n")
    for language in arguments.language or LANGUAGES:
        verify(language, evidence)


if __name__ == "__main__":
    main()
