#!/usr/bin/env python3
"""Exercise real Herdr creation events and raw Codex in a private dummy session."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import tempfile
import time


class Probe:
    def __init__(self, output, control):
        self.output = output.resolve()
        self.output.mkdir(mode=0o700)
        self.source = Path(__file__).resolve().parents[1]
        self.repo = self.output / "source tree"
        self.work = self.output / "worktree"
        self.home = self.output / "home"
        self.control = control
        for directory in (
            self.home / ".codex",
            self.output / "runtime",
            self.output / "bin",
        ):
            directory.mkdir(parents=True, mode=0o700)
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(control),
            "XDG_STATE_HOME": str(self.output / "state"),
            "XDG_CACHE_HOME": str(self.output / "cache"),
            "XDG_RUNTIME_DIR": str(self.output / "runtime"),
            "CODEX_HOME": str(self.home / ".codex"),
            "CODEX_ISOLATION_CA_BUNDLE": os.environ["CODEX_ISOLATION_CA_BUNDLE"],
            "SHELL": str(Path(shutil.which("bash")).resolve()),
            "TERM": "xterm-256color",
            "NIX_CONFIG": "experimental-features = nix-command flakes",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "HERDR_DUMMY_SECRET": "dummy-inherited-value",
        }
        self.herdr = [shutil.which("herdr"), "--session", "isolation-273"]
        self.results = {}
        self.sequence = 0
        self.copy_logs = {}

    def run(self, arguments, cwd=None, check=True):
        result = subprocess.run(
            arguments,
            cwd=cwd or self.output,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=120,
        )
        if check and result.returncode:
            raise RuntimeError(f"{shlex.join(map(str, arguments))}: {result.stderr}")
        return result

    def api(self, *arguments):
        result = self.run([*self.herdr, *map(str, arguments)])
        if not result.stdout.strip():
            return None
        response = json.loads(result.stdout)
        self.sequence += 1
        (self.output / f"api-{self.sequence:03}.json").write_text(result.stdout)
        return response["result"]

    def wait(self, predicate, description, seconds=120):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            result = predicate()
            if result:
                return result
            time.sleep(0.2)
        raise AssertionError(f"timed out: {description}")

    def setup(self):
        self.run(["git", "init", "-qb", "main", str(self.repo)])
        self.run(["git", "config", "user.name", "Fixture"], self.repo)
        self.run(["git", "config", "user.email", "fixture@example.invalid"], self.repo)
        (self.repo / ".gitignore").write_text(".env\n.env.*\n__pycache__/\n")
        (self.repo / ".env").write_text("HERDR_DUMMY_SECRET=dummy-copied-value\n")
        (self.repo / ".env.local").write_text("dummy-alias-not-copied\n")
        plugin = self.repo / ".herdr"
        plugin.mkdir()
        self.manifest = plugin / "herdr-plugin.toml"
        self.manifest.write_bytes(
            (self.source / ".herdr/herdr-plugin.toml").read_bytes()
        )
        for name in ("codex-worktree", "devshell-env"):
            (self.output / "bin" / name).symlink_to(
                self.source / "private_dot_local/bin" / f"executable_{name}"
            )
        config = self.run(
            [
                "chezmoi",
                "--source",
                str(self.source),
                "execute-template",
                "-f",
                str(self.source / "private_dot_config/codex/config.toml.tmpl"),
            ]
        ).stdout
        (self.home / ".codex/config.toml").write_text(config)
        herdr_config = self.control / "herdr/config.toml"
        herdr_config.parent.mkdir(parents=True)
        herdr_config.write_text(
            'onboarding = false\n[terminal]\nshell_mode = "non_login"\n'
            f"default_shell = {json.dumps(self.env['SHELL'])}\n"
            "[update]\nversion_check = false\nmanifest_check = false\n"
        )
        self.run(["git", "add", ".gitignore"], self.repo)
        self.run(["git", "commit", "-qm", "test: dummy Herdr repository"], self.repo)

    def create(self, name):
        target = self.output / name
        previous = {
            entry["log_id"]
            for entry in self.api(
                "plugin", "log", "list", "--plugin", "dotfiles.copy-env"
            )["logs"]
        }
        response = self.api(
            "worktree",
            "create",
            "--cwd",
            self.repo,
            "--path",
            target,
            "--branch",
            f"test/{name}",
            "--no-focus",
        )
        entry = self.wait(
            lambda: next(
                (
                    entry
                    for entry in self.api(
                        "plugin", "log", "list", "--plugin", "dotfiles.copy-env"
                    )["logs"]
                    if entry["log_id"] not in previous
                ),
                None,
            ),
            "new copy event",
        )
        self.copy_logs[target] = entry["log_id"]
        return target, response

    def copy_result(self, target, expected="succeeded"):
        def finished():
            response = self.api(
                "plugin",
                "log",
                "list",
                "--plugin",
                "dotfiles.copy-env",
                "--limit",
                "50",
            )
            entries = response["logs"]
            return next(
                (
                    entry
                    for entry in entries
                    if entry["log_id"] == self.copy_logs[target]
                    and entry["status"] in ("succeeded", "failed")
                ),
                None,
            )

        entry = self.wait(finished, f"copy event for {target.name}")
        assert entry["status"] == expected, entry
        if expected == "succeeded":
            assert entry["exit_code"] == 0, entry
            assert f"copy-env: copied .env to {target}" in entry["stdout"], entry
            assert (target / ".env").read_bytes() == (self.repo / ".env").read_bytes()
            assert stat.S_IMODE((target / ".env").stat().st_mode) == 0o600
            assert not (target / ".env").is_symlink()
            assert not (target / ".env.local").exists()
        else:
            assert entry["exit_code"] != 0, entry
            assert "copy-env: copied" not in entry.get("stdout", ""), entry
        assert "dummy-" not in entry.get("stdout", "") + entry.get("stderr", "")
        return entry

    def public_inputs(self, target):
        paths = [
            target / name
            for name in (".env", ".env.local", "late-secret", "renamed-secret")
        ]
        paths.extend([self.repo / ".env", self.output / "other-worktree/.env"])
        sockets = list(self.control.rglob("*.sock"))
        assert sockets, "no private Herdr control socket found"
        (target / "boundary.json").write_text(
            json.dumps(
                {"paths": list(map(str, paths)), "sockets": list(map(str, sockets))}
            )
        )
        (target / "boundary.py").write_text("""import json, os, shutil, socket, sys
