#!/usr/bin/env python3
"""Run the isolation fixture on a real Linux kernel, using the NixOS VM driver."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(mode=0o700)
    root = Path(__file__).resolve().parents[1]
    nixpkgs = subprocess.check_output(
        ["nix", "eval", "--offline", "--impure", "--raw", "--expr", f"(builtins.getFlake {json.dumps(str(root))}).inputs.nixpkgs.outPath"], text=True,
    ).strip()
    command = ["nix", "build", "--impure", "--file", str(root / "tests/fixtures/secret-isolation/linux-vm.nix"), "driver", "--no-link", "--print-out-paths", "--argstr", "repoPath", str(root), "--argstr", "nixpkgsPath", nixpkgs]
    for name, argument in (("nix", "nixRoot"), ("bash", "bashRoot"), ("cat", "coreutilsRoot"), ("python3", "pythonRoot"), ("git", "gitRoot"), ("codex", "codexRoot"), ("gh", "ghRoot"), ("bwrap", "bwrapRoot"), ("bats", "batsRoot")):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f"missing required tool: {name}")
        path = Path(executable).resolve(strict=True)
        if path.parts[:3] != ("/", "nix", "store"):
            raise ValueError(f"a Nix store tool is required: {name}")
        command.extend(["--argstr", argument, str(Path(*path.parts[:4]))])
    with (output / "build.log").open("w") as log:
        driver = subprocess.check_output(command, stderr=log, text=True).strip()
    runtime = output / "runtime"
    runtime.mkdir(mode=0o700)
    (output / "evidence").mkdir()
    # The regular user owns KVM access and disk-backed VM state; no daemon,
    # group or shared /run/user settings are changed to run this test.
    with (output / "test.log").open("w") as log:
        result = subprocess.run(
            [driver + "/bin/nixos-test-driver", "--no-interactive", "-o", str(output / "evidence")],
            env=os.environ | {"XDG_RUNTIME_DIR": str(runtime)}, stdout=log, stderr=subprocess.STDOUT,
        )
    print(f"Linux VM exit={result.returncode}; evidence: {output}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
