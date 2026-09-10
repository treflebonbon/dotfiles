"""Coordinate dummy-only human/raw processes through their public CLI entries."""

import os
from pathlib import Path
import select
import subprocess
import sys
import time
import uuid


def wait_line(process, marker, captured):
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        if not select.select([process.stdout], [], [], 1)[0]:
            continue
        line = process.stdout.readline().decode()
        assert line, f"process exited before {marker}: {captured!r}"
        captured.append(line)
        if line.strip() == marker:
            return
    raise AssertionError(f"timeout waiting for {marker}: {captured!r}")


def main():
    base, source = map(Path, sys.argv[1:])
    human = base / "human"
    human.mkdir(mode=0o700)
    (human / "home").mkdir()
    (human / "output").mkdir()
    work = base / "work"
    revision = subprocess.check_output(
        ["git", "-C", str(work), "rev-parse", "HEAD"], text=True
    ).strip()
    # No shared Git objects, moving branch, untracked files or live worktree mount.
    bundle = human / "reviewed.bundle"
    subprocess.run(
        ["git", "-C", str(work), "bundle", "create", str(bundle), "HEAD"], check=True
    )
    checkout = human / "code"
    subprocess.run(["git", "clone", "-q", str(bundle), str(checkout)], check=True)
    subprocess.run(
        ["git", "-C", str(checkout), "checkout", "-q", "--detach", revision], check=True
    )
    fixed = {
        name: (checkout / name).read_bytes()
        for name in ("reviewed.py", "fixture.txt", "flake.nix")
    }
    token = "dummy-human-only-274-" + str(uuid.uuid4())
    (checkout / ".env").write_text(f"HUMAN_TOKEN={token}\n")
    (human / "output/result.txt").write_text("pending")
    private_log = human / "output/private.log"
    private_log.touch()
    control = subprocess.run(
        [sys.executable, str(work / "task.py"), "probe", str(checkout / ".env")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert control.returncode != 0 and "human path was accessible" in control.stderr
    environment = os.environ | {
        "HOME": str(human / "home"),
        "XDG_CACHE_HOME": str(human / "cache"),
    }
    # Public with-env, real Nix and shellHook, no model or service credentials.
    human_process = subprocess.Popen(
        [
            str(source / "private_dot_local/bin/executable_devshell-env"),
            "with-env",
            "--",
            "python3",
            "reviewed.py",
            "human",
        ],
        cwd=checkout,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    raw_process = None
    human_lines, raw_lines = [], []
    try:
        wait_line(human_process, "HUMAN_READY", human_lines)
        paths = [str(checkout / name) for name in (*fixed, ".env")]
        paths += [
            str(private_log),
            str(human / "output/result.txt"),
            f"/proc/{human_process.pid}/environ",
        ]
        paths += [f"/proc/{human_process.pid}/root{checkout}/.env"]
        environment = os.environ | {
            "HOME": str(base / "home"),
            "CODEX_HOME": str(base / "home/.codex"),
            "XDG_STATE_HOME": str(base / "state"),
            "HUMAN_TOKEN": token,
        }
        raw_process = subprocess.Popen(
            [
                str(base / "bin/codex-worktree"),
                "sandbox",
                "--",
                "python3",
                "task.py",
                *paths,
            ],
            cwd=work,
            env=environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
        wait_line(raw_process, "AI_EDITED", raw_lines)
        human_tail, _ = human_process.communicate(b"continue\n", timeout=30)
        human_lines.append(human_tail.decode())
        assert human_process.returncode == 0, human_lines
        private_log.write_text("".join(human_lines))
        assert (human / "output/result.txt").read_text() == token
        raw_tail, _ = raw_process.communicate(b"continue\n", timeout=60)
        raw_lines.append(raw_tail.decode())
        assert raw_process.returncode == 0, raw_lines
        assert b"AI_FINISHED" in raw_tail
        assert "PUBLIC_TEST_PASSED" in "".join(raw_lines)
        assert token not in "".join(raw_lines)
        for name, original in fixed.items():
            assert (checkout / name).read_bytes() == original
        assert (checkout / ".env").read_text() == f"HUMAN_TOKEN={token}\n"
        assert (human / "output/result.txt").read_text() == token
        assert private_log.read_text() == "".join(human_lines)
        assert (
            work / "reviewed.py"
        ).read_text() == "raise RuntimeError('continued AI edit')\n"
        assert (
            subprocess.check_output(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
            ).strip()
            == revision
        )
        assert (
            subprocess.check_output(
                ["git", "-C", str(work), "rev-parse", "HEAD"], text=True
            ).strip()
            != revision
        )
        # Explicitly selected public summary; private stdout/artifacts stay human-side.
        print(
            f"HUMAN_VALIDATION_SEPARATED reviewed={revision}; public test passed; human dummy check passed"
        )
    finally:
        for process in (raw_process, human_process):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=30)


if __name__ == "__main__":
    main()