from pathlib import Path
assert not any(name.startswith("HERDR_") for name in os.environ)
assert shutil.which("herdr") is None
boundary = json.loads(Path("boundary.json").read_text())
for name in boundary["paths"]:
    try:
        content = Path(name).read_bytes()
    except OSError:
        continue
    assert not content, "host file contents reached isolation"
for name in boundary["sockets"]:
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(name)
    except OSError:
        continue
    raise AssertionError("host Herdr control socket reached isolation")
assert Path("source.txt").read_text() == "public source\\n"
print("BOUNDARY_OK " + sys.argv[1], flush=True)
""")
        (target / "source.txt").write_text("public source\n")
        bash = Path(self.env["SHELL"]).parent.parent
        utils = Path(shutil.which("cat")).resolve().parent.parent
        python = Path(shutil.which("python3")).resolve().parent.parent
        system = {"x86_64": "x86_64-linux", "aarch64": "aarch64-linux"}[
            os.uname().machine
        ]
        hook = 'python3 boundary.py initialization || return $?; printf "run\\n" >> hook-calls'
        (target / "flake.nix").write_text(
            """{ outputs = { self }:
assert !(builtins.pathExists %s);
{ devShells.%s.default = builtins.derivation {
name = "herdr-test"; system = "%s"; builder = "%s/bin/bash";
args = [ "-c" "exit 0" ]; outputs = [ "out" ];
PATH = "%s/bin:%s/bin:%s/bin"; shellHook = %s;
}; }; }"""
            % (
                json.dumps(str(target / ".env")),
                system,
                system,
                bash,
                bash,
                utils,
                python,
                json.dumps(hook),
            )
        )
        (target / "task.sh").write_text("""set -eu
