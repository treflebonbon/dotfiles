#!/usr/bin/env python3
"""Reproduce issue #270 with synthetic inputs, never with the caller's repository."""

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import stat
import subprocess
import sys
import threading
import time


SENTINELS = (b"host-fixture-only", b"synthetic-host-only", b"synthetic-parent-only", b"synthetic-provider-only", b"synthetic-late-only", b"synthetic-replacement-only", b"synthetic-tool-auth")


def read_regular_file(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        metadata = os.fstat(source.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise RuntimeError("artifact must be a regular file with one link")
        return source.read()


def audit_artifacts(output):
    paths = [output / name for name in ("store-copy.log", "closure.txt", "runtime.log", "report.json", "launch.json") if (output / name).exists()]
    if (output / "evidence").exists():
        paths.extend((output / "evidence").iterdir())
    leaked = False
    for path in paths:
        data = read_regular_file(path)
        redacted = data
        for sentinel in SENTINELS:
            redacted = redacted.replace(sentinel, b"[redacted synthetic value]")
        if redacted != data:
            leaked = True
            descriptor = os.open(path, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "wb") as destination:
                destination.write(redacted)
    if leaked:
        raise RuntimeError("synthetic secret detected in artifacts; output withheld")


def run(command, *, environment, **kwargs):
    return subprocess.run(command, env=environment, check=True, text=True, **kwargs)


def prepare_input(output, scenario):
    fixture = output / "fixture"
    fixture.mkdir()
    (fixture / ".env").write_text("DUMMY_SECRET=host-fixture-only\n")
    (fixture / "other-secret").write_text("synthetic-host-only\n")
    candidate = fixture / "admitted.txt"
    if scenario == "symlink-input":
        candidate.symlink_to(fixture / ".env")
    elif scenario == "hardlink-input":
        os.link(fixture / ".env", candidate)
    else:
        candidate.write_text("public-fixture-input\n")
    try:
        descriptor = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as source:
            metadata = os.fstat(source.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise OSError("linked or nonregular input")
            with (output / "admitted.txt").open("xb") as destination:
                shutil.copyfileobj(source, destination)
    except OSError as error:
        raise RuntimeError("input must be a regular file with one link") from error
    (fixture / "alias").symlink_to(fixture / ".env")
    os.link(fixture / ".env", fixture / "hardlink")
    return fixture


def run_probe(output, scenario):
    fixture = prepare_input(output, scenario)
    tools = {}
    for name in ("nix", "bash", "coreutils", "python3", "git", "codex", "gh", "bwrap"):
        executable = shutil.which("cat" if name == "coreutils" else name)
        if not executable:
            raise RuntimeError(f"missing required tool: {name}")
        path = Path(executable).resolve(strict=True)
        if path.parts[:3] != ("/", "nix", "store"):
            raise RuntimeError(f"expected a Nix store tool: {name}")
        tools[name] = Path(*path.parts[:4])
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise RuntimeError("bubblewrap is required; no unisolated fallback")
    bootstrap = output / "bootstrap"
    bootstrap.mkdir()
    environment = {
        "HOME": str(bootstrap),
        "PATH": os.pathsep.join(str(path / "bin") for path in tools.values()),
        "NIX_CONF_DIR": str(bootstrap),
        "NIX_CONFIG": "experimental-features = nix-command flakes\n",
    }
    report = {
        "scenario": scenario,
        "fixture_result": "preparing",
        "production_ready": False,
        "platform": "WSL2" if "microsoft" in os.uname().release.lower() else "Linux",
        "kernel": os.uname().release,
        "architecture": os.uname().machine,
        "tools": {k: str(v) for k, v in tools.items()},
        "versions": {},
        "unverified": ["other host platform", "hosted inference and real service authentication", "live Herdr worktree input and result transfer"],
    }
    for name, path in tools.items():
        binary = "cat" if name == "coreutils" else name
        version = run([str(path / "bin" / binary), "--version"], environment=environment, capture_output=True)
        report["versions"][name] = version.stdout.splitlines()[0]
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    store = output / "store"
    with (output / "store-copy.log").open("w") as log:
        run(
            [str(tools["nix"] / "bin/nix"), "copy", "--to", str(store), "--no-check-sigs", *map(str, tools.values())],
            environment=environment,
            stdout=log,
            stderr=log,
            timeout=300,
        )
    closure = run([str(tools["nix"] / "bin/nix"), "path-info", "--store", str(store), "--all"], environment=environment, capture_output=True)
    (output / "closure.txt").write_text(closure.stdout)
    host_unix = socket.socket(socket.AF_UNIX)
    host_unix.bind(str(fixture / "provider.sock"))
    host_unix.listen()

    class SecretProvider(socketserver.BaseRequestHandler):
        calls = 0

        def handle(self):
            type(self).calls += 1
            self.request.sendall(b"synthetic-provider-only")

    host_service = socketserver.ThreadingTCPServer(("127.0.0.1", 0), SecretProvider)
    threading.Thread(target=host_service.serve_forever, daemon=True).start()
    with socket.create_connection(host_service.server_address, timeout=2) as connection:
        assert connection.recv(100) == b"synthetic-provider-only"
    host_namespaces = {name: os.readlink(f"/proc/self/ns/{name}") for name in ("mnt", "pid", "net", "user")}
    workspace = output / "workspace"
    workspace.mkdir()
    evidence = output / "evidence"
    evidence.mkdir()
    flake = '''{
      outputs = { self }:
      assert !(builtins.pathExists @HOST_ENV@);
      assert builtins.getEnv "PROBE_PARENT_SECRET" == "";
      let
        bash = builtins.storePath "@BASH@";
        utils = builtins.storePath "@UTILS@";
      in { devShells.@SYSTEM@.default = builtins.derivation {
        name = "secret-isolation-fixture";
        system = "@SYSTEM@";
        outputs = [ "out" ];
        builder = "${bash}/bin/bash";
        args = [ "-c" "exit 0" ];
        PATH = "${bash}/bin:${utils}/bin";
        shellHook = "@PYTHON@/bin/python3 /fixture/runtime.py assert-boundary; export PROBE_HOOK=ready";
      }; };
    }
    '''
    system = {"x86_64": "x86_64-linux", "aarch64": "aarch64-linux"}[os.uname().machine]
    flake = flake.replace("@BASH@", str(tools["bash"])).replace("@UTILS@", str(tools["coreutils"])).replace("@SYSTEM@", system)
    flake = flake.replace("@HOST_ENV@", json.dumps(str(fixture / ".env"))).replace("@PYTHON@", str(tools["python3"]))
    if scenario == "nix-failure":
        flake = '{ outputs = { self }: throw "synthetic Nix evaluation failure"; }'
    elif scenario == "hook-failure":
        flake = flake.replace("export PROBE_HOOK=ready", "exit 37")
    elif scenario in ("log-leak", "log-leak-success"):
        continuation = "exit 37" if scenario == "log-leak" else "export PROBE_HOOK=ready"
        flake = flake.replace("export PROBE_HOOK=ready", "echo synthetic-tool-auth >&2; " + continuation)
    (output / "flake.nix").write_text(flake)
    script = output / "inside.sh"
    script.write_text('''set -euo pipefail
test ! -e "$HOST_FIXTURE/.env"
test ! -e "$HOST_FIXTURE/other-secret"
test -z "${PROBE_PARENT_SECRET+x}"
test ! -e /nix/var/nix/daemon-socket/socket
printf 'PASS host-secrets-unavailable\\n'
git init -q -b main /repo
git -C /repo add flake.nix admitted.txt
git -C /repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'test: fixture base'
git -C /repo worktree add -b task /work
set +e
nix print-dev-env --impure /work --no-write-lock-file > /tmp/development.bash
result=$?
if [ "$result" -eq 0 ]; then
  bash -e /activate.sh
  result=$?
fi
if [ "$result" -ne 0 ] && [ ! -e /evidence/codex-started ]; then
  python3 /fixture/runtime.py assert-boundary || exit 1
  printf 'PASS isolated-diagnostics\\n'
fi
exit "$result"
''')
    activate = output / "activate.sh"
    activate.write_text('''source /tmp/development.bash
test "$PROBE_HOOK" = ready
printf 'PASS nix-environment\\n'
exec python3 /fixture/runtime.py run
''')
    command = [
        bwrap, "--unshare-all", "--die-with-parent", "--new-session", "--cap-drop", "ALL", "--clearenv",
        "--tmpfs", "/", "--dev", "/dev", "--proc", "/proc", "--dir", "/tmp", "--dir", "/home/agent",
        "--bind", str(store / "nix"), "/nix", "--bind", str(workspace), "/work",
        "--dir", "/repo", "--bind", str(evidence), "/evidence",
        "--ro-bind", str(output / "flake.nix"), "/repo/flake.nix",
        "--ro-bind", str(output / "admitted.txt"), "/repo/admitted.txt",
        "--ro-bind", str(Path(__file__).resolve().parents[1] / "tests/fixtures/secret-isolation"), "/fixture",
        "--ro-bind", str(script), "/inside.sh", "--dir", "/bin",
        "--ro-bind", str(activate), "/activate.sh",
        "--symlink", str(tools["bash"] / "bin/bash"), "/bin/sh",
        "--setenv", "HOME", "/home/agent", "--setenv", "PATH", environment["PATH"],
        "--setenv", "SHELL", str(tools["bash"] / "bin/bash"),
        "--setenv", "CODEX_HOME", "/home/agent/.codex",
        "--setenv", "HOST_FIXTURE", str(fixture), "--setenv", "NIX_REMOTE", "local",
        "--setenv", "HOST_TCP_PORT", str(host_service.server_address[1]),
        "--setenv", "HOST_NAMESPACES", json.dumps(host_namespaces),
        "--setenv", "NIX_CONFIG", "experimental-features = nix-command flakes\nbuild-users-group =\nsandbox = false\nsubstituters =\n",
        "--chdir", "/work", str(tools["bash"] / "bin/bash"), "/inside.sh",
    ]
    if scenario == "isolation-failure":
        command[1:1] = ["--ro-bind", str(output / "missing-mount-input"), "/unavailable"]
    (output / "launch.json").write_text(json.dumps(command, indent=2) + "\n")
    stop = threading.Event()

    def mutate_host():
        while not stop.wait(0.01):
            if (evidence / "mutate.ready").exists():
                (fixture / "late-secret").write_text("synthetic-late-only\n")
                (fixture / "replacement").write_text("synthetic-replacement-only\n")
                os.replace(fixture / "replacement", fixture / ".env")
                (fixture / "admitted.txt").write_text("synthetic-late-only\n")
                with (evidence / "mutate.done").open("x"):
                    pass
                return

    mutator = threading.Thread(target=mutate_host, daemon=True)
    mutator.start()
    try:
        result = subprocess.run(command, env={**environment, "PROBE_PARENT_SECRET": "synthetic-parent-only"}, capture_output=True, text=True, timeout=180)
    finally:
        stop.set()
        mutator.join(timeout=2)
        host_service.shutdown()
        host_service.server_close()
        host_unix.close()
    (output / "runtime.log").write_text(result.stdout + result.stderr)
    report.update(fixture_result="validating" if result.returncode == 0 else "failed", exit_code=result.returncode)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    result.check_returncode()
    assert SecretProvider.calls == 1, "isolated process contacted host secret service"
    assert (evidence / "mutate.done").exists()
    assert (workspace / "admitted.txt").stat().st_ino != (fixture / "admitted.txt").stat().st_ino
    assert read_regular_file(workspace / "admitted.txt") == b"public-fixture-input\n"
    report.update(fixture_result="passed", checks=["nix-evaluation", "shellHook", "codex-process", "shell-and-child", "git-edit-build-test-commit", "github-fixture", "stdio-mcp", "host-files-and-variables", "host-services", "late-replacement", "separate-input-inode", "no-secret-in-provider-or-tool-logs"])
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return result.stdout + "PASS dynamic-host-boundary\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scenario", choices=("success", "symlink-input", "hardlink-input", "isolation-failure", "nix-failure", "hook-failure", "log-leak", "log-leak-success"), default="success", help="Synthetic failure injection; never accepts a real project path")
    args = parser.parse_args()
    output = args.output.absolute()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    try:
        try:
            summary = run_probe(output, args.scenario)
        finally:
            audit_artifacts(output)
    except Exception:
        report_path = output / "report.json"
        if report_path.exists():
            report = json.loads(read_regular_file(report_path))
            report["fixture_result"] = "failed"
            report_path.write_text(json.dumps(report, indent=2) + "\n")
        raise
    print(summary, end="")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, end="")
        print(error.stderr or str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, RuntimeError) as error:
        print(f"secret-isolation-probe: {error}", file=sys.stderr)
        sys.exit(1)
