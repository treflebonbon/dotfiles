"""Nix 配布物の Playwright owner/runtime を隔離 fixture で検証する。"""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def checked_run(command, environment, *, cwd, expected=0):
    result = subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"command exited {result.returncode}, expected {expected}: {command}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result


def environment_for(root, owner, runtime, powershell):
    return {
        **os.environ,
        "BROWSER_OWNERSHIP_DIR": str(root / "ownership"),
        "PWCLI_RUNTIME_DIR": str(root / "runtime"),
        "PWCLI_WINDOWS_SCRIPT": r"C:\mock.ps1",
        "PWCLI_POWERSHELL": str(powershell),
        "MANAGED_CHROME_OWNER": str(owner),
        "PWCLI_RUNTIME_COMMAND": str(runtime),
    }


def create_probe(powershell):
    powershell.parent.mkdir(parents=True, exist_ok=True)
    powershell.write_text("#!/usr/bin/env bash\nprintf 'absent\\n'\n", encoding="utf-8")
    powershell.chmod(0o755)


def identity_for(workspace):
    return "playwright-" + hashlib.sha256(str(workspace).encode()).hexdigest()


def locate(owner, workspace, environment):
    checked_run(
        [owner, "locate", "--role", "playwright", "--workspace", workspace],
        environment,
        cwd=workspace,
    )


def assert_dashboard_hold(owner, runtime, workspace, root, environment, identity):
    allocation_file = root / "ownership/allocations.json"
    original_allocations = allocation_file.read_bytes()
    runtime_dir = root / "runtime/playwright-cli" / identity
    runtime_dir.mkdir(parents=True, exist_ok=True)
    dashboard_pid = runtime_dir / "dashboard.pid"
    dashboard_pid.write_text("fixture dashboard\n", encoding="utf-8")

    result = checked_run(
        [owner, "--identity", identity, "relocate", "--role", "playwright", "--workspace", workspace],
        environment,
        cwd=workspace,
        expected=1,
    )
    assert "Close the worktree Dashboard" in result.stderr
    assert allocation_file.read_bytes() == original_allocations
    assert dashboard_pid.read_text(encoding="utf-8") == "fixture dashboard\n"

    dashboard_pid.unlink()
    checked_run(
        [owner, "--identity", identity, "relocate", "--role", "playwright", "--workspace", workspace],
        environment,
        cwd=workspace,
    )
    assert allocation_file.read_bytes() != original_allocations
    layout = checked_run([runtime, identity], environment, cwd=workspace)
    fields = layout.stdout.rstrip("\n").split("\t")
    assert len(fields) == 10
    assert Path(fields[0]) == runtime_dir


def assert_wrapper_rechecks_allocation(package, workspace, root, powershell, flock):
    owner = package / "bin/managed-chrome-owner"
    runtime = package / "libexec/playwright-runtime"
    environment = environment_for(root, owner, runtime, powershell)
    identity = identity_for(workspace)
    fake_bin = root / "bin"
    fake_bin.mkdir(parents=True, exist_ok=True)
    wslinfo = fake_bin / "wslinfo"
    wslinfo.write_text("#!/usr/bin/env bash\nprintf 'mirrored\\n'\n", encoding="utf-8")
    wslinfo.chmod(0o755)
    upstream_log = root / "upstream.log"
    upstream = fake_bin / "playwright-cli-upstream"
    upstream.write_text(
        "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$PWCLI_UPSTREAM_LOG\"\n",
        encoding="utf-8",
    )
    upstream.chmod(0o755)
    race_flock = fake_bin / "flock-before-lock"
    race_flock.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "\"$MANAGED_CHROME_OWNER\" --identity \"$RACE_IDENTITY\" relocate --role playwright --workspace \"$PWCLI_WORKSPACE\" >/dev/null\n"
        "exec \"$REAL_FLOCK\" \"$@\"\n",
        encoding="utf-8",
    )
    race_flock.chmod(0o755)
    environment.update(
        {
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "PWCLI_TEST_WSL": "1",
            "PWCLI_WORKSPACE": str(workspace),
            "PWCLI_UPSTREAM": str(upstream),
            "PWCLI_UPSTREAM_LOG": str(upstream_log),
            "PWCLI_WSLINFO": str(wslinfo),
            "PWCLI_FLOCK": str(race_flock),
            "REAL_FLOCK": str(flock),
            "RACE_IDENTITY": identity,
        }
    )
    result = checked_run(
        [package / "bin/playwright-cli", "open"],
        environment,
        cwd=workspace,
        expected=1,
    )
    assert "Browser allocation changed while waiting for the runtime lock" in result.stderr
    assert not upstream_log.exists()


