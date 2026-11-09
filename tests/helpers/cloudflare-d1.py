"""D1 の公開 CLI 境界を、合成定義と HTTP primitive の stub で検証する。"""

import contextlib
import copy
from email.message import Message
import hashlib
from http.client import BadStatusLine, IncompleteRead, LineTooLong
import importlib.machinery
import importlib.util
import io
import json
import multiprocessing.connection
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import time
import unittest
from typing import Any
from unittest.mock import patch
import urllib.request
import urllib.response

sys.dont_write_bytecode = True
FIXTURE = Path(sys.argv.pop(1))
SOURCE = Path(__file__).resolve().parents[2] / "private_dot_config/nix-devshell/packages/cloudflare-cli/cloudflare-inspect.py"
if len(sys.argv) > 1 and sys.argv[1] == "--installed":
    sys.argv.pop(1)
    installed = shutil.which("cloudflare-inspect")
    assert installed is not None
    SOURCE = Path(installed).resolve()
spec = importlib.util.spec_from_file_location("cloudflare_inspect", SOURCE,
                                            loader=importlib.machinery.SourceFileLoader("cloudflare_inspect", str(SOURCE)))
assert spec is not None and spec.loader is not None
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class FixtureResponse(urllib.response.addinfourl):
    msg = "Fixture"


