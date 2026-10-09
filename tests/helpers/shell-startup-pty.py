"""stdin に PTY を接続し、完了しないシェル起動を検出する。"""

import os
import pty
import signal
import subprocess
import sys

STARTUP_TIMEOUT = 30
DRAIN_TIMEOUT = 2


def kill_session(session_id):
    rows = subprocess.check_output(["ps", "-eo", "pid="], text=True)
    for value in rows.split():
        pid = int(value)
        try:
            if os.getsid(pid) == session_id:
                os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


master, slave = pty.openpty()
try:
    process = subprocess.Popen(
        sys.argv[1:], stdin=slave, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, start_new_session=True,
    )
    output_encoding = process.stdout.encoding
    os.close(slave)
    slave = None
    try:
        output, _ = process.communicate(timeout=STARTUP_TIMEOUT)
    except subprocess.TimeoutExpired:
        # The root shell may have exited and reparented a pipe-holding child.
        kill_session(process.pid)
        try:
            output, _ = process.communicate(timeout=DRAIN_TIMEOUT)
        except subprocess.TimeoutExpired as drain_timeout:
            output = drain_timeout.output or ""
            if process.stdout is not None:
                process.stdout.close()
            if process.poll() is None:
                try:
                    if os.getsid(process.pid) == process.pid:
                        os.kill(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=DRAIN_TIMEOUT)
                except subprocess.TimeoutExpired:
                    pass
        if isinstance(output, bytes):
            output = output.decode(output_encoding, errors="replace")
        print(output, end="")
        sys.exit(f"シェル起動が入力なしの PTY で{STARTUP_TIMEOUT}秒以内に完了しない")
    print(output, end="")
    sys.exit(process.returncode)
finally:
    if slave is not None:
        os.close(slave)
    os.close(master)
