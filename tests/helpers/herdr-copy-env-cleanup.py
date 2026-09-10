"""Exercise cleanup without importing the live probe's server-starting module body."""

import ast
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock, call

source = Path(__file__).with_name("herdr-copy-env-live.py")
function = next(
    node
    for node in ast.parse(source.read_text()).body
    if isinstance(node, ast.FunctionDef) and node.name == "stop_server"
)


class CleanupTest(unittest.TestCase):
    def setUp(self):
        self.run = Mock()
        self.server = Mock()
        namespace = {"subprocess": subprocess, "run": self.run, "herdr": ["herdr"]}
        exec(
            compile(ast.Module(body=[function], type_ignores=[]), str(source), "exec"),
            namespace,
        )
        self.stop = namespace["stop_server"]

    def test_graceful_stop(self):
        self.stop(self.server)
        self.run.assert_called_once_with(["herdr", "server", "stop"], check=False)
        self.server.wait.assert_called_once_with(timeout=15)
        self.server.terminate.assert_not_called()
        self.server.kill.assert_not_called()

    def test_termination_timeout_kills_and_reaps_preserving_first_failure(self):
        first = subprocess.TimeoutExpired("initial wait", 15)
        self.server.wait.side_effect = [
            first,
            subprocess.TimeoutExpired("term wait", 10),
            0,
        ]
        with self.assertRaises(subprocess.TimeoutExpired) as error:
            self.stop(self.server)
        self.assertIs(error.exception, first)
        self.assertEqual(
            self.server.mock_calls,
            [
                call.wait(timeout=15),
                call.terminate(),
                call.wait(timeout=10),
                call.kill(),
                call.wait(),
            ],
        )

    def test_stop_command_exception_still_waits(self):
        failure = subprocess.TimeoutExpired("herdr server stop", 30)
        self.run.side_effect = failure
        with self.assertRaises(subprocess.TimeoutExpired) as error:
            self.stop(self.server)
        self.assertIs(error.exception, failure)
        self.server.wait.assert_called_once_with(timeout=15)

    def test_stop_command_and_termination_failure_still_reap(self):
        self.run.side_effect = OSError("stop failed")
        self.server.wait.side_effect = [
            subprocess.TimeoutExpired("wait", 15),
            subprocess.TimeoutExpired("term", 10),
            0,
        ]
        with self.assertRaises(subprocess.TimeoutExpired):
            self.stop(self.server)
        self.server.kill.assert_called_once_with()
        self.assertEqual(self.server.wait.call_args, call())


if __name__ == "__main__":
    unittest.main()
