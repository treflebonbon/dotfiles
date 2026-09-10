"""Dummy-only regression through the public with-env and codex-worktree CLIs."""

import io
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tarfile
import time


base = Path(sys.argv[1]).resolve()
work = base / "work"
reviewed = base / "human-reviewed"
reviewed.mkdir()
environment = {
    "HOME": str(base / "home"),
    "CODEX_HOME": str(base / "home/.codex"),
    "XDG_STATE_HOME": str(base / "state"),
    "PATH": os.environ["PATH"],
}
for name in ("CODEX_ISOLATION_CA_BUNDLE", "NIX_SSL_CERT_FILE", "SSL_CERT_FILE"):
    if name in os.environ:
        environment[name] = os.environ[name]


def run(arguments, cwd=work):
    return subprocess.check_output(arguments, cwd=cwd, env=environment, text=True)


def ready(process, marker):
    # Bounded rendezvous, without granting the isolated child a host control file.
    deadline = time.monotonic() + 180
    received = b""
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while marker.encode() not in received.split(b"\n")[:-1]:
            assert selector.select(timeout=max(0, deadline - time.monotonic())), (
                f"timeout waiting for {marker}"
            )
            chunk = os.read(process.stdout.fileno(), 4096)
            assert chunk, f"process exited before {marker}; see {base}/*-stderr.log"
            received += chunk
    assert b"dummy-human-only" not in received


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


bash_root, coreutils_root, python_root = (
    Path(shutil.which(name)).resolve().parents[1] for name in ("bash", "cat", "python3")
)
system = {"x86_64": "x86_64-linux", "aarch64": "aarch64-linux"}[os.uname().machine]
(work / "flake.nix").write_text(
    """{ outputs = { self }: let
tool = path: builtins.appendContext path { ${path}.path = true; };
in { devShells.%s.default = builtins.derivation {
name = "human-validation"; system = "%s"; builder = "${tool "%s"}/bin/bash";
args = [ "-c" "exit 0" ]; outputs = [ "out" ];
PATH = "${tool "%s"}/bin:${tool "%s"}/bin:${tool "%s"}/bin"; PUBLIC_MODE = "fixture";
shellHook = "test -z \\"$HUMAN_TOKEN$RAW_DUMMY_SECRET\\" || return 71";
}; }; }"""
    % (system, system, bash_root, bash_root, coreutils_root, python_root)
)
(work / "calculator.py").write_text("def add(a, b): return a + b\n")
(work / "fixture.json").write_text('{"expected": 5}\n')
(work / "validate.py").write_text("""import json, os, sys
from pathlib import Path
from calculator import add
assert os.environ["PUBLIC_MODE"] == "fixture"
assert add(2, 3) == json.loads(Path("fixture.json").read_text())["expected"]
if sys.argv[1] == "human":
    assert os.environ["HUMAN_TOKEN"].startswith("dummy-")
    print("HUMAN_READY", flush=True)
    assert input() == "continue"
    assert Path("calculator.py").read_text() == "def add(a, b): return a + b\\n"
    Path("result.txt").write_text(os.environ["HUMAN_TOKEN"])
else:
    assert "HUMAN_TOKEN" not in os.environ and "RAW_DUMMY_SECRET" not in os.environ
    assert os.environ["LOCAL_DUMMY"] == "harmless"
""")
(work / ".gitignore").write_text(".env\n__pycache__/\n")
(work / ".envrc").write_text("touch envrc-executed\nexit 89\n")
names = [
    "flake.nix",
    "calculator.py",
    "fixture.json",
    "validate.py",
    ".gitignore",
    ".envrc",
]
run(["git", "add", "--", *names])
run(["git", "commit", "-qm", "test: reviewed public code"])
reviewed_sha = run(["git", "rev-parse", "HEAD"]).strip()
# Export a fixed revision, never a live mount or a shared Git object directory.
archive = subprocess.check_output(["git", "archive", reviewed_sha], cwd=work)
with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
    stream.extractall(reviewed, filter="data")
