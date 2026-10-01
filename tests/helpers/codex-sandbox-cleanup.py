"""Exercise real sandbox teardown without touching the user's HOME or dotenv."""

import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
case = sys.argv[2]
home = root / "home"
workspace = root / "workspace"
(home / ".codex").mkdir(parents=True)
workspace.mkdir()
(home / ".codex/config.toml").write_text(
    '[permissions.test]\nextends = ":workspace"\n'
    '[permissions.test.filesystem.":workspace_roots"]\n".env" = "deny"\n'
)
env = dict(os.environ, HOME=str(home), CODEX_HOME=str(home / ".codex"), TMPDIR="/tmp")
command = ["codex", "sandbox", "-P", "test", "-C", str(workspace), "--"]
dotenv = workspace / ".env"
processes = []


def wait_until(predicate):
    deadline = time.monotonic() + 5
    while not predicate():
        assert time.monotonic() < deadline, "sandbox startup or cleanup timed out"
        time.sleep(0.01)


def start(marker):
    process = subprocess.Popen(
        [*command, "sh", "-c",
         'if data=$(cat .env 2>/dev/null); then '
         'test "$2" != existing && test -z "$data" || exit 1; fi; '
         'if (printf changed >.env) 2>/dev/null; then exit 2; fi; '
         'test "$2" != ignored || trap "" TERM; '
         'printf ready >"$1"; while [ ! -e finish ]; do sleep 0.01; done', "_", marker, case],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    processes.append(process)
    wait_until(lambda: (workspace / marker).exists() or process.poll() is not None)
    assert process.poll() is None, process.communicate()[1].decode()
    assert dotenv.is_file()
    return process


def stop(process, sig):
    os.killpg(process.pid, sig)
    process.communicate(timeout=5)


try:
    if case in ("tty", "tty-denied"):
        pid, master = pty.fork()
        if pid == 0:
            profile = "test" if case == "tty-denied" else ":read-only"
            os.execvpe("codex", ["codex", "sandbox", "-P", profile, "-C", str(workspace),
                               "--", "sh", "-c", 'read data; test "$data" = fixture && printf tty-ok'], env)
        status = None
        output = b""
        try:
            if case == "tty-denied":
                wait_until(dotenv.is_file)
            os.write(master, b"fixture\n")
            deadline = time.monotonic() + 5
            while status is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.05)[0]:
                    try:
                        output += os.read(master, 4096)
                    except OSError:
                        pass
                waited, value = os.waitpid(pid, os.WNOHANG)
                if waited:
                    status = value
            assert status is not None, "sandbox could not read its terminal"
            while select.select([master], [], [], 0)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
            assert os.waitstatus_to_exitcode(status) == 0, output.decode(errors="replace")
            assert b"tty-ok" in output
            assert not dotenv.exists()
        finally:
            if status is None:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)
    elif case == "exit-status":
        result = subprocess.run(
            [*command, "sh", "-c", 'printf out; printf err >&2; exit 37'],
            env=env, capture_output=True, timeout=5,
        )
        assert result.returncode == 37
        assert result.stdout == b"out"
        assert result.stderr.endswith(b"err")
        assert not dotenv.exists()
    elif case == "existing":
        for contents in (b"", b"fixture\n"):
            dotenv.write_bytes(contents)
            dotenv.chmod(0o600)
            before = dotenv.stat()
            process = start(f"ready-{len(contents)}")
            stop(process, signal.SIGKILL)
            # A following successful command also verifies the teardown has completed.
            subprocess.run([*command, "true"], env=env, capture_output=True, check=True)
            after = dotenv.stat()
            assert dotenv.read_bytes() == contents
            assert (after.st_ino, after.st_mode) == (before.st_ino, before.st_mode)
    else:
        process = start("ready-first")
        if case == "overlap":
            other = start("ready-second")
            stop(process, signal.SIGKILL)
            stop(other, signal.SIGTERM)
        elif case == "normal":
            (workspace / "finish").touch()
            process.communicate(timeout=5)
            assert process.returncode == 0
        else:
            stop(process, signal.SIGKILL)
        wait_until(lambda: not dotenv.exists())
        subprocess.run([*command, "true"], env=env, capture_output=True, check=True)
        assert not dotenv.exists(), "sandbox left a dotenv that did not exist before execution"
finally:
    (workspace / "finish").touch()
    for process in processes:
        if process.poll() is None:
            stop(process, signal.SIGKILL)
