#!/usr/bin/env python3
"""Run the isolated worktree experiment using the shared implementation."""

from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(
        str(
            Path(__file__).resolve().parents[1]
            / "private_dot_local/share/codex-isolation/secret-isolation-worktree.py"
        ),
        run_name="__main__",
    )
