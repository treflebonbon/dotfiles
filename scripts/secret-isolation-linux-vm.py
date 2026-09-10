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
    parser.add_argument(
        "--human-validation",
        action="store_true",
        help="run fixed human code and concurrent raw Codex with dummy values only",
    )
    parser.add_argument(
        "--herdr",
        action="store_true",
        help="run the real Herdr event/terminal integration without external tool logins",
    )
    parser.add_argument(
        "--real-services",
        action="store_true",
        help="run managed MCP and read-only GitHub probes using selected tool login files",
    )
    args = parser.parse_args()
    if sum((args.herdr, args.real_services, args.human_validation)) > 1:
        parser.error(
            "--herdr, --real-services and --human-validation select separate verification runs"
        )
    output = args.output.resolve()
    output.mkdir(mode=0o700)
    root = Path(__file__).resolve().parents[1]
    nixpkgs = subprocess.check_output(
        [
            "nix",
            "eval",
            "--offline",
            "--impure",
            "--raw",
            "--expr",
            f"(builtins.getFlake {json.dumps(str(root))}).inputs.nixpkgs.outPath",
        ],
        text=True,
    ).strip()
    command = [
        "nix",
        "build",
        "--impure",
        "--file",
        str(root / "tests/fixtures/secret-isolation/linux-vm.nix"),
        "driver",
        "--no-link",
        "--print-out-paths",
        "--argstr",
        "repoPath",
        str(root),
        "--argstr",
        "nixpkgsPath",
        nixpkgs,
    ]
    if args.real_services:
        command.extend(["--arg", "realServices", "true"])
    if args.human_validation:
        app = subprocess.check_output(
            ["nix", "build", f"{root}#with-env", "--no-link", "--print-out-paths"],
            text=True,
        ).strip()
        command.extend(["--argstr", "withEnvRoot", app])
    selected_tools = [
        ("nix", "nixRoot"),
        ("bash", "bashRoot"),
        ("cat", "coreutilsRoot"),
        ("python3", "pythonRoot"),
        ("git", "gitRoot"),
        ("codex", "codexRoot"),
        ("gh", "ghRoot"),
        ("bwrap", "bwrapRoot"),
        ("bats", "batsRoot"),
        ("chezmoi", "chezmoiRoot"),
    ]
    if args.herdr:
        selected_tools.append(("herdr", "herdrRoot"))
    for name, argument in selected_tools:
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
    environment = os.environ | {"XDG_RUNTIME_DIR": str(runtime)}
    if args.real_services:
        selected = {
            "CODEX_ISOLATION_VM_CODEX_AUTH": Path(
                os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
            )
            / "auth.json",
            "CODEX_ISOLATION_VM_GH_HOSTS": Path(
                os.environ.get("GH_CONFIG_DIR", str(Path.home() / ".config/gh"))
            )
            / "hosts.yml",
        }
        for name, path in selected.items():
            if not path.is_file():
                raise ValueError(f"the selected tool login file is unavailable: {name}")
            environment[name] = str(path.resolve(strict=True))
    # The regular user owns KVM access and disk-backed VM state; no daemon,
    # group or shared /run/user settings are changed to run this test.
    with (output / "test.log").open("w") as log:
        result = subprocess.run(
            [
                driver + "/bin/nixos-test-driver",
                "--no-interactive",
                "-o",
                str(output / "evidence"),
            ],
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    print(f"Linux VM exit={result.returncode}; evidence: {output}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