class D1(unittest.TestCase):
    def setUp(self):
        self.root = FIXTURE / self.id().split(".")[-1]
        self.root.mkdir(mode=0o700)
        self.scratch = self.root / "scratch"
        self.scratch.mkdir(mode=0o700)
        self.definition: dict[str, Any] = {
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
            "max_plan_rows": 100,
            "timeout_seconds": 30,
        }
        self.file = self.root / "definition.json"
        self.params = self.root / "params.json"
        self.write(self.params, {"category": "ready"})
        self.response: dict[str, Any] = {"success": True, "errors": [], "messages": [], "result": [{
            "success": True, "results": [{"state": "available"}],
            "meta": {"rows_read": 7, "rows_written": 0, "duration": 0.5, "changed_db": False,
                     "changes": 0, "last_row_id": 0, "size_after": 4096, "served_by_colo": "LHR",
                     "served_by_primary": True, "served_by_region": "EEUR", "timings": {"sql_duration_ms": 0.5}},
        }]}
        self.calls = self.root / "http.jsonl"
        self.http_status = 200
        self.http_exception = None
        self.response_raw = None
        self.request_delay = 0
        self.real_transport = False
        self.fail_replace = None
        self.first_record_delay = 0
        self.definition_mode = 0o600
        self.definition_raw = None
        self.environment = {}
        self.expected_proxy = None
        self.delay_deadline_notice = False
        self.execute_sql = False

    def write(self, path, value):
        if path.exists():
            path.chmod(0o600)
        path.write_text(json.dumps(value))
        path.chmod(0o600)

    def exchange(self, opener, request, timeout):
        body = json.loads(request.data)
        with self.calls.open("a") as output:
            output.write(json.dumps({"url": request.full_url, "method": request.method,
                                     "body": body}) + "\n")
        time.sleep(self.request_delay)
        if self.http_exception is not None:
            raise self.http_exception
        if self.response_raw is not None:
            return self.http_status, self.response_raw
        if self.execute_sql:
            with sqlite3.connect(":memory:") as database:
                database.executescript("CREATE TABLE fixture_records (state TEXT, category TEXT); "
                                       "INSERT INTO fixture_records VALUES ('available', 'ready');")
                try:
                    cursor = database.execute(body["sql"], body["params"])
                except sqlite3.Error:
                    return 400, b""
                self.response["result"][0]["results"] = [dict(zip([item[0] for item in cursor.description], row)) for row in cursor.fetchall()]
        return self.http_status, json.dumps(self.response).encode()

    def https_open(self, handler, request):
        if self.expected_proxy is not None:
            self.assertEqual(request.host, self.expected_proxy)
        status, raw = self.exchange(None, request, 30)
        headers = Message()
        headers["Location"] = "https://untrusted.invalid/"
        headers["Content-Type"] = "application/json"
        headers["Proxy-Authenticate"] = 'Basic realm="fixture"'
        return FixtureResponse(io.BytesIO(raw), headers, request.full_url, status)

    def invoke(self, *extra, with_params=True):
        self.write(self.file, self.definition)
        if self.definition_raw is not None:
            self.file.write_bytes(self.definition_raw)
        self.file.chmod(self.definition_mode)
        expected = hashlib.sha256(self.file.read_bytes()).hexdigest()
        output = io.StringIO()
        replace = os.replace
        receive = multiprocessing.connection.Connection.recv
        replacements = 0

        def receive_message(connection):
            message = receive(connection)
            if self.delay_deadline_notice and isinstance(message, dict) and "deadline" in message:
                time.sleep(2)
            return message

        def replace_record(*args, **kwargs):
            nonlocal replacements
            replacements += 1
            if replacements == 1:
                time.sleep(self.first_record_delay)
            if self.fail_replace is not None and replacements >= self.fail_replace:
                raise OSError("DUMMY_CF_TOKEN private-storage-error")
            return replace(*args, **kwargs)

        exchange = helper.http_exchange if self.real_transport else self.exchange
        params = ["--params-file", str(self.params)] if with_params else []
        with patch.dict(os.environ, {"CLOUDFLARE_API_TOKEN": "DUMMY_CF_TOKEN",
                                     "CLOUDFLARE_ACCOUNT_ID": "0123456789abcdef0123456789abcdef", **self.environment}, clear=True), \
                patch.object(os, "replace", replace_record), \
                patch.object(multiprocessing.connection.Connection, "recv", receive_message), \
                patch.object(helper, "D1_SCRATCH", self.scratch, create=True), \
                patch.object(helper, "http_exchange", exchange, create=True), \
                patch.object(urllib.request.HTTPSHandler, "https_open", lambda handler, request: self.https_open(handler, request)), \
                contextlib.redirect_stdout(output):
            status = helper.main(["--reviewed", "d1", "read", "--definition", str(self.file),
                                  "--sha256", expected, *params, *extra])
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
        self.assertEqual(audit["implementation"]["helper_path"], str(SOURCE.resolve()))
        self.assertEqual(audit["implementation"]["helper_sha256"], hashlib.sha256(SOURCE.read_bytes()).hexdigest())
        self.assertEqual(audit["implementation"]["cli_pin"], "1.0.0-beta.26")
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

    def test_http_protocol_failure(self):
        errors = (IncompleteRead(b"DUMMY_CF_TOKEN private-payload"),
                  BadStatusLine("DUMMY_CF_TOKEN private-payload"), LineTooLong("DUMMY_CF_TOKEN private-payload"))
        for index, error in enumerate(errors, 1):
            with self.subTest(error=type(error).__name__):
                self.http_exception = error
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "request_failed")
                self.assertEqual(summary["attempts_started"], 1)
                self.assertIsNone(summary["returned_count"])
                self.assertEqual(len(self.calls.read_text().splitlines()), index)
                record = Path(summary["record"]).read_text()
                self.assertEqual(json.loads(record)["status"], "failed")
                self.assertEqual(json.loads(record)["stop_reason"], "request_failed")
                self.assertNotIn("private-payload", record + json.dumps(summary))
                self.assertNotIn("DUMMY_CF_TOKEN", record + json.dumps(summary))

    def test_sql_boundaries(self):
        self.execute_sql = True
        value = "ready' OR 1=1 --"
        self.definition["parameters"]["category"]["values"] = [value]
        self.write(self.params, {"category": value})
        status, summary = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(summary["returned_count"], 0)
        status, summary = self.invoke("--mode", "explain", "--limit", "1")
        self.assertEqual(status, 0)
        plan = json.loads(Path(summary["record"]).read_text())["query_plan"]
        self.assertGreater(len(plan), 0)
        self.assertEqual(set(plan[0]), {"id", "parent", "notused", "detail"})
        self.definition["select"] = ["missing"]
        self.definition["allowed_columns"].append("missing")
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "http_error")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 3)

    def test_delayed_deadline_notice(self):
        self.definition["timeout_seconds"] = 1
        self.request_delay = 5
        self.delay_deadline_notice = True
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "deadline_exceeded")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertIsNotNone(summary["record"])
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

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

    def test_expired_before_request(self):
        self.definition["timeout_seconds"] = 1
        self.first_record_delay = 1.2
        self.delay_deadline_notice = True
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "deadline_exceeded")
        self.assertEqual(summary["attempts_started"], 0)
        self.assertFalse(self.calls.exists())

    def test_redirect(self):
        self.real_transport = True
        self.http_status = 302
        self.response = {"private": "DUMMY_CF_TOKEN"}
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "http_error")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_proxy_challenge(self):
        self.real_transport = True
        self.environment = {"HTTPS_PROXY": "http://DUMMY_PROXY_USER:DUMMY_PROXY_PASS@proxy.invalid:8080", "NO_PROXY": ""}
        self.expected_proxy = "proxy.invalid:8080"
        self.http_status = 407
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "http_error")
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.assertNotIn("DUMMY_PROXY", json.dumps(summary))
        self.assertNotIn("DUMMY_PROXY", Path(summary["record"]).read_text())

    def test_invalid_response(self):
        valid = copy.deepcopy(self.response)
        sentinel = "INVALID_RESPONSE_SECRET_SENTINEL"
        cases = [
            ("json", lambda r: setattr(self, "response_raw", b'{"result":' + sentinel.encode())),
            ("top_level", lambda r: r.update(unapproved=sentinel)),
            ("top_level", lambda r: r.update(success=False)),
            ("result", lambda r: r["result"][0].update(success=False)),
            ("result", lambda r: r["result"].append(r["result"][0])),
            ("row", lambda r: r["result"][0]["results"][0].update(unapproved=sentinel)),
            ("statistics", lambda r: r["result"][0]["meta"].update(rows_read=sentinel)),
            ("statistics", lambda r: r["result"][0]["meta"].update(rows_read=0.5)),
            ("statistics", lambda r: r["result"][0]["meta"].update(rows_read=True)),
            ("json", lambda r: r["result"][0]["meta"].update(duration=float("nan"))),
            ("statistics", lambda r: r["result"][0]["meta"].pop("rows_written")),
            ("statistics", lambda r: r["result"][0]["meta"].update(unknown=1)),
            ("statistics", lambda r: r["result"][0]["meta"].update(changes=False)),
            ("statistics", lambda r: r["result"][0]["meta"].update(served_by_primary="yes")),
            ("statistics", lambda r: r["result"][0]["meta"].update(served_by_region="unknown")),
            ("statistics", lambda r: r["result"][0]["meta"].update(timings={"sql_duration_ms": "invalid"})),
            ("statistics", lambda r: r["result"][0]["meta"].update(timings={"unknown": 0})),
            ("write", lambda r: r["result"][0]["meta"].update(rows_written=1)),
            ("write", lambda r: r["result"][0]["meta"].update(changed_db=True)),
            ("write", lambda r: r["result"][0]["meta"].update(changes=1)),
        ]
        allowed_diagnostics = {stage for stage, _ in cases}
        for index, (diagnostic, change) in enumerate(cases):
            with self.subTest(index=index, diagnostic=diagnostic):
                self.response = copy.deepcopy(valid)
                self.response_raw = None
                change(self.response)
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "invalid_response")
                self.assertEqual(summary["attempts_started"], 1)
                self.assertEqual(len(self.calls.read_text().splitlines()), index + 1)
                self.assertNotIn("response_validation_failure", summary)
                audit = json.loads(Path(summary["record"]).read_text())
                self.assertEqual(audit["status"], "failed")
                self.assertEqual(audit["response_validation_failure"], diagnostic)
                self.assertIn(audit["response_validation_failure"], allowed_diagnostics)
                self.assertNotIn("results", audit)
                record = Path(summary["record"]).read_text()
                self.assertNotIn(sentinel, record + json.dumps(summary))

        self.response = copy.deepcopy(valid)
        self.response_raw = None
        status, summary = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(len(self.calls.read_text().splitlines()), len(cases) + 1)
        self.assertNotIn("response_validation_failure", json.loads(Path(summary["record"]).read_text()))

    def test_invalid_definition(self):
        valid = copy.deepcopy(self.definition)
        cases = [
            lambda d: d.update(sql="SELECT * FROM fixture_records; DELETE FROM fixture_records"),
            lambda d: d.update(version=True),
            lambda d: d.update(account_id="fedcba9876543210fedcba9876543210"),
            lambda d: d.update(table="fixture_records; DROP TABLE x"),
            lambda d: d.update(table="sqlite_schema"),
            lambda d: d.update(select=["*"]),
            lambda d: d.update(select=["unapproved"]),
            lambda d: d["where"][0].update(column="unapproved"),
            lambda d: d["where"][0].update(operator="OR 1=1"),
            lambda d: d["order_by"][0].update(column="unapproved"),
            lambda d: d["order_by"][0].update(direction="asc; DELETE"),
            lambda d: d["parameters"]["category"].update(type="number"),
            lambda d: d["parameters"]["category"].update(values=["other"]),
            lambda d: d.update(max_rows=1001),
            lambda d: d.update(max_plan_rows=1001),
            lambda d: d.update(max_plan_rows=True),
            lambda d: d.pop("max_plan_rows"),
            lambda d: d.update(timeout_seconds=31),
            lambda d: d.update(order_by=[]),
        ]
        for index, change in enumerate(cases):
            with self.subTest(index=index):
                self.definition = copy.deepcopy(valid)
                change(self.definition)
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["attempts_started"], 0)
                self.assertIsNone(summary["record"])
                self.assertFalse(self.calls.exists())
        self.definition = valid
        for extra in [("--sha256", "0" * 64), ("--limit", "101"), ("--limit", "0"), ("--body", "{}")]:
            with self.subTest(extra=extra):
                status, summary = self.invoke(*extra)
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())
        self.definition["parameters"]["category"]["values"] = ["17", "True", "None"]
        for value in (17, True, None):
            with self.subTest(value=value):
                self.write(self.params, {"category": value})
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())

    def test_parameters_optional(self):
        status, summary = self.invoke(with_params=False)
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["attempts_started"], 0)
        self.assertFalse(self.calls.exists())
        self.definition.update(parameters={}, where=[])
        status, summary = self.invoke(with_params=False)
        self.assertEqual(status, 0)
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(json.loads(self.calls.read_text())["body"]["params"], [])

    def test_storage_failure(self):
        for replacement, attempts in [(1, 0), (2, 0), (3, 1)]:
            with self.subTest(replacement=replacement):
                self.fail_replace = replacement
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["attempts_started"], attempts)
                self.assertEqual(summary["stop_reason"], "record_failed")
                self.assertNotIn("private-storage-error", json.dumps(summary))
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_explain(self):
        plan = {"id": 2, "parent": 0, "notused": 0, "detail": "SCAN fixture_records"}
        self.response["result"][0]["results"] = [plan]
        status, summary = self.invoke("--mode", "explain")
        self.assertEqual(status, 0)
        audit = json.loads(Path(summary["record"]).read_text())
        self.assertEqual(audit["query_plan"], [plan])
        self.assertIsNone(audit["query_plan_reason"])
        self.assertNotIn("SCAN", json.dumps(summary))
        self.assertTrue(json.loads(self.calls.read_text().splitlines()[0])["body"]["sql"].startswith("EXPLAIN QUERY PLAN SELECT"))
        self.response["result"][0]["results"] = []
        status, summary = self.invoke("--mode", "explain")
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "invalid_response")
        self.response["result"][0]["results"] = [plan]
        self.response["result"][0]["results"][0]["id"] = "invalid"
        status, summary = self.invoke("--mode", "explain")
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "invalid_response")
        plan["id"] = 2
        self.response["result"][0]["results"] = [plan, plan]
        status, summary = self.invoke("--mode", "explain", "--limit", "1")
        self.assertEqual(status, 0)
        self.assertEqual(summary["returned_count"], 2)
        self.assertEqual(summary["stop_reason"], "complete")
        self.definition["max_plan_rows"] = 2
        status, summary = self.invoke("--mode", "explain", "--limit", "1")
        self.assertEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "complete")
        audit = json.loads(Path(summary["record"]).read_text())
        self.assertEqual(audit["limit"], 1)
        self.assertEqual(audit["result_limit"], 2)
        self.definition["max_plan_rows"] = 1
        status, summary = self.invoke("--mode", "explain", "--limit", "1")
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "invalid_response")

    def test_limit_and_redaction(self):
        self.response["result"][0]["results"] = [{"state": "DUMMY_CF_TOKEN"}]
        status, summary = self.invoke("--limit", "1")
        self.assertEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "limit_reached_unknown")
        audit = Path(summary["record"]).read_text()
        self.assertNotIn("DUMMY_CF_TOKEN", audit)
        self.assertEqual(json.loads(audit)["results"], [{"state": "[非表示]"}])

    def test_private_boundaries(self):
        for mode in (0o644, 0o400, 0o666):
            with self.subTest(mode=mode):
                self.definition_mode = mode
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "invalid_request")
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())
        self.definition_mode = 0o600
        for raw in (b'{"version":1,"version":1}', b"x" * 65537, b'{"value": NaN}'):
            with self.subTest(raw_size=len(raw)):
                self.definition_raw = raw
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "invalid_request")
                self.assertEqual(summary["attempts_started"], 0)
        self.definition_raw = None
        target = self.root / "symlink-target.json"
        self.write(target, self.definition)
        link = self.root / "link.json"
        link.symlink_to(target)
        hard_link = self.root / "hard.json"
        os.link(target, hard_link)
        parent_link = self.root / "parent-link"
        parent_link.symlink_to(self.root, target_is_directory=True)
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        for path in (link, hard_link, parent_link / "definition.json", fifo):
            with self.subTest(path=path.name):
                started = time.monotonic()
                status, summary = self.invoke("--definition", str(path))
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "invalid_request")
                self.assertLess(time.monotonic() - started, 3)
                self.assertEqual(summary["attempts_started"], 0)
        self.scratch.chmod(0o755)
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "invalid_request")
        self.assertEqual(summary["attempts_started"], 0)
        self.assertEqual(self.scratch.stat().st_mode & 0o777, 0o755)
        self.assertFalse(self.calls.exists())

    def test_unsupported_proxy(self):
        self.real_transport = True
        for key in ("HTTPS_PROXY", "https_proxy", "ALL_PROXY"):
            with self.subTest(variable=key):
                self.environment = {key: "https://DUMMY_PROXY_USER:DUMMY_PROXY_PASS@proxy.invalid:8443", "NO_PROXY": ""}
                status, summary = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["stop_reason"], "transport_configuration")
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())
                record = Path(summary["record"]).read_text()
                self.assertEqual(json.loads(record)["status"], "failed")
                self.assertNotIn("DUMMY_PROXY", record + json.dumps(summary))

    def test_transport_environment(self):
        self.real_transport = True
        keylog = self.root / "keylog"
        self.environment = {"HTTPS_PROXY": "http://proxy.invalid:8080", "NO_PROXY": "",
                            "SSLKEYLOGFILE": str(keylog), "NODE_OPTIONS": "untrusted",
                            "CLOUDFLARE_API_BASE_URL": "https://untrusted.invalid/", "DEBUG": "*"}
        self.expected_proxy = "proxy.invalid:8080"
        status, summary = self.invoke()
        self.assertEqual(status, 0)
        self.assertFalse(keylog.exists())
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.environment["SSL_CERT_FILE"] = str(self.root / "missing-ca.pem")
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "transport_configuration")
        self.assertEqual(summary["attempts_started"], 0)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.environment.pop("SSL_CERT_FILE")
        self.environment["NIX_SSL_CERT_FILE"] = str(self.root / "missing-nix-ca.pem")
        status, summary = self.invoke()
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["stop_reason"], "transport_configuration")
        self.assertEqual(summary["attempts_started"], 0)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