def assert_owner_holds_both_locks(package, skills_root, workspace, root, powershell, flock):
    owner = package / "bin/managed-chrome-owner"
    runtime = package / "libexec/playwright-runtime"
    environment = environment_for(root, owner, runtime, powershell)
    locate(owner, workspace, environment)
    identity = identity_for(workspace)
    layout = checked_run([runtime, identity], environment, cwd=workspace)
    fields = layout.stdout.rstrip("\n").split("\t")
    owner_lock = root / "ownership/ownership.lock"
    runtime_lock = Path(fields[1])
    barrier = root / "rename"
    log = root / "relocate.log"
    hook = skills_root / "packages/wsl2-browser/tests/fixtures/playwright-relocation-hooks.mjs"
    assert hook.is_file()
    environment.update(
        {
            "NODE_OPTIONS": f"--import={hook}",
            "TEST_OWNER_LOCK": str(owner_lock),
            "TEST_RUNTIME_LOCK": str(runtime_lock),
            "TEST_RELOCATION_BARRIER": str(barrier),
        }
    )
    process = subprocess.Popen(
        [
            str(owner),
            "--identity",
            identity,
            "relocate",
            "--role",
            "playwright",
            "--workspace",
            str(workspace),
        ],
        cwd=workspace,
        env=environment,
        stdout=log.open("w"),
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        deadline = time.monotonic() + 20
        while not Path(f"{barrier}.ready").is_file():
            if process.poll() is not None:
                raise AssertionError(f"relocate exited before barrier: {log.read_text(encoding='utf-8')}")
            if time.monotonic() >= deadline:
                raise AssertionError(f"relocate did not reach rename barrier: {log.read_text(encoding='utf-8')}")
            time.sleep(0.01)
        for lock in (owner_lock, runtime_lock):
            result = subprocess.run([flock, "--nonblock", lock, "true"], check=False)
            assert result.returncode == 1, f"expected lock to remain held: {lock}"
        Path(f"{barrier}.continue").touch()
        assert process.wait(timeout=20) == 0, log.read_text(encoding="utf-8")
    finally:
        Path(f"{barrier}.continue").touch()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main():
    package = Path(sys.argv[1]).resolve(strict=True)
    skills_root = Path(sys.argv[2]).resolve(strict=True)
    temporary = Path(sys.argv[3]).resolve(strict=True)
    workspace = Path(sys.argv[4]).resolve(strict=True)
    if not str(package).startswith("/nix/store/"):
        raise AssertionError(f"expected a built Nix package, got {package}")
    for relative in (
        "bin/managed-chrome-owner",
        "bin/playwright-cli",
        "libexec/playwright-runtime",
        "libexec/managed-chrome-owner.mjs",
        "libexec/playwright-runtime.mjs",
        "libexec/browser-lock.mjs",
        "share/playwright-cli/playwright-runtime.mjs",
        "share/playwright-cli/browser-lock.mjs",
    ):
        path = package / relative
        assert path.exists(), f"missing distributed Playwright file: {path}"
    owner = package / "bin/managed-chrome-owner"
    runtime = package / "libexec/playwright-runtime"
    powershell = temporary / "probe-powershell"
    create_probe(powershell)
    flock = shutil.which("flock")
    if not flock:
        raise AssertionError("flock is required for the packaged browser-lock fixture")
    identity = identity_for(workspace)

    dashboard_root = temporary / "distribution-dashboard"
    dashboard_environment = environment_for(
        dashboard_root, owner, runtime, powershell
    )
    locate(owner, workspace, dashboard_environment)
    assert_dashboard_hold(
        owner,
        runtime,
        workspace,
        dashboard_root,
        dashboard_environment,
        identity,
    )

    assert_wrapper_rechecks_allocation(
        package,
        workspace,
        temporary / "distribution-wrapper-race",
        powershell,
        flock,
    )
    assert_owner_holds_both_locks(
        package,
        skills_root,
        workspace,
        temporary / "distribution-owner-locks",
        powershell,
        flock,
    )
    print("Nix 配布 Playwright package の owner/runtime/wrapper と両 lock を検証しました")


if __name__ == "__main__":
    main()