python3 boundary.py command
printf 'ISOLATED_READY\\n'
read -r reply
test "$reply" = continue
python3 boundary.py child
with-env --prepared -- python3 boundary.py prepared
printf 'def add(a, b): return a + b\\n' > calculator.py
python3 -m py_compile calculator.py
python3 -c 'from calculator import add; assert add(2, 3) == 5'
git add calculator.py
git commit -qm 'test: develop in Herdr without host dotenv'
printf 'ISOLATED_TASK_OK\\n'
""")
        names = [
            ".gitignore",
            "flake.nix",
            "boundary.py",
            "boundary.json",
            "source.txt",
            "task.sh",
        ]
        self.run(["git", "add", "--", *names], target)
        self.run(["git", "commit", "-qm", "test: public Herdr fixture"], target)
        self.run([str(self.output / "bin/devshell-env"), "trust"], target)
        head = self.run(["git", "rev-parse", "HEAD"], target).stdout.strip()
        self.run(
            [
                str(self.output / "bin/devshell-env"),
                "admit",
                "--git-head",
                head,
                "--",
                *names,
            ],
            target,
        )

    def start(self, pane, target, label, arguments):
        script = self.output / f"{label}.sh"
        log = self.output / f"{label}.log"
        status = self.output / f"{label}.status"
        script.write_text(
            'test "$HERDR_ENV" = 1 || exit 90\n'
            f'test "$PWD" = {shlex.quote(str(target))} || exit 91\n'
            + shlex.join([str(self.output / "bin/codex-worktree"), *arguments])
            + f" > {shlex.quote(str(log))} 2>&1\n"
            + f'printf "%s\\n" "$?" > {shlex.quote(str(status))}\n'
        )
        self.api("pane", "run", pane, shlex.join([self.env["SHELL"], str(script)]))
        return log, status

    def complete(self, log, status, expected=0):
        self.wait(status.exists, f"terminal completion: {status.name}", 180)
        text = log.read_text()
        assert int(status.read_text()) == expected, text
        assert "dummy-" not in text, "dummy value appeared in terminal output"
        return text

    def ready(self, log, status):
        self.wait(
            lambda: (
                status.exists()
                or (log.exists() and "ISOLATED_READY" in log.read_text())
            ),
            "isolated command ready",
        )
        assert not status.exists(), log.read_text()

    def change_host_secrets(self, target):
        (target / ".env").write_text("HERDR_DUMMY_SECRET=dummy-replaced-value\n")
        (target / "late-secret").write_text("dummy-late-value\n")
        (target / "renamed-secret").symlink_to(self.repo / ".env")

    def exercise(self):
        self.api("plugin", "link", self.manifest.parent)
        primary = self.api("workspace", "create", "--cwd", self.repo, "--no-focus")
        self.work, created = self.create("worktree")
        self.copy_result(self.work)
        other, _ = self.create("other-worktree")
        self.copy_result(other)
        pane = created["root_pane"]["pane_id"]
        assert created["root_pane"]["cwd"] == str(self.work)
        assert created["worktree"]["is_linked_worktree"]
        log, status = self.start(pane, self.work, "untrusted-refused", ["--version"])
        assert "untrusted repository" in self.complete(log, status, expected=1)
        self.results["untrusted_worktree_refused"] = "passed"
        self.public_inputs(self.work)
        log, status = self.start(
            pane, self.work, "copied", ["sandbox", "--", "bash", "task.sh"]
        )
        self.ready(log, status)
        self.change_host_secrets(self.work)
        self.api("pane", "send-text", pane, "continue\n")
        text = self.complete(log, status)
        assert "ISOLATED_TASK_OK" in text, text
        assert (self.work / "hook-calls").read_text() == "run\n"
        assert (
            self.run(["git", "log", "-1", "--format=%s"], self.work).stdout.strip()
            == "test: develop in Herdr without host dotenv"
        )
        assert (
            self.work / "calculator.py"
        ).read_text() == "def add(a, b): return a + b\n"
        self.run(
            ["git", "diff", "--exit-code", "HEAD", "--", "calculator.py"], self.work
        )
        assert (
            self.work / ".env"
        ).read_text() == "HERDR_DUMMY_SECRET=dummy-replaced-value\n"
        assert (
            self.repo / ".env"
        ).read_text() == "HERDR_DUMMY_SECRET=dummy-copied-value\n"
        self.results["copy_then_develop"] = "passed"
        log, status = self.start(
            pane,
            self.work,
            "restart",
            ["sandbox", "--", "python3", "boundary.py", "restart"],
        )
        assert "BOUNDARY_OK restart" in self.complete(log, status)
        assert (self.work / "hook-calls").read_text() == "run\nrun\n"
        self.results["restart_with_host_secrets"] = "passed"

        # Only this test manifest holds the real event before cp, with a bounded
        # host-side rendezvous. Production copy and raw entry stay unchanged.
        original = self.manifest.read_text()
        gate = """printf 'waiting\\n' > "$worktree/.copy-waiting"
