import importlib.util
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "herdr_probe",
    Path(__file__).resolve().parents[2] / "scripts/herdr-codex-isolation.py",
)
herdr_probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(herdr_probe)


class ProbeRegression(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="h273-regression-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.probe = herdr_probe.Probe.__new__(herdr_probe.Probe)
        self.probe.output = self.root
        self.probe.herdr = ["herdr", "--session", "isolation-273"]
        self.probe.run = Mock(
            return_value=subprocess.CompletedProcess([], 0, "stopped\n", "")
        )

    def test_generated_flake_supports_each_linux_architecture(self):
        self.probe.repo = self.root / "repo"
        self.probe.control = self.root / "control"
        self.probe.control.mkdir()
        (self.probe.control / "server.sock").touch()
        self.probe.env = {"SHELL": str(Path(shutil.which("bash")).resolve())}
        for architecture in ("x86_64", "aarch64"):
            with self.subTest(architecture=architecture):
                target = self.root / architecture
                target.mkdir()
                with patch.object(
                    herdr_probe.os,
                    "uname",
                    return_value=SimpleNamespace(machine=architecture),
                ):
                    self.probe.public_inputs(target)
                system = f"{architecture}-linux"
                result = subprocess.run(
                    [
                        "nix",
                        "--extra-experimental-features",
                        "nix-command flakes",
                        "eval",
                        "--raw",
                        f"path:{target}#devShells.{system}.default.system",
                    ],
                    text=True,
                    capture_output=True,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, system)

    def server(self, ignore_terminate=False):
        child = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import signal, time; "
                + (
                    "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                    if ignore_terminate
                    else ""
                )
                + "print('ready', flush=True); time.sleep(60)",
            ],
            stdout=subprocess.PIPE,
            text=True,
        )

        def cleanup():
            if child.poll() is None:
                child.kill()
            child.wait()
            child.stdout.close()

        self.addCleanup(cleanup)
        self.assertEqual(child.stdout.readline(), "ready\n")
        wait = child.wait
        # Keep real process waits and signals, shortening only the grace periods.
        accelerated = patch.object(
            child,
            "wait",
            side_effect=lambda timeout=None: wait(0.1 if timeout is not None else None),
        )
        accelerated.start()
        self.addCleanup(accelerated.stop)
        return child

    def assert_reaped(self, child, expected_signal):
        self.assertEqual(child.returncode, -expected_signal)
        with self.assertRaises(ChildProcessError):
            os.waitpid(child.pid, os.WNOHANG)

    def test_graceful_stop_preserves_log(self):
        child = self.server()
        self.probe.run.side_effect = lambda *args, **kwargs: (
            child.terminate() or subprocess.CompletedProcess([], 0, "stopped\n", "")
        )
        self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGTERM)
        self.assertEqual((self.root / "stop.log").read_text(), "stopped\n")

    def test_failed_stop_exit_status_is_reported(self):
        child = self.server()
        child.terminate()
        self.probe.run.return_value = subprocess.CompletedProcess([], 1, "", "failed\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGTERM)
        self.assertEqual((self.root / "stop.log").read_text(), "failed\n")

    def test_stuck_server_is_terminated_and_failure_is_reported(self):
        child = self.server()
        with self.assertRaises(subprocess.TimeoutExpired):
            self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGTERM)

    def test_server_ignoring_terminate_is_killed_and_reaped(self):
        child = self.server(ignore_terminate=True)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGKILL)

    def test_stop_command_timeout_still_reaps_server(self):
        child = self.server(ignore_terminate=True)
        self.probe.run.side_effect = subprocess.TimeoutExpired("herdr server stop", 120)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGKILL)

    def test_stop_log_failure_still_reaps_server(self):
        child = self.server()
        (self.root / "stop.log").mkdir()
        with self.assertRaises(subprocess.TimeoutExpired):
            self.probe.stop_server(child)
        self.assert_reaped(child, signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
