"""D1 の公開 CLI 境界を、合成定義と HTTP primitive の stub で検証する。"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
FIXTURE = Path(sys.argv.pop(1))
SOURCE = Path(__file__).resolve().parents[2] / "private_dot_config/nix-devshell/packages/cloudflare-cli/cloudflare-inspect.py"
spec = importlib.util.spec_from_file_location("cloudflare_inspect", SOURCE)
assert spec is not None and spec.loader is not None
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class D1(unittest.TestCase):
    def setUp(self):
        self.root = FIXTURE / self.id().split(".")[-1]
        self.root.mkdir(mode=0o700)
        self.scratch = self.root / "scratch"
        self.scratch.mkdir(mode=0o700)
        self.definition = {
            "version": 1,
            "account_id": "0123456789abcdef0123456789abcdef",
            "database_id": "01234567-89ab-cdef-0123-456789abcdef",
            "table": "fixture_records",
            "allowed_columns": ["state", "category"],
            "select": ["state"],
            "where": [{"column": "category", "operator": "=", "parameter": "category"}],
            "order_by": [{"column": "state", "direction": "asc"}],
            "parameters": {"category": {"type": "string", "max_length": 16, "values": ["ready"]}},
            "max_rows": 100,
            "timeout_seconds": 30,
        }
        self.file = self.root / "definition.json"
        self.params = self.root / "params.json"
        self.write(self.params, {"category": "ready"})
        self.response = {"success": True, "errors": [], "messages": [], "result": [{
            "success": True, "results": [{"state": "available"}],
            "meta": {"rows_read": 7, "rows_written": 0, "duration": 0.5},
        }]}
        self.calls = self.root / "http.jsonl"
        self.http_status = 200
        self.request_delay = 0

    def write(self, path, value):
        path.write_text(json.dumps(value))
        path.chmod(0o600)

    def exchange(self, opener, request, timeout):
        with self.calls.open("a") as output:
            output.write(json.dumps({"url": request.full_url, "method": request.method,
                                     "body": json.loads(request.data)}) + "\n")
        time.sleep(self.request_delay)
        return self.http_status, json.dumps(self.response).encode()

    def invoke(self, *extra):
        self.write(self.file, self.definition)
        expected = hashlib.sha256(self.file.read_bytes()).hexdigest()
        output = io.StringIO()
        with patch.dict(os.environ, {"CLOUDFLARE_API_TOKEN": "DUMMY_CF_TOKEN",
                                     "CLOUDFLARE_ACCOUNT_ID": self.definition["account_id"]}, clear=True), \
                patch.object(helper, "D1_SCRATCH", self.scratch, create=True), \
                patch.object(helper, "http_exchange", self.exchange, create=True), \
                contextlib.redirect_stdout(output):
            status = helper.main(["--reviewed", "d1", "read", "--definition", str(self.file),
                                  "--sha256", expected, "--params-file", str(self.params), *extra])
        return status, json.loads(output.getvalue())

    def test_select(self):
        status, summary = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(summary["returned_count"], 1)
        self.assertEqual(summary["rows_read"], 7)
        self.assertEqual(summary["stop_reason"], "complete")
        self.assertNotIn("available", json.dumps(summary))
        self.assertNotIn("fixture_records", json.dumps(summary))
        self.assertEqual([json.loads(line) for line in self.calls.read_text().splitlines()], [{
            "url": "https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/d1/database/01234567-89ab-cdef-0123-456789abcdef/query",
            "method": "POST", "body": {
                "sql": "SELECT [state] FROM [fixture_records] WHERE [category] = ? ORDER BY [state] ASC LIMIT 100",
                "params": ["ready"],
            },
        }])
        record = Path(summary["record"])
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.assertEqual(record.parent.stat().st_mode & 0o777, 0o700)
        audit = json.loads(record.read_text())
        self.assertEqual(audit["results"], [{"state": "available"}])
        self.assertEqual(audit["query_plan"], None)
        self.assertEqual(audit["query_plan_reason"], "not_requested")
        self.assertNotIn("DUMMY_CF_TOKEN", record.read_text())

    def test_http_failure(self):
        self.http_status = 503
        self.response = {"error": "DUMMY_CF_TOKEN private-payload"}
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stop_reason"], "http_error")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.assertNotIn("private-payload", json.dumps(summary))
        record = Path(summary["record"]).read_text()
        self.assertNotIn("DUMMY_CF_TOKEN", record)
        self.assertNotIn("private-payload", record)
        self.assertEqual(json.loads(record)["status"], "failed")

    def test_deadline(self):
        self.definition["timeout_seconds"] = 1
        self.request_delay = 5
        started = time.monotonic()
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(summary["stop_reason"], "deadline_exceeded")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        audit = json.loads(Path(summary["record"]).read_text())
        self.assertEqual(audit["attempts_started"], 1)
        self.assertEqual(audit["stop_reason"], "interrupted_or_deadline")
        self.assertEqual(audit["status"], "pending")


if __name__ == "__main__":
    unittest.main()