for (( attempt=0; attempt<600; attempt++ )); do
  [ -e "$HERDR_PLUGIN_ROOT/release-copy" ] && break
  sleep 0.2
done
[ -e "$HERDR_PLUGIN_ROOT/release-copy" ] || fail 'test copy gate timed out'
"""
        self.manifest.write_text(
            original.replace(
                'cp "$repo/.env" "$worktree/.env"',
                gate + 'cp "$repo/.env" "$worktree/.env"',
            )
        )
        self.api("plugin", "link", self.manifest.parent)
        delayed, created = self.create("delayed-worktree")
        self.wait((delayed / ".copy-waiting").exists, "copy held before cp")
        assert not (delayed / ".env").exists()
        self.public_inputs(delayed)
        head = self.run(["git", "rev-parse", "HEAD"], delayed).stdout
        pane = created["root_pane"]["pane_id"]
        log, status = self.start(
            pane, delayed, "delayed", ["sandbox", "--", "bash", "task.sh"]
        )
        self.ready(log, status)
        (self.manifest.parent / "release-copy").touch()
        self.copy_result(delayed)
        self.change_host_secrets(delayed)
        (delayed / "source.txt").write_text("dummy-concurrent-replacement\n")
        self.api("pane", "send-text", pane, "continue\n")
        text = self.complete(log, status, expected=1)
        assert "ISOLATED_TASK_OK" in text and "host input changed" in text, text
        assert self.run(["git", "rev-parse", "HEAD"], delayed).stdout == head
        assert not (delayed / "calculator.py").exists()
        assert (delayed / "source.txt").read_text() == "dummy-concurrent-replacement\n"
        self.results["copy_during_session_and_host_conflict"] = "passed"

        self.manifest.write_text(original)
        self.api("plugin", "link", self.manifest.parent)
        (self.repo / ".env").rename(self.repo / ".env-retained")
        failed, _ = self.create("failed-copy")
        self.copy_result(failed, "failed")
        assert not (failed / ".env").exists()
        self.results["failed_copy_is_not_launch_readiness"] = "passed"

        log, status = self.start(
            primary["root_pane"]["pane_id"], self.repo, "primary-refused", ["--version"]
        )
        assert "not a linked Git worktree" in self.complete(log, status, expected=1)
        self.results["primary_checkout_refused"] = "passed"

    def stop_server(self, server):
        try:
            stopped = self.run([*self.herdr, "server", "stop"], check=False)
            (self.output / "stop.log").write_text(stopped.stdout + stopped.stderr)
            stopped.check_returncode()
        finally:
            try:
                server.wait(timeout=30)
            except subprocess.TimeoutExpired:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
                raise

    def main(self):
        self.setup()
        with (self.output / "server.log").open("w") as log:
            server = subprocess.Popen(
                [*self.herdr, "server"],
                cwd=self.output,
                env=self.env,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                self.wait(
                    lambda: (
                        self.run(
                            [*self.herdr, "workspace", "list"], check=False
                        ).returncode
                        == 0
                    ),
                    "private Herdr server startup",
                    30,
                )
                self.exercise()
            finally:
                self.stop_server(server)
        report = {
            "kernel": os.uname().release,
            "tools": {
                name: self.run([name, "--version"]).stdout.strip()
                for name in ("herdr", "nix", "codex", "python3", "git", "bwrap")
            },
            "manifest_sha256": hashlib.sha256(self.manifest.read_bytes()).hexdigest(),
            "worktree_owner": "real Herdr worktree create",
            "codex_execution": "real codex-worktree sandbox; no hosted model or external tool login",
            "checks": self.results,
        }
        (self.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Herdr isolation evidence: {self.output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    # Herdr's UNIX socket must fit sockaddr_un even under a long Bats TMPDIR.
    with tempfile.TemporaryDirectory(prefix="h273-", dir="/tmp") as control:
        Probe(arguments.output, Path(control)).main()
