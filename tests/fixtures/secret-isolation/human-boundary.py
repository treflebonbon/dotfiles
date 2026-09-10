"""Attempt access only to the dummy paths explicitly supplied by the test."""

import errno
import os
from pathlib import Path
import subprocess
import sys


def probe(paths):
    for name in paths:
        for flags in (os.O_RDONLY, os.O_WRONLY):
            try:
                descriptor = os.open(name, flags)
            except OSError as error:
                assert error.errno in (errno.ENOENT, errno.EACCES, errno.EPERM), error
            else:
                os.close(descriptor)
                raise AssertionError(f"human path was accessible: {name}")
    assert "HUMAN_TOKEN" not in os.environ
    print("HUMAN_PATHS_DENIED", flush=True)


if sys.argv[1] == "probe":
    probe(sys.argv[2:])
else:
    paths = sys.argv[1:]
    probe(paths)
    subprocess.run(
        ["with-env", "--prepared", "--", "python3", __file__, "probe", *paths],
        check=True,
    )
    subprocess.run(
        [
            "with-env",
            "--prepared",
            "--",
            "env",
            "TEST_TOKEN=dummy-ai-274",
            "python3",
            "reviewed.py",
        ],
        check=True,
    )
    Path("reviewed.py").write_text("raise RuntimeError('continued AI edit')\n")
    Path("fixture.txt").write_text("continued AI edit\n")
    subprocess.run(["git", "add", "reviewed.py", "fixture.txt"], check=True)
    subprocess.run(
        ["git", "commit", "-qm", "test: continue AI work during human validation"],
        check=True,
    )
    print("AI_EDITED", flush=True)
    assert sys.stdin.readline().strip() == "continue"
    # Retry after the human has produced its private output and log.
    probe(paths)
    print("AI_FINISHED", flush=True)
