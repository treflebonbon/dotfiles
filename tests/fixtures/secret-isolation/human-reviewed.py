"""Fixed, reviewed dummy-only program; never contact a real service."""

import os
from pathlib import Path
import sys

assert os.environ["PUBLIC_VAR"] == "normal"
assert Path("fixture.txt").read_text() == "public fixture\n"
assert not Path("envrc-executed").exists()
if sys.argv[1:] == ["human"]:
    assert os.environ["HUMAN_TOKEN"]
    reviewed_code = Path(__file__).read_bytes()
    print("HUMAN_READY", flush=True)
    assert sys.stdin.readline().strip() == "continue"
    # The controller releases this only after the raw session edits its copy.
    assert Path("fixture.txt").read_text() == "public fixture\n"
    assert Path(__file__).read_bytes() == reviewed_code
    Path("../output/result.txt").write_text(os.environ["HUMAN_TOKEN"])
    print("private diagnostic: " + os.environ["HUMAN_TOKEN"], flush=True)
else:
    assert "HUMAN_TOKEN" not in os.environ
    assert os.environ["TEST_TOKEN"] == "dummy-ai-274"
    print("PUBLIC_TEST_PASSED", flush=True)
