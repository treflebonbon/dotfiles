"""R2 の公開 CLI 境界を、合成資格情報とローカル HTTP stub で検証する。"""

import base64
from datetime import datetime, timezone
from email.message import Message
import hashlib
from http.client import BadStatusLine, IncompleteRead, LineTooLong
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import time
import unittest
import urllib.request
import urllib.response
from contextlib import nullcontext
from unittest.mock import patch
from urllib.parse import parse_qsl, urlsplit

sys.dont_write_bytecode = True
FIXTURE = Path(sys.argv.pop(1))
SOURCE = Path(__file__).resolve().parents[2] / "private_dot_config/nix-devshell/packages/cloudflare-cli/cloudflare-inspect.py"
spec = importlib.util.spec_from_file_location(
    "cloudflare_inspect", SOURCE,
    loader=importlib.machinery.SourceFileLoader("cloudflare_inspect", str(SOURCE)),
)
assert spec is not None and spec.loader is not None
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

ACCOUNT_ID = "0123456789abcdef0123456789abcdef"
BUCKET = "r2-fixture-bucket"
PREFIX = "reports/"
ACCESS_KEY_ID = "DUMMYR2ACCESSKEY"
FIXED_TIME = 1_800_000_000
FIXED_UTC = datetime.fromtimestamp(FIXED_TIME, timezone.utc)
JWT_HEADER = base64.urlsafe_b64encode(b'{"alg":"HS256","typ":"JWT"}').rstrip(b"=").decode()
JWT_PAYLOAD = base64.urlsafe_b64encode(json.dumps({
    "iss": ACCESS_KEY_ID,
    "sub": ACCOUNT_ID,
    "aud": ACCOUNT_ID + ".r2.cloudflarestorage.com",
    "iat": FIXED_TIME - 10,
    "exp": FIXED_TIME + 300,
    "actions": ["ListObjectsV2"],
    "bucket": BUCKET,
    "paths": {"prefixPaths": [PREFIX], "objectPaths": []},
}, separators=(",", ":")).encode()).rstrip(b"=").decode()
JWT = JWT_HEADER + "." + JWT_PAYLOAD + "." + ("A" * 43)
SECRET_ACCESS_KEY = hashlib.sha256(JWT.encode()).hexdigest()
SESSION_TOKEN = base64.b64encode(("jwt/" + JWT).encode()).decode()
S3_NS = "http://s3.amazonaws.com/doc/2006-03-01/"


