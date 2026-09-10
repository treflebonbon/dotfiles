"""Exercise exported templates in independent repositories using real Nix."""

import argparse
import json
import os
from pathlib import Path
import shlex
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


def run(arguments, cwd, *, environment=None, expected=0, expected_stderr=None):
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
    if expected_stderr is not None:
        assert expected_stderr in result.stderr, result.stderr
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
    # Invalid UTF-8 fails during reading even when UID 0 can bypass file permissions.
    dotenv.write_bytes(b"DOTENV_258=\xff\n")
    run(failure, repo, expected=1, expected_stderr="cannot read root .env")
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
        f"{language}: human dotenv, worktree selection, failures and output selection passed",
        flush=True,
    )
    verify_raw(language, repo, evidence)


def verify_raw(language, repo, evidence):
    """Use the actual #271 entry and the template's actual with-env package."""
    app = run(["nix", "eval", "--raw", ".#apps.x86_64-linux.with-env.program"], repo)
    task = evidence / f"{language}-raw-task.sh"
    task.write_text(
        "set -eu\n"
        + shlex.join(LANGUAGES[language])
        + "\ntest ! -e envrc-executed\n"
        + 'test -z "${RAW_DUMMY_SECRET+x}"\n'
        + 'with-env --prepared -- env TEST_TOKEN=dummy-public sh -c \'test "$TEST_TOKEN" = dummy-public; test "$(cat fixture.txt)" = public\'\n'
        + "set +e\n"
        + shlex.quote(app)
        + " --prepared -- sh -c 'test -z \"${RAW_DUMMY_SECRET+x}\" || exit 42; test \"$1/$2\" = \"two words/\" || exit 43; exit 23' _ 'two words' ''\n"
        + 'status=$?\nset -e\ntest "$status" -eq 23\n'
        # Codex may create an empty deny placeholder; it is not the host dotenv.
        + "python3 - <<'PY'\n"
        + "from pathlib import Path\n"
        + "for name in ('.env', 'ordinary-looking-name', 'nested/renamed', '../repo/.env'):\n"
        + "    path = Path(name)\n"
        + "    try: content = path.read_bytes()\n"
        + "    except (FileNotFoundError, PermissionError): continue\n"
        + "    assert path.name == '.env' and content == b'', name\n"
        + "PY\n"
        + "printf tested > fixture.txt\ngit add fixture.txt\ngit commit -qm 'test: template in raw isolation'\nprintf 'TEMPLATE_RAW_OK\\n'\n"
    )
    temporary = evidence / f"{language}-raw"
    temporary.mkdir()
    script = r"""
set -eu
source "$PROJECT_ROOT/tests/helpers/raw-codex.bash"
raw_fixture
cp "$TEMPLATE_REPO/flake.nix" "$TEMPLATE_REPO/flake.lock" "$RAW_BASE/work/"
cp "$TEMPLATE_RAW_TASK" "$RAW_BASE/work/task.sh"
printf 'public\n' > "$RAW_BASE/work/fixture.txt"
printf 'touch envrc-executed; exit 89\n' > "$RAW_BASE/work/.envrc"
raw_admit flake.nix flake.lock task.sh fixture.txt .envrc
export RAW_DUMMY_SECRET=dummy-template-host-only
raw_run sandbox -- bash task.sh
test "$(cat "$RAW_BASE/work/fixture.txt")" = tested
test "$(git -C "$RAW_BASE/work" log -1 --format=%s)" = 'test: template in raw isolation'
test "$(cat "$RAW_BASE/work/.env")" = RAW_DUMMY_SECRET=dummy-root-secret
raw_run sandbox -- with-env --prepared -- sh -c 'test "$(cat fixture.txt)" = tested'
"""
    output = run(
        ["bash", "-c", script],
        repo,
        environment=os.environ
        | {
            "PROJECT_ROOT": str(SOURCE),
            "BATS_TEST_TMPDIR": str(temporary),
            "TEMPLATE_REPO": str(repo),
            "TEMPLATE_RAW_TASK": str(task),
        },
    )
    assert "TEMPLATE_RAW_OK" in output
    assert "dummy-template-host-only" not in output
    print(
        f"{language}: real raw entry, public app, dummy test, commit and restart passed",
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
