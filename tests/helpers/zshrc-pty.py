"""開いた標準入力で zsh 初期化の入力待ちを検出する。"""

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
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        print(output, end="")
        sys.exit("zsh 初期化が入力なしの PTY で5秒以内に完了しない")
    print(output, end="")
    sys.exit(process.returncode)
finally:
    if slave is not None:
        os.close(slave)
    os.close(master)