run(["git", "init", "-q"], reviewed)
run(["git", "add", "--", *names], reviewed)
fixed = {name: (reviewed / name).read_bytes() for name in names}
(reviewed / ".env").write_text("HUMAN_TOKEN=dummy-human-only\n")
(reviewed / "result.txt").write_text("pending\n")
# with-env here is the repository's exported Nix package, supplied by devShell.
with_env = shutil.which("with-env")
assert with_env and Path(with_env).resolve().is_relative_to("/nix/store")
with (base / "human-stderr.log").open("w") as human_errors:
    human = subprocess.Popen(
        [with_env, "--", "python3", "-u", "validate.py", "human"],
        cwd=reviewed,
        env=environment,
        text=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=human_errors,
    )
    try:
        ready(human, "HUMAN_READY")
        paths = [str(reviewed / name) for name in (*names, ".env", "result.txt")]
        paths += [
            f"/proc/{human.pid}/environ",
            f"/proc/{human.pid}/root{reviewed}/.env",
        ]
        (work / "boundary.json").write_text(json.dumps(paths))
        (work / "boundary.py").write_text("""import errno, json, os
from pathlib import Path
for name in json.loads(Path("boundary.json").read_text()):
    for flags in (os.O_RDONLY, os.O_WRONLY | os.O_TRUNC):
        try:
            fd = os.open(name, flags)
        except OSError as error:
            assert error.errno in (errno.ENOENT, errno.EACCES, errno.EPERM, errno.EROFS), (name, error.errno)
        else:
            os.close(fd)
            raise AssertionError("human file became accessible: " + name)
""")
        (work / "task.sh").write_text("""set -eu
with-env --prepared -- env LOCAL_DUMMY=harmless python3 validate.py ai
python3 boundary.py
printf 'def add(a, b): return sum((a, b))\\n' > calculator.py
python3 -m py_compile calculator.py
with-env --prepared -- env LOCAL_DUMMY=harmless python3 validate.py ai
printf 'AI_READY\\n'
read -r reply
test "$reply" = continue
with-env --prepared -- python3 boundary.py
git add calculator.py
git commit -qm 'test: continue editing after human revision was fixed'
""")
        names += ["boundary.json", "boundary.py", "task.sh"]
        run(["git", "add", "--", *names])
        run(["git", "commit", "-qm", "test: public boundary checks"])
        cli = str(base / "bin/devshell-env")
        run([cli, "trust"])
        run(
            [
                cli,
                "admit",
                "--git-head",
                run(["git", "rev-parse", "HEAD"]).strip(),
                "--",
                *names,
            ]
        )
        with (base / "codex-stderr.log").open("w") as errors:
            codex = subprocess.Popen(
                [str(base / "bin/codex-worktree"), "sandbox", "--", "bash", "task.sh"],
                cwd=work,
                env=environment | {"RAW_DUMMY_SECRET": "dummy-inherited"},
                text=True,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=errors,
            )
            try:
                ready(codex, "AI_READY")
                human_output, _ = human.communicate("continue\n", timeout=30)
                assert human.returncode == 0, (base / "human-stderr.log").read_text()
                assert not human_output, repr(human_output)
                assert (reviewed / "result.txt").read_text() == "dummy-human-only"
                raw_output, _ = codex.communicate("continue\n", timeout=60)
                assert codex.returncode == 0, (base / "codex-stderr.log").read_text()
                assert "dummy-human-only" not in raw_output
            finally:
                stop(codex)
    finally:
        stop(human)
for name, content in fixed.items():
    assert (reviewed / name).read_bytes() == content
assert (reviewed / ".env").read_text() == "HUMAN_TOKEN=dummy-human-only\n"
assert (reviewed / "result.txt").read_text() == "dummy-human-only"
assert (work / "calculator.py").read_text() == "def add(a, b): return sum((a, b))\n"
assert run(["git", "show", "HEAD:calculator.py"]) == "def add(a, b): return sum((a, b))\n"
run(["git", "diff", "--exit-code", "HEAD", "--", "calculator.py"])
assert (
    not (work / "envrc-executed").exists()
    and not (reviewed / "envrc-executed").exists()
)
assert not (work / "result.txt").exists()
print("HUMAN_VALIDATION_SEPARATED_OK")
