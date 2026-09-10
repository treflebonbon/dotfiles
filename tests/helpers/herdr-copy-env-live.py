#!/usr/bin/env python3
"""Test registration and global worktree events in an isolated real Herdr session."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parents[2]
output = Path(tempfile.mkdtemp(prefix="herdr-env-", dir="/tmp"))
home = output / "home"
home.mkdir()
env = {
    "PATH": os.environ["PATH"], "HOME": str(home),
    "XDG_CONFIG_HOME": str(output / "cfg"),
    "XDG_STATE_HOME": str(output / "state"),
    "XDG_CACHE_HOME": str(output / "cache"),
    "XDG_RUNTIME_DIR": str(output / "runtime"),
    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
    "SHELL": shutil.which("bash"), "TERM": "xterm-256color",
}
(output / "runtime").mkdir()
config = output / "cfg/herdr/config.toml"
config.parent.mkdir(parents=True)
config.write_text('onboarding = false\n[terminal]\nshell_mode = "non_login"\n'
                  f'default_shell = {json.dumps(env["SHELL"])}\n'
                  '[update]\nversion_check = false\nmanifest_check = false\n')
lib = home / ".config/nix-devshell/lib/ensure-env.sh"
lib.parent.mkdir(parents=True)
lib.write_text("ensure_nix_devshell_env() { :; }\n")
herdr = [shutil.which("herdr"), "--session", "copy-env-test"]


def run(args, cwd=output, check=True):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise RuntimeError(f"{args}: {result.stderr}")
    return result


def api(*args):
    return json.loads(run([*herdr, *map(str, args)]).stdout)["result"]


def wait(fn):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError("timed out")


def repo(name):
    path = output / name
    run(["git", "init", "-qb", "main", str(path)])
    (path / ".gitignore").write_text(".env\n.env.*\n")
    run(["git", "add", ".gitignore"], path)
    run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
         "commit", "-qm", "test: dummy repository"], path)
    return path


source = repo("plugin source")
shutil.copytree(project / ".herdr", source / ".herdr")
env["CHEZMOI_SOURCE_DIR"] = str(source)
setup = ["bash", str(project / "run_after_setup-herdr.sh")]
# Offline registration uses the normal default session; the registry is user-wide.
run(setup)
run(setup)
assert api("plugin", "list", "--plugin", "dotfiles.copy-env", "--json")["plugins"][0]["enabled"]
# Linking disabled works offline and provides the same state as manual disable.
api("plugin", "link", source / ".herdr", "--disabled")
run(setup)
assert not api("plugin", "list", "--json")["plugins"][0]["enabled"]
relocated = output / "relocated plugin source"
source.rename(relocated)
env["CHEZMOI_SOURCE_DIR"] = str(relocated)
run(setup)
plugin = api("plugin", "list", "--json")["plugins"][0]
assert plugin["plugin_root"] == str(relocated / ".herdr") and not plugin["enabled"]

with (output / "server.log").open("w") as log:
    server = subprocess.Popen([*herdr, "server"], cwd=output, env=env, stdout=log, stderr=log)
    try:
        wait(lambda: run([*herdr, "workspace", "list"], check=False).returncode == 0)
        api("plugin", "enable", "dotfiles.copy-env")
        run(setup)
        results = []
        for index in range(3):
            primary = repo(f"project {index}")
            if index < 2:
                (primary / ".env").write_text(f"DUMMY_VALUE=fixture-{index}\n")
            (primary / ".env.local").write_text("DUMMY_ALIAS=not-copied\n")
            api("workspace", "create", "--cwd", primary, "--no-focus")
            previous = {item["log_id"] for item in api("plugin", "log", "list")["logs"]}
            target = output / f"worktree {index}"
            api("worktree", "create", "--cwd", primary, "--path", target,
                "--branch", "test/copy", "--no-focus")
            entry = wait(lambda: next((item for item in api("plugin", "log", "list")["logs"]
                         if item["log_id"] not in previous and item["status"] in ("succeeded", "failed")), None))
            assert entry["status"] == "succeeded" and entry["exit_code"] == 0, entry
            if index < 2:
                assert (target / ".env").read_bytes() == (primary / ".env").read_bytes()
                assert (target / ".env").stat().st_mode & 0o777 == 0o600
                (target / ".env").write_text("LOCAL_EDIT=preserved\n")
                api("worktree", "open", "--cwd", primary, "--path", target, "--no-focus")
                assert (target / ".env").read_text() == "LOCAL_EDIT=preserved\n"
            else:
                assert not (target / ".env").exists()
                assert "skipped (source .env absent)" in entry["stdout"]
            assert not (target / ".env.local").exists()
            assert "fixture-" not in json.dumps(entry)
            results.append(entry)
        api("plugin", "disable", "dotfiles.copy-env")
        run(setup)
        assert not api("plugin", "list", "--json")["plugins"][0]["enabled"]
        (output / "results.json").write_text(json.dumps(results, indent=2))
    finally:
        run([*herdr, "server", "stop"], check=False)
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.terminate()
            server.wait(timeout=10)
            raise
print(f"PASS: offline registration, relocation, disable preservation, global events; evidence: {output}")