def make_credentials(claims=None, *, header=None, header_raw=None, payload_raw=None):
    if header_raw is None:
        header_raw = json.dumps(header or {"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode()
    if payload_raw is None:
        payload_raw = json.dumps(claims or {
            "iss": ACCESS_KEY_ID,
            "sub": ACCOUNT_ID,
            "aud": ACCOUNT_ID + ".r2.cloudflarestorage.com",
            "iat": FIXED_TIME - 10,
            "exp": FIXED_TIME + 300,
            "actions": ["ListObjectsV2"],
            "bucket": BUCKET,
            "paths": {"prefixPaths": [PREFIX], "objectPaths": []},
        }, separators=(",", ":")).encode()
    def enc(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    jwt = enc(header_raw) + "." + enc(payload_raw) + "." + ("A" * 43)
    return {
        "CLOUDFLARE_R2_ACCESS_KEY_ID": ACCESS_KEY_ID,
        "CLOUDFLARE_R2_SECRET_ACCESS_KEY": hashlib.sha256(jwt.encode()).hexdigest(),
        "CLOUDFLARE_R2_SESSION_TOKEN": base64.b64encode(("jwt/" + jwt).encode()).decode(),
    }


class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
        return cls.fromtimestamp(FIXED_TIME, tz or timezone.utc)


class FixtureResponse(urllib.response.addinfourl):
    msg = "Fixture"


def xml_page(*, bucket=BUCKET, prefix=PREFIX, max_keys=12, key="reports%2Fannual%20report.csv",
             size="4", etag='"d41d8cd98f"', last_modified="2026-11-07T12:00:00.000Z",
             truncated="false", next_token=None, key_count=None, extra="", object_extra="",
             include_content=True, namespace=S3_NS):
    continuation = f"<NextContinuationToken>{next_token}</NextContinuationToken>" if next_token is not None else ""
    count = (1 if include_content else 0) if key_count is None else key_count
    contents = (f'<Contents><Key>{key}</Key><LastModified>{last_modified}</LastModified>'
                f'<ETag>{etag}</ETag><Size>{size}</Size><StorageClass>STANDARD</StorageClass>{object_extra}</Contents>' if include_content else "")
    return (f'<ListBucketResult xmlns="{namespace}"><Name>{bucket}</Name><Prefix>{prefix.replace("/", "%2F")}</Prefix>'
            f'<KeyCount>{count}</KeyCount><MaxKeys>{max_keys}</MaxKeys><IsTruncated>{truncated}</IsTruncated>'
            f'<EncodingType>url</EncodingType>{contents}'
            f'{continuation}{extra}</ListBucketResult>').encode()


class R2(unittest.TestCase):
    def setUp(self):
        self.root = FIXTURE / self.id().split(".")[-1]
        self.root.mkdir(mode=0o700)
        self.scratch = self.root / "scratch"
        self.scratch.mkdir(mode=0o700)
        self.definition = {
            "version": 1,
            "account_id": ACCOUNT_ID,
            "bucket": BUCKET,
            "prefix": PREFIX,
            "jurisdiction": "default",
            "fields": ["key", "size"],
            "max_keys": 12,
            "timeout_seconds": 10,
            "max_credential_remaining_seconds": 300,
        }
        self.file = self.root / "definition.json"
        self.calls = self.root / "http.json"
        self.attempts = self.root / "attempts.txt"
        self.exchange_status = 200
        self.exchange_body = xml_page()
        self.exchange_headers = {"content-type": "application/xml", "content-encoding": "identity"}
        self.request_delay = 0
        self.http_exception = None
        self.expected_proxy = None
        self.expected_environment = {}
        self.environment = {}
        self.definition_mode = 0o600

    def write(self, value):
        if self.file.exists():
            self.file.chmod(0o600)
        self.file.write_text(json.dumps(value, separators=(",", ":")))
        self.file.chmod(self.definition_mode)

    def clear_calls(self):
        self.calls.unlink(missing_ok=True)
        self.attempts.unlink(missing_ok=True)

    def record_call(self, request, timeout):
        headers = {key.lower(): value for key, value in request.header_items()}
        authorization = headers.get("authorization", "")
        call = {
            "url": request.full_url,
            "method": request.get_method(),
            "headers": {
                "accept-encoding": headers.get("accept-encoding"),
                "authorization_algorithm": authorization.split(" ", 1)[0] if authorization else None,
                "credential_scope": authorization.split("Credential=", 1)[1].split("/", 1)[1].split(",", 1)[0] if "Credential=" in authorization else None,
                "signed_headers": authorization.split("SignedHeaders=", 1)[1].split(",", 1)[0] if "SignedHeaders=" in authorization else None,
                "signature": authorization.split("Signature=", 1)[1] if "Signature=" in authorization else None,
                "x-amz-content-sha256": headers.get("x-amz-content-sha256"),
                "x-amz-date": headers.get("x-amz-date"),
                "session_token_present": headers.get("x-amz-security-token") == SESSION_TOKEN,
            },
            "body": request.data,
            "timeout": timeout,
            "environment": sorted(os.environ),
            "preserved_environment_matches": {
                key: os.environ.get(key) == value for key, value in self.expected_environment.items()
            },
        }
        self.calls.write_text(json.dumps(call))
        with self.attempts.open("a") as output:
            output.write("attempt\n")

    def https_open(self, handler, request):
        if self.expected_proxy is not None:
            self.assertEqual(request.host, self.expected_proxy)
        self.record_call(request, None)
        time.sleep(self.request_delay)
        if self.http_exception is not None:
            raise self.http_exception
        headers = Message()
        for key, value in self.exchange_headers.items():
            headers[key] = value
        if self.exchange_status == 302:
            headers["Location"] = "https://untrusted.invalid/"
        return FixtureResponse(io.BytesIO(self.exchange_body), headers, request.full_url, self.exchange_status)

    def invoke(self, *extra, raw=None, environment=None, exchange=None, real_transport=False, definition_path=None,
               fake_opener=False):
        self.write(self.definition)
        if raw is not None:
            self.file.write_bytes(raw)
            self.file.chmod(self.definition_mode)
        expected = hashlib.sha256(self.file.read_bytes()).hexdigest()
        path = definition_path or self.file

        def record_exchange(opener, request, timeout):
            self.record_call(request, timeout)
            time.sleep(self.request_delay)
            if exchange is not None:
                return exchange(opener, request, timeout)
            return self.exchange_status, self.exchange_body, self.exchange_headers

        env = {
            "CLOUDFLARE_R2_ACCESS_KEY_ID": ACCESS_KEY_ID,
            "CLOUDFLARE_R2_SECRET_ACCESS_KEY": SECRET_ACCESS_KEY,
            "CLOUDFLARE_R2_SESSION_TOKEN": SESSION_TOKEN,
            "CLOUDFLARE_API_TOKEN": "DUMMY_PARENT_CLOUDFLARE_TOKEN",
            "CLOUDFLARE_ACCOUNT_ID": "fedcba9876543210fedcba9876543210",
            "AWS_ACCESS_KEY_ID": "DUMMY_AWS_ACCESS_KEY",
            "AWS_SECRET_ACCESS_KEY": "DUMMY_AWS_SECRET",
            "AWS_SESSION_TOKEN": "DUMMY_AWS_SESSION",
            "SSLKEYLOGFILE": str(self.root / "keylog"),
            "CLOUDFLARE_API_BASE_URL": "https://untrusted.invalid/",
            "DEBUG": "*",
            **self.environment,
            **(environment or {}),
        }
        output = []
        exchange_patch = nullcontext() if real_transport else patch.object(helper, "r2_exchange", record_exchange)
        open_patch = patch.object(urllib.request.HTTPSHandler, "https_open",
                                  lambda handler, request: self.https_open(handler, request)) if real_transport else nullcontext()
        opener_patch = patch.object(helper, "d1_opener", lambda: object()) if fake_opener else nullcontext()
        with patch.dict(os.environ, env, clear=True), \
                patch.object(helper, "D1_SCRATCH", self.scratch, create=True), \
                exchange_patch, open_patch, opener_patch, \
                patch.object(helper, "datetime", FrozenDateTime), \
                patch.object(helper.time, "time", lambda: FIXED_TIME), \
                patch("sys.stdout.write", side_effect=lambda value: output.append(value)):
            try:
                status = helper.main(["--reviewed", "r2", "objects", "list", "--definition", str(path),
                                      "--sha256", expected, *extra])
            except ValueError as error:
                status = 2
                output.append(str(error))
        return status, "".join(output)

    def test_fixed_request_and_projection(self):
        status, output = self.invoke()
        self.assertEqual(status, 0, output)
        summary = json.loads(output)
        self.assertEqual(set(summary), {"status", "returned_count", "attempts_started", "end_reason", "record_locator"})
        self.assertEqual(summary["status"], "complete")
        self.assertEqual(summary["returned_count"], 1)
        self.assertEqual(summary["attempts_started"], 1)
        self.assertEqual(summary["end_reason"], "complete")
        for private_value in (ACCOUNT_ID, BUCKET, PREFIX, "annual report.csv", ACCESS_KEY_ID, SECRET_ACCESS_KEY, SESSION_TOKEN, JWT):
            self.assertNotIn(private_value, output)

        call = json.loads(self.calls.read_text())
        parsed = urlsplit(call["url"])
        self.assertEqual(call["method"], "GET")
        self.assertEqual(parsed.scheme, "https")
        self.assertEqual(parsed.netloc, ACCOUNT_ID + ".r2.cloudflarestorage.com")
        self.assertEqual(parsed.path, "/" + BUCKET)
        self.assertEqual(parsed.query, "encoding-type=url&list-type=2&max-keys=12&prefix=reports%2F")
        self.assertEqual(parse_qsl(parsed.query), [
            ("encoding-type", "url"), ("list-type", "2"), ("max-keys", "12"), ("prefix", PREFIX),
        ])
        self.assertIsNone(call["body"])
        self.assertEqual(call["headers"]["accept-encoding"], "identity")
        self.assertEqual(call["headers"]["x-amz-content-sha256"], hashlib.sha256(b"").hexdigest())
        self.assertEqual(call["headers"]["signed_headers"], "host;x-amz-content-sha256;x-amz-date;x-amz-security-token")
        self.assertTrue(call["headers"]["session_token_present"])
        self.assertEqual(call["headers"]["authorization_algorithm"], "AWS4-HMAC-SHA256")
        self.assertEqual(call["headers"]["credential_scope"], FIXED_UTC.strftime("%Y%m%d") + "/auto/s3/aws4_request")
        self.assertEqual(call["headers"]["signature"], "ce98c812d6eebf527c81f09b4a386e2f59fc1b2149dfa203d25ef0841b8b9e1d")
        self.assertEqual(call["headers"]["x-amz-date"], FIXED_UTC.strftime("%Y%m%dT%H%M%SZ"))
        self.assertEqual(call["environment"], sorted([
            "CLOUDFLARE_R2_ACCESS_KEY_ID", "CLOUDFLARE_R2_SECRET_ACCESS_KEY", "CLOUDFLARE_R2_SESSION_TOKEN",
        ]))
        self.assertFalse((self.root / "keylog").exists())

        record = Path(summary["record_locator"])
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.assertEqual(record.parent.stat().st_mode & 0o777, 0o700)
        audit = record.read_text()
        for secret in (ACCESS_KEY_ID, SECRET_ACCESS_KEY, SESSION_TOKEN, JWT, "NextToken-SENSITIVE", "<ListBucketResult"):
            self.assertNotIn(secret, audit)
        value = json.loads(audit)
        self.assertEqual(value["items"], [{"key": "reports/annual report.csv", "size": 4}])
        self.assertEqual(set(value["items"][0]), set(self.definition["fields"]))
        self.assertEqual(value["status"], "complete")
        self.assertEqual(value["attempts_started"], 1)

    def test_child_environment_keeps_only_r2_credentials_proxy_ca_and_locale(self):
        self.expected_environment = {name: "DUMMY_" + name for name in helper.R2_TRANSPORT_ENV}
        self.environment = {
            **self.expected_environment,
            "CLOUDFLARE_API_TOKEN": "DUMMY_PARENT_CLOUDFLARE_TOKEN",
            "CLOUDFLARE_ACCOUNT_ID": "fedcba9876543210fedcba9876543210",
            "AWS_ACCESS_KEY_ID": "DUMMY_AWS_ACCESS_KEY",
            "AWS_SECRET_ACCESS_KEY": "DUMMY_AWS_SECRET",
            "AWS_SESSION_TOKEN": "DUMMY_AWS_SESSION",
            "SSLKEYLOGFILE": str(self.root / "keylog"),
            "CLOUDFLARE_API_BASE_URL": "https://untrusted.invalid/",
            "DEBUG": "*",
        }
        status, output = self.invoke(fake_opener=True)
        self.assertEqual(status, 0, output)
        call = json.loads(self.calls.read_text())
        self.assertEqual(call["environment"], sorted([*helper.R2_CREDENTIAL_ENV, *helper.R2_TRANSPORT_ENV]))
        self.assertEqual(call["preserved_environment_matches"], {name: True for name in helper.R2_TRANSPORT_ENV})
        self.assertFalse((self.root / "keylog").exists())

    def test_official_empty_or_omitted_object_paths_and_rejects_credential_mismatch_before_http(self):
        claims = {
            "iss": ACCESS_KEY_ID,
            "sub": ACCOUNT_ID,
            "aud": ACCOUNT_ID + ".r2.cloudflarestorage.com",
            "iat": FIXED_TIME - 10,
            "exp": FIXED_TIME + 300,
            "actions": ["ListObjectsV2"],
            "bucket": BUCKET,
            "paths": {"prefixPaths": [PREFIX], "objectPaths": []},
        }
        self.clear_calls()
        status, output = self.invoke(environment=make_credentials(claims))
        self.assertEqual(status, 0, output)
        self.assertEqual(json.loads(output)["attempts_started"], 1)

        cases = []
        omitted = json.loads(json.dumps(claims))
        omitted["paths"].pop("objectPaths")
        self.clear_calls()
        status, output = self.invoke(environment=make_credentials(omitted))
        self.assertEqual(status, 0, output)
        self.assertEqual(json.loads(output)["attempts_started"], 1)
        invalid = json.loads(json.dumps(claims))
        invalid["paths"]["objectPaths"] = ["reports/private.csv"]
        cases.append(("nonempty objectPaths", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["actions"] = ["GetObject"]
        cases.append(("wrong actions", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["scope"] = "object-read-only"
        cases.append(("unknown scope", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["paths"]["other"] = []
        cases.append(("unknown paths key", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["paths"]["prefixPaths"] = ["reports/other/"]
        cases.append(("prefix mismatch", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["bucket"] = "other-bucket"
        cases.append(("bucket mismatch", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["aud"] = "untrusted.invalid"
        cases.append(("audience mismatch", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["iat"] = True
        cases.append(("boolean iat", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["iat"] = FIXED_TIME + 61
        cases.append(("future iat", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["iat"] = FIXED_TIME + 30
        invalid["exp"] = FIXED_TIME + 30
        cases.append(("iat not before exp", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["exp"] = FIXED_TIME
        cases.append(("expired credential", make_credentials(invalid)))
        invalid = json.loads(json.dumps(claims))
        invalid["exp"] = FIXED_TIME + 301
        cases.append(("remaining lifetime exceeds definition", make_credentials(invalid)))
        cases.append(("header algorithm", make_credentials(claims, header={"alg": "HS512", "typ": "JWT"})))
        cases.append(("duplicate header JSON key", make_credentials(header_raw=b'{"alg":"HS256","alg":"HS256","typ":"JWT"}')))
        duplicate = b'{"iss":"DUMMYR2ACCESSKEY","iss":"DUMMYR2ACCESSKEY","sub":"' + ACCOUNT_ID.encode() + b'","aud":"' + (ACCOUNT_ID + ".r2.cloudflarestorage.com").encode() + b'","iat":1799999990,"exp":1800000300,"actions":["ListObjectsV2"],"bucket":"' + BUCKET.encode() + b'","paths":{"prefixPaths":["reports/"],"objectPaths":[]}}'
        cases.append(("duplicate JSON key", make_credentials(payload_raw=duplicate)))
        nonfinite = json.dumps(claims, separators=(",", ":")).replace('"iat":1799999990', '"iat":NaN').encode()
        cases.append(("nonfinite JSON value", make_credentials(payload_raw=nonfinite)))
        cases.append(("secret mismatch", {**make_credentials(claims), "CLOUDFLARE_R2_SECRET_ACCESS_KEY": "DUMMY_WRONG_SECRET"}))
        cases.append(("access key header delimiter", {**make_credentials(claims), "CLOUDFLARE_R2_ACCESS_KEY_ID": "DUMMY/R2KEY"}))
        cases.append(("malformed session token", {**make_credentials(claims), "CLOUDFLARE_R2_SESSION_TOKEN": "not-base64"}))
        cases.append(("oversized JWT", {**make_credentials(claims), "CLOUDFLARE_R2_SESSION_TOKEN": base64.b64encode(("jwt/" + "A" * 8200).encode()).decode()}))
        cases.append(("oversized session token", {**make_credentials(claims), "CLOUDFLARE_R2_SESSION_TOKEN": "A" * (16 * 1024 + 1)}))

        for name, credentials in cases:
            with self.subTest(name=name):
                self.clear_calls()
                status, output = self.invoke(environment=credentials)
                summary = json.loads(output)
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["status"], "failed")
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())

    def test_credential_values_are_redacted_before_and_after_scope_validation(self):
        original_write = helper.D1Record.write
        for name, prefix_part in (
            ("access key ID", ACCESS_KEY_ID),
            ("secret access key", SECRET_ACCESS_KEY),
            ("session token", SESSION_TOKEN),
            ("parsed JWT", JWT),
        ):
            with self.subTest(value=name):
                self.definition["prefix"] = prefix_part + "/"
                self.clear_calls()
                write_log = self.root / "record-writes.jsonl"
                write_log.unlink(missing_ok=True)
                credential_values = (
                    ("access key ID", ACCESS_KEY_ID), ("secret access key", SECRET_ACCESS_KEY),
                    ("session token", SESSION_TOKEN), ("parsed JWT", JWT),
                )

                def capture_write(record, value):
                    encoded = json.dumps(value, ensure_ascii=False)
                    leaked_names = [name for name, credential in credential_values if credential in encoded]
                    with write_log.open("a") as output:
                        output.write(json.dumps(leaked_names) + "\n")
                    return original_write(record, value)

                with patch.object(helper.D1Record, "write", capture_write):
                    status, output = self.invoke()

                summary = json.loads(output)
                self.assertNotEqual(status, 0)
                self.assertEqual((summary["end_reason"], summary["attempts_started"]),
                                 ("credential_validation", 0))
                captured_writes = write_log.read_text().splitlines()
                write_log.unlink()
                self.assertEqual(len(captured_writes), 2)
                self.assertEqual([json.loads(line) for line in captured_writes], [[], []])
                stored = output + Path(summary["record_locator"]).read_text()
                for credential_name, credential in credential_values:
                    self.assertFalse(credential in stored, f"{credential_name} was stored")
                self.assertFalse(self.calls.exists())

    def test_definition_hash_shape_and_bounds_fail_before_http(self):
        valid = json.loads(json.dumps(self.definition))
        cases = [
            ("wrong version", lambda value: value.update(version=True)),
            ("uppercase account", lambda value: value.update(account_id=ACCOUNT_ID.upper())),
            ("invalid bucket", lambda value: value.update(bucket="Bad_Bucket")),
            ("empty prefix", lambda value: value.update(prefix="")),
            ("unterminated prefix", lambda value: value.update(prefix="reports")),
            ("nondefault jurisdiction", lambda value: value.update(jurisdiction="eu")),
            ("empty fields", lambda value: value.update(fields=[])),
            ("duplicate fields", lambda value: value.update(fields=["key", "key"])),
            ("unknown field", lambda value: value.update(fields=["metadata"])),
            ("invalid max_keys", lambda value: value.update(max_keys=1001)),
            ("boolean timeout", lambda value: value.update(timeout_seconds=True)),
            ("remaining credential limit", lambda value: value.update(max_credential_remaining_seconds=901)),
            ("unknown definition key", lambda value: value.update(endpoint="https://untrusted.invalid")),
        ]
        for name, mutate in cases:
            with self.subTest(name=name):
                self.clear_calls()
                self.definition = json.loads(json.dumps(valid))
                mutate(self.definition)
                status, output = self.invoke()
                summary = json.loads(output)
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["attempts_started"], 0)
                self.assertFalse(self.calls.exists())

        self.definition = json.loads(json.dumps(valid))
        for extra in (("--sha256", "0" * 64), ("--limit", "0"), ("--limit", "13"), ("--endpoint", "https://untrusted.invalid")):
            with self.subTest(extra=extra):
                self.clear_calls()
                status, output = self.invoke(*extra)
                self.assertNotEqual(status, 0)
                if output.startswith("{"):
                    self.assertEqual(json.loads(output)["attempts_started"], 0)
                self.assertFalse(self.calls.exists())

    def test_private_definition_file_boundaries(self):
        for mode in (0o644, 0o400, 0o666):
            with self.subTest(mode=oct(mode)):
                self.definition_mode = mode
                self.clear_calls()
                status, output = self.invoke()
                self.assertNotEqual(status, 0)
                self.assertEqual(json.loads(output)["attempts_started"], 0)
                self.assertFalse(self.calls.exists())
        self.definition_mode = 0o600

        for raw in (
            b'{"version":1,"version":1}',
            b'{"version":1,"value":NaN}',
            b" " * (64 * 1024 + 1),
        ):
            with self.subTest(raw_size=len(raw)):
                self.clear_calls()
                status, output = self.invoke(raw=raw)
                self.assertNotEqual(status, 0)
                self.assertEqual(json.loads(output)["attempts_started"], 0)
                self.assertFalse(self.calls.exists())

        link = self.root / "definition-link.json"
        link.symlink_to(self.file)
        hard_link = self.root / "definition-hard-link.json"
        os.link(self.file, hard_link)
        parent_link = self.root / "definition-parent-link"
        parent_link.symlink_to(self.root, target_is_directory=True)
        for path in (link, hard_link, parent_link / self.file.name):
            with self.subTest(path=path.name):
                self.clear_calls()
                status, output = self.invoke(definition_path=path)
                self.assertNotEqual(status, 0)
                self.assertEqual(json.loads(output)["attempts_started"], 0)
                self.assertFalse(self.calls.exists())
        self.assertEqual(self.file.stat().st_nlink, 2)

    def test_empty_and_truncated_pages_do_not_store_continuation_tokens(self):
        self.exchange_body = xml_page(include_content=False)
        status, output = self.invoke()
        self.assertEqual(status, 0, output)
        summary = json.loads(output)
        self.assertEqual((summary["status"], summary["returned_count"], summary["end_reason"]), ("complete", 0, "complete"))
        self.assertEqual(json.loads(Path(summary["record_locator"]).read_text())["items"], [])

        self.exchange_body = xml_page(truncated="true", next_token="NextToken-SENSITIVE")
        self.clear_calls()
        status, output = self.invoke()
        self.assertEqual(status, 0, output)
        summary = json.loads(output)
        self.assertEqual((summary["status"], summary["returned_count"], summary["end_reason"]), ("truncated", 1, "truncated"))
        call = json.loads(self.calls.read_text())
        self.assertNotIn("continuation-token", call["url"])
        record = Path(summary["record_locator"]).read_text()
        self.assertNotIn("NextToken-SENSITIVE", output + record)
        self.assertNotIn("NextToken-SENSITIVE", call["url"])

    def test_invalid_xml_transport_encoding_and_metadata_never_store_items(self):
        valid = xml_page()
        malformed = valid.replace(b"</ListBucketResult>", b"", 1)
        cases = [
            ("malformed XML", malformed, {"content-type": "application/xml", "content-encoding": "identity"}),
            ("DOCTYPE and entity", b'<!DOCTYPE ListBucketResult [<!ENTITY x "hidden">]>' + valid,
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("unknown namespace", xml_page(namespace="urn:untrusted"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("unknown element", xml_page(extra=f"<Owner xmlns=\"{S3_NS}\">private</Owner>"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("common prefix", xml_page(extra=f"<CommonPrefixes xmlns=\"{S3_NS}\"><Prefix>reports%2Fchild%2F</Prefix></CommonPrefixes>"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("bucket mismatch", xml_page(bucket="other-bucket"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("prefix mismatch", xml_page(prefix="other/"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("key outside prefix", xml_page(key="other%2Fprivate.csv"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("bad percent encoding", xml_page(key="reports%2Fbad%ZZ"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("negative size", xml_page(size="-1"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("invalid timestamp", xml_page(last_modified="not-a-date"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("mismatched key count", xml_page(key_count=2),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("mismatched max keys", xml_page(max_keys=13),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("truncated without token", xml_page(truncated="true"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("token when complete", xml_page(next_token="NextToken-SENSITIVE"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("unknown object element", xml_page(object_extra="<Unapproved>private</Unapproved>"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("BOMless UTF-16LE with DOCTYPE and entity",
             ('<?xml version="1.0" encoding="UTF-16LE"?>'
              '<!DOCTYPE ListBucketResult [<!ENTITY entity_size "4">]>'
              + xml_page().decode().replace("<Size>4</Size>", "<Size>&entity_size;</Size>")).encode("utf-16-le"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("BOMless UTF-16BE with DOCTYPE and entity",
             ('<?xml version="1.0" encoding="UTF-16BE"?>'
              '<!DOCTYPE ListBucketResult [<!ENTITY entity_size "4">]>'
              + xml_page().decode().replace("<Size>4</Size>", "<Size>&entity_size;</Size>")).encode("utf-16-be"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("non-UTF8 XML", xml_page().decode().encode("utf-16"),
             {"content-type": "application/xml", "content-encoding": "identity"}),
            ("compressed response", valid,
             {"content-type": "application/xml", "content-encoding": "gzip"}),
            ("wrong content type", valid,
             {"content-type": "application/json", "content-encoding": "identity"}),
        ]
        for name, raw, headers in cases:
            with self.subTest(name=name):
                self.clear_calls()
                self.exchange_body = raw
                self.exchange_headers = headers
                status, output = self.invoke()
                summary = json.loads(output)
                self.assertNotEqual(status, 0)
                self.assertEqual(summary["status"], "failed")
                self.assertEqual(summary["attempts_started"], 1)
                self.assertIsNone(summary["returned_count"])
                record = json.loads(Path(summary["record_locator"]).read_text())
                self.assertNotIn("items", record)
                self.assertNotIn(raw.decode("utf-8", "replace"), json.dumps(record))
        self.exchange_headers = {"content-type": "application/xml", "content-encoding": "identity"}

        self.clear_calls()
        self.exchange_body = b"x" * (8 * 1024 * 1024 + 1)
        status, output = self.invoke()
        summary = json.loads(output)
        self.assertNotEqual(status, 0)
        self.assertEqual(summary["attempts_started"], 1)
        self.assertNotIn("items", json.loads(Path(summary["record_locator"]).read_text()))

    def test_unknown_xml_encoding_preserves_attempt_and_classifies_http_error(self):
        self.exchange_body = b'<?xml version="1.0" encoding="made-up"?>' + xml_page()
        status, output = self.invoke()
        summary = json.loads(output)
        with self.subTest(response="success"):
            self.assertNotEqual(status, 0)
            self.assertEqual((summary["status"], summary["end_reason"], summary["attempts_started"]),
                             ("failed", "invalid_response", 1))
            self.assertIsNotNone(summary["record_locator"])
            record = json.loads(Path(summary["record_locator"]).read_text())
            self.assertNotIn("items", record)
            self.assertNotIn("made-up", output + json.dumps(record))

        self.exchange_status = 503
        self.exchange_body = (b'<?xml version="1.0" encoding="made-up"?>'
                              b'<Error><Code>AccessDenied</Code><Message>PRIVATE_ERROR_BODY</Message></Error>')
        status, output = self.invoke()
        summary = json.loads(output)
        with self.subTest(response="HTTP error"):
            self.assertNotEqual(status, 0)
            self.assertEqual((summary["status"], summary["end_reason"], summary["attempts_started"]),
                             ("failed", "http_error", 1))
            self.assertIsNotNone(summary["record_locator"])
            record = json.loads(Path(summary["record_locator"]).read_text())
            self.assertEqual((record["http_status"], record["service_error_code"]), (503, "unknown"))
            self.assertNotIn("PRIVATE_ERROR_BODY", output + json.dumps(record))
            self.assertNotIn("made-up", output + json.dumps(record))

    def test_real_transport_stub_never_redirects_retries_or_leaks_error_bodies(self):
        self.exchange_status = 302
        self.exchange_body = b'<Error><Code>PermanentRedirect</Code><Message>PRIVATE_REDIRECT_BODY</Message></Error>'
        self.clear_calls()
        status, output = self.invoke(real_transport=True)
        summary = json.loads(output)
        self.assertNotEqual(status, 0)
        self.assertEqual((summary["status"], summary["attempts_started"], summary["end_reason"]),
                         ("failed", 1, "http_error"))
        self.assertEqual(len(self.attempts.read_text().splitlines()), 1)
        self.assertNotIn("PRIVATE_REDIRECT_BODY", output + Path(summary["record_locator"]).read_text())
        self.assertEqual(json.loads(Path(summary["record_locator"]).read_text())["service_error_code"], "PermanentRedirect")

        self.exchange_status = 503
        self.exchange_body = b'<Error><Code>AccessDenied</Code><Message>DUMMY_PARENT_CLOUDFLARE_TOKEN SECRET_ERROR_BODY</Message></Error>'
        self.clear_calls()
        status, output = self.invoke(real_transport=True)
        summary = json.loads(output)
        audit = json.loads(Path(summary["record_locator"]).read_text())
        self.assertNotEqual(status, 0)
        self.assertEqual((audit["http_status"], audit["service_error_code"], audit["attempts_started"]), (503, "AccessDenied", 1))
        self.assertNotIn("SECRET_ERROR_BODY", output + json.dumps(audit))
        self.assertNotIn("DUMMY_PARENT_CLOUDFLARE_TOKEN", output + json.dumps(audit))
        self.assertEqual(len(self.attempts.read_text().splitlines()), 1)

        self.exchange_status = 407
        self.exchange_body = b'<Error><Code>UnknownPrivateError</Code><Message>SECRET_ERROR_BODY</Message></Error>'
        self.environment = {"HTTPS_PROXY": "http://DUMMY_PROXY_USER:DUMMY_PROXY_PASS@proxy.invalid:8080", "NO_PROXY": ""}
        self.expected_proxy = "proxy.invalid:8080"
        self.clear_calls()
        status, output = self.invoke(real_transport=True)
        summary = json.loads(output)
        audit = json.loads(Path(summary["record_locator"]).read_text())
        self.assertNotEqual(status, 0)
        self.assertEqual(audit["service_error_code"], "unknown")
        self.assertNotIn("DUMMY_PROXY", output + json.dumps(audit))
        self.assertNotIn("SECRET_ERROR_BODY", output + json.dumps(audit))
        self.assertEqual(len(self.attempts.read_text().splitlines()), 1)

        self.environment = {}
        self.expected_proxy = None
        for error in (IncompleteRead(b"PRIVATE_DISCONNECT"), BadStatusLine("PRIVATE_STATUS_LINE"),
                      LineTooLong("PRIVATE_LONG_STATUS_LINE")):
            with self.subTest(error=type(error).__name__):
                self.http_exception = error
                self.clear_calls()
                status, output = self.invoke(real_transport=True)
                summary = json.loads(output)
                audit = json.loads(Path(summary["record_locator"]).read_text())
                self.assertNotEqual(status, 0)
                self.assertEqual((summary["attempts_started"], summary["end_reason"]), (1, "request_failed"))
                self.assertNotIn("PRIVATE_", output + json.dumps(audit))
                self.assertEqual(len(self.attempts.read_text().splitlines()), 1)
        self.http_exception = None

    def test_deadline_kills_local_stub_and_leaves_pending_attempt_record(self):
        self.definition["timeout_seconds"] = 1
        self.request_delay = 5
        started = time.monotonic()
        status, output = self.invoke()
        summary = json.loads(output)
        self.assertNotEqual(status, 0)
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual((summary["end_reason"], summary["attempts_started"]), ("deadline_exceeded", 1))
        audit = json.loads(Path(summary["record_locator"]).read_text())
        self.assertEqual((audit["status"], audit["attempts_started"], audit["end_reason"]),
                         ("pending", 1, "interrupted_or_deadline"))
        self.assertEqual(len(self.attempts.read_text().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
