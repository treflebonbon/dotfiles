"""開いた標準入力でシェル起動の入力・job control 待ちを検出する。"""

import os
import pty
import signal
import subprocess
import sys

master, slave = pty.openpty()
try:
    process = subprocess.Popen(
        sys.argv[1:], stdin=slave, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, start_new_session=True,
    )
    os.close(slave)
    slave = None
    try:
        output, _ = process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        # timeout は子を別 process group に置くため、子孫を同じ session 内で終了する。
        rows = subprocess.check_output(["ps", "-eo", "pid=,ppid="], text=True)
        pairs = [tuple(map(int, row.split())) for row in rows.splitlines()]
        descendants = {process.pid}
        while True:
            found = descendants | {pid for pid, parent in pairs if parent in descendants}
            if found == descendants:
                break
            descendants = found
        for pid in descendants:
            try:
                if os.getsid(pid) == process.pid:
                    os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        output, _ = process.communicate()
        print(output, end="")
        sys.exit("シェル起動が入力なしの PTY で5秒以内に完了しない")
    print(output, end="")
    sys.exit(process.returncode)
finally:
    if slave is not None:
        os.close(slave)
    os.close(master)
