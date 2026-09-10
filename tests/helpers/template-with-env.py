"""Exercise exported templates in independent repositories using real Nix."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
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


def run(
    arguments, cwd, *, environment=None, expected=0, expected_stderr=None, timeout=1800
):
    result = subprocess.run(
        arguments,
        cwd=cwd,
        env=environment,
        text=True,
        capture_output=True,
        timeout=timeout,
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


def language_tools(language, command, repo):
    def execute(*arguments):
        output = run([*command, *arguments], repo, timeout=180)
        print(f"{language} {arguments!r}: {output.strip()}", flush=True)
        return output

    def write(name, contents):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    if language == "go":
        if not (repo / "go.mod").exists():
            execute("go", "mod", "init", "example.com/template-smoke")
        write("smoke.go", "package smoke\n\nfunc Answer() int { return 42 }\n")
        write(
            "smoke_test.go",
            'package smoke\n\nimport "testing"\n\n'
            "func TestAnswer(t *testing.T) {\n"
            ' if Answer() != 42 { t.Fatal("incorrect answer") }\n}\n',
        )
        execute("gofumpt", "-w", "smoke.go", "smoke_test.go")
        execute("go", "test", "./...")
        execute("gopls", "check", "smoke.go")
        execute("golangci-lint", "run", "--no-config", "./...")
        for arguments in (
            ("gopls", "version"),
            ("air", "-v"),
            ("gotests", "-h"),
            ("gomodifytags", "-h"),
            ("dlv", "version"),
            ("golangci-lint", "version"),
            ("ko", "version"),
            ("wire", "help"),
            ("goreleaser", "--version"),
            ("oapi-codegen", "-version"),
            ("sqlc", "version"),
            ("gofumpt", "-version"),
        ):
            execute(*arguments)
        # impl's public help writes usage to stderr and exits 2.
        run(
            [*command, "impl", "-h"],
            repo,
            expected=2,
            expected_stderr="impl [-dir directory] <recv> <iface>",
            timeout=180,
        )
        print("go impl -h: help displayed (exit 2)", flush=True)
    elif language == "rust":
        write(
            "Cargo.toml",
            '[package]\nname = "template-smoke"\nversion = "0.1.0"\nedition = "2024"\n',
        )
        write(
            "src/lib.rs",
            "pub fn answer() -> u32 { 42 }\n"
            "#[test]\nfn answer_is_available() { assert_eq!(answer(), 42); }\n",
        )
        for arguments in (
            ("cargo", "test", "--offline"),
            ("cargo", "nextest", "run", "--offline"),
            ("cargo", "clippy", "--offline", "--", "-D", "warnings"),
            ("cargo", "fmt"),
            ("rust-analyzer", "--version"),
            ("bacon", "--version"),
            ("cargo", "audit", "--version"),
            ("sqlx", "--version"),
        ):
            execute(*arguments)
    elif language == "elixir":
        execute("mix", "--version")
        execute(
            "erl",
            "-noshell",
            "-eval",
            'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().',
        )
        execute("expert", "--help")
    elif language == "perl":
        # Its stdio transport exits 1 on EOF without a shutdown request.
        output = run(
            [*command, "sh", "-eu", "-c", "perlnavigator --stdio </dev/null 2>&1"],
            repo,
            expected=1,
            timeout=180,
        )
        assert not output.strip(), output
        print("perl perlnavigator: EOF exit 1 without diagnostics", flush=True)
    elif language == "bun":
        execute("typescript-language-server", "--version")


def verify(language, evidence):
    repo = evidence / language
    repo.mkdir()
    run(["git", "init", "-q"], repo)
    run(["nix", "flake", "init", "-t", f"git+file://{SOURCE}#{language}"], repo)
    run(["git", "add", "flake.nix", ".gitignore", "DEVELOPMENT.md"], repo)
    lock_command = ["nix", "flake", "lock"]
    for input_name, owner in (("nixpkgs", "NixOS"), ("rust-overlay", "oxalica")):
        if input_name == "rust-overlay" and language != "rust":
            continue
        variable = f"TEMPLATE_WITH_ENV_{input_name.upper().replace('-', '_')}_REV"
        revision = os.environ.get(variable)
        if revision:
            assert re.fullmatch(r"[0-9a-f]{40}", revision), variable
            lock_command.extend(
                [
                    "--override-input",
                    input_name,
                    f"github:{owner}/{input_name}/{revision}",
                ]
            )
    run(lock_command, repo)
    run(["git", "add", "flake.lock"], repo)
    lock = (repo / "flake.lock").read_bytes()
    locked = json.loads(lock)
    print(
        f"{language} locked inputs: "
        + json.dumps(
            {
                name: node["locked"]
                for name, node in locked["nodes"].items()
                if "locked" in node
            },
            sort_keys=True,
        ),
        flush=True,
    )
    for system in SYSTEMS:
        app = run(["nix", "eval", "--raw", f".#apps.{system}.with-env.program"], repo)
        assert app.endswith("/bin/with-env"), app
    run(["nix", "flake", "check", "--no-build", "--all-systems"], repo)
    (repo / ".envrc").rename(repo / "envrc-original")
    entry = ["nix", "run", "--no-write-lock-file", ".#with-env", "--"]
    develop = ["nix", "develop", "--no-write-lock-file", ".#default", "-c"]
    for name, command in (("devShell", develop), ("with-env", entry)):
        version = run([*command, *LANGUAGES[language]], repo)
        print(f"{language} {name}: {version.strip()}", flush=True)
        if language == "rust":
            shutil.copyfile(
                SOURCE / "tests/helpers/template-rust-vtable.rs",
                repo / "vtable.rs",
            )
            result = run(
                [
                    *command,
                    "sh",
                    "-eu",
                    "-c",
                    "rustc --edition=2024 vtable.rs -o vtable; ./vtable",
                ],
                repo,
            )
            assert result.strip() == "done", result
        if language == "gleam":
            (repo / "gleam.toml").write_text(
                'name = "template_smoke"\nversion = "1.0.0"\ntarget = "erlang"\n'
            )
            (repo / "src").mkdir(exist_ok=True)
            (repo / "src/template_smoke.gleam").write_text(
                # rand:shuffle/1 is an OTP 29 API, exercised through compiled Gleam.
                '@external(erlang, "rand", "shuffle")\n'
                "fn shuffle(values: List(Int)) -> List(Int)\n\n"
                "pub fn main() {\n"
                "  let assert [42] = shuffle([42])\n"
                '  echo "gleam-erlang-ok"\n'
                "}\n"
            )
            run([*command, "gleam", "run"], repo)
        language_tools(language, command, repo)
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
    evidence = Path(tempfile.mkdtemp(prefix="template-with-env-258-"))
    print(f"Evidence: {evidence}", flush=True)
    for key in list(os.environ):
        if key.startswith(("GIT_", "DEVSHELL_ENV_")):
            os.environ.pop(key)
    for name in ("home", "cache", "config", "data", "state", "runtime"):
        (evidence / name).mkdir(mode=0o700)
    os.environ.update(
        HOME=str(evidence / "home"),
        XDG_CACHE_HOME=str(evidence / "cache"),
        XDG_CONFIG_HOME=str(evidence / "config"),
        XDG_DATA_HOME=str(evidence / "data"),
        XDG_STATE_HOME=str(evidence / "state"),
        XDG_RUNTIME_DIR=str(evidence / "runtime"),
        CARGO_HOME=str(evidence / "home/cargo"),
        CARGO_TARGET_DIR=str(evidence / "cache/cargo-target"),
        RUSTUP_HOME=str(evidence / "home/rustup"),
        GOPATH=str(evidence / "home/go"),
        GOCACHE=str(evidence / "cache/go-build"),
        GOMODCACHE=str(evidence / "cache/go-mod"),
        GOTOOLCHAIN="local",
        GOWORK="off",
        MIX_HOME=str(evidence / "home/mix"),
        HEX_HOME=str(evidence / "home/hex"),
        BUN_INSTALL=str(evidence / "home/bun"),
        BUN_INSTALL_CACHE_DIR=str(evidence / "cache/bun"),
        npm_config_cache=str(evidence / "cache/npm"),
    )
    (evidence / ".env").write_text("DOTENV_258=parent\n")
    for language in arguments.language or LANGUAGES:
        verify(language, evidence)


if __name__ == "__main__":
    main()
