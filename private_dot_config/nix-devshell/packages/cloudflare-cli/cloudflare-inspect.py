#!/usr/bin/env -S python3 -I

"""Cloudflare の確認済み参照操作だけを、機密項目を除外して返す。"""

import argparse
import base64
import binascii
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
from http.client import HTTPException
import json
import math
import multiprocessing
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from urllib.error import HTTPError
from urllib.parse import quote, unquote_to_bytes, urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, ProxyHandler, Request, build_opener, getproxies_environment


VERSION = "1.0.0-beta.25"
OPERATIONS = {
    ("d1", "list"): ("page", "per-page", "name"),
    ("durable-objects", "namespaces", "list"): ("page", "per-page"),
    ("r2", "buckets", "list"): ("per-page", "name-contains", "start-after", "cursor", "order", "direction", "cf-r2-jurisdiction"),
    ("workers", "scripts", "search"): ("page", "per-page", "name", "id", "order-by"),
}
REVIEWED = {("d1", "get"): ("fields",)}
R2_LIST = ("r2", "objects", "list")
SEARCH_TERMS = ("durable objects namespaces", "d1 databases", "r2 buckets", "workers scripts")
LOG_QUERY = ("o11y", "telemetry", "query")
D1_SCRATCH = Path("/tmp/codex")
D1_MAX_JSON = 65536
D1_MAX_RESPONSE = 8 * 1024 * 1024
R2_MAX_JWT = 8192
R2_MAX_SESSION_TOKEN = 16384
R2_MAX_RESPONSE = 8 * 1024 * 1024
R2_NAMESPACE = "http://s3.amazonaws.com/doc/2006-03-01/"
R2_CREDENTIAL_ENV = ("CLOUDFLARE_R2_ACCESS_KEY_ID", "CLOUDFLARE_R2_SECRET_ACCESS_KEY", "CLOUDFLARE_R2_SESSION_TOKEN")
R2_TRANSPORT_ENV = ("LANG", "LC_ALL", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                    "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
                    "NIX_SSL_CERT_FILE")
R2_ERROR_CODES = frozenset({
    "AccessDenied", "AuthorizationHeaderMalformed", "ExpiredToken", "InvalidAccessKeyId", "InvalidArgument",
    "InvalidToken", "NoSuchBucket", "RequestTimeout", "SignatureDoesNotMatch", "SlowDown", "ServiceUnavailable",
    "InternalError", "PermanentRedirect",
})


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("重複した JSON 項目です。")
            result[key] = value
        return result

    def invalid_constant(value):
        raise ValueError("有限の JSON 値が必要です。")

    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_constant)


def private_directory(path):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("絶対 path の通常 directory が必要です。")
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def private_bytes(path):
    path = Path(path)
    parent = private_directory(path.parent)
    try:
        descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    finally:
        os.close(parent)
    with os.fdopen(descriptor, "rb") as source:
        metadata = os.fstat(source.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1):
            raise ValueError("本人所有・mode0600 の通常ファイルが必要です。")
        raw = source.read(D1_MAX_JSON + 1)
    if len(raw) > D1_MAX_JSON:
        raise ValueError("定義または引数が大きすぎます。")
    return raw


def require_exact_keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise ValueError("定義の項目が不正です。")


def identifier(value):
    if (not isinstance(value, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}", value)
            or value.lower().startswith(("sqlite_", "_cf_"))):
        raise ValueError("許可された識別子が必要です。")
    return "[" + value + "]"


def d1_plan(options, account):
    raw = private_bytes(options.definition)
    if not re.fullmatch(r"[a-f0-9]{64}", options.sha256) or hashlib.sha256(raw).hexdigest() != options.sha256:
        raise ValueError("確認済み定義の hash と一致しません。")
    definition = strict_json(raw)
    require_exact_keys(definition, ("version", "account_id", "database_id", "table", "allowed_columns", "select",
                      "where", "order_by", "parameters", "max_rows", "max_plan_rows", "timeout_seconds"))
    if type(definition["version"]) is not int or definition["version"] != 1:
        raise ValueError("未対応の定義です。")
    if not isinstance(account, str) or not re.fullmatch(r"[a-fA-F0-9]{32}", account) or definition["account_id"] != account:
        raise ValueError("対象 account が一致しません。")
    database = definition["database_id"]
    if not isinstance(database, str) or not re.fullmatch(r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", database):
        raise ValueError("対象 database が不正です。")
    for name in ("allowed_columns", "select"):
        columns = definition[name]
        if not isinstance(columns, list) or not 1 <= len(columns) <= 32:
            raise ValueError("許可列が不正です。")
        for column in columns:
            identifier(column)
        if len(set(columns)) != len(columns):
            raise ValueError("列が重複しています。")
    allowed = set(definition["allowed_columns"])
    if not set(definition["select"]) <= allowed:
        raise ValueError("許可外の投影列です。")
    for name, maximum in (("max_rows", 1000), ("max_plan_rows", 1000), ("timeout_seconds", 30)):
        if type(definition[name]) is not int or not 1 <= definition[name] <= maximum:
            raise ValueError("件数または期限の上限が不正です。")
    limit = options.limit if options.limit is not None else min(100, definition["max_rows"])
    if not 1 <= limit <= definition["max_rows"]:
        raise ValueError("許可外の取得件数です。")
    parameters = definition["parameters"]
    values = strict_json(private_bytes(options.params_file)) if options.params_file else {}
    if not isinstance(parameters, dict) or len(parameters) > 16:
        raise ValueError("引数定義が不正です。")
    require_exact_keys(values, parameters)
    for name, rule in parameters.items():
        identifier(name)
        require_exact_keys(rule, ("type", "max_length", "values"))
        if (rule["type"] != "string" or type(rule["max_length"]) is not int or not 1 <= rule["max_length"] <= 4096
                or not isinstance(rule["values"], list) or not rule["values"] or len(rule["values"]) > 256):
            raise ValueError("文字列引数の型・許可値が不正です。")
        for value in rule["values"]:
            if not isinstance(value, str) or len(value) > rule["max_length"] or any(ord(c) < 32 for c in value):
                raise ValueError("文字列引数の許可値が不正です。")
        if not isinstance(values[name], str) or values[name] not in rule["values"]:
            raise ValueError("許可外の引数値です。")
    where, order, bound, used = [], [], [], set()
    for collection, minimum in (("where", 0), ("order_by", 1)):
        if not isinstance(definition[collection], list) or not minimum <= len(definition[collection]) <= 16:
            raise ValueError("条件または並び順が不正です。")
    for condition in definition["where"]:
        require_exact_keys(condition, ("column", "operator", "parameter"))
        column = identifier(condition["column"])
        if condition["column"] not in allowed or condition["operator"] not in ("=", "!=", "<", "<=", ">", ">="):
            raise ValueError("許可外の条件です。")
        name = condition["parameter"]
        identifier(name)
        if name not in parameters:
            raise ValueError("未定義の引数です。")
        used.add(name)
        bound.append(values[name])
        where.append(column + " " + condition["operator"] + " ?")
    if used != set(parameters):
        raise ValueError("未使用の引数定義です。")
    for item in definition["order_by"]:
        require_exact_keys(item, ("column", "direction"))
        column = identifier(item["column"])
        if item["column"] not in allowed or item["direction"] not in ("asc", "desc"):
            raise ValueError("許可外の並び順です。")
        order.append(column + " " + item["direction"].upper())
    sql = "SELECT " + ", ".join(identifier(column) for column in definition["select"]) + " FROM " + identifier(definition["table"])
    if where:
        sql += " WHERE " + " AND ".join(where)
    if order:
        sql += " ORDER BY " + ", ".join(order)
    sql += " LIMIT " + str(limit)
    if options.mode == "explain":
        sql = "EXPLAIN QUERY PLAN " + sql
    return definition, {"sql": sql, "params": bound}, limit


class D1Record:
    def __init__(self):
        D1_SCRATCH.mkdir(mode=0o700, exist_ok=True)
        parent = private_directory(D1_SCRATCH)
        try:
            metadata = os.fstat(parent)
            if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
                raise ValueError("本人所有の private directory が必要です。")
            name = "cloudflare-inspect." + secrets.token_hex(12)
            os.mkdir(name, mode=0o700, dir_fd=parent)
            self.directory = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.fchmod(self.directory, 0o700)
        finally:
            os.close(parent)
        self.path = str(D1_SCRATCH / name / "record.json")
        descriptor = os.open("record.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.directory)
        os.close(descriptor)

    def write(self, value):
        name = ".record-" + secrets.token_hex(12)
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.directory)
        with os.fdopen(descriptor, "w") as output:
            os.fchmod(output.fileno(), 0o600)
            json.dump(value, output, ensure_ascii=False, allow_nan=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, "record.json", src_dir_fd=self.directory, dst_dir_fd=self.directory)
        os.fsync(self.directory)

    def close(self):
        os.close(self.directory)


class D1NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def d1_opener():
    # create_default_context() は SSLKEYLOGFILE も読むため、TLS client を直接作る。
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    cafile = os.environ.get("SSL_CERT_FILE") or os.environ.get("NIX_SSL_CERT_FILE")
    capath = os.environ.get("SSL_CERT_DIR")
    if cafile or capath:
        context.load_verify_locations(cafile=cafile, capath=capath)
    else:
        context.load_default_certs()
    proxies = getproxies_environment()
    if "https" not in proxies and "all" in proxies:
        proxies["https"] = proxies["all"]
    for name in ("http", "https"):
        if name in proxies:
            proxy = urlsplit(proxies[name])
            # urllib は CONNECT 前に proxy 側の TLS を開始しない。
            if proxy.scheme != "http" or not proxy.hostname or proxy.query or proxy.fragment or proxy.path not in ("", "/"):
                raise ValueError("未対応の proxy 設定です。")
    # 認証 challenge を再送する handler は登録しない。
    return build_opener(ProxyHandler(proxies), HTTPSHandler(context=context), D1NoRedirect())


def http_exchange(opener, request, timeout):
    try:
        with opener.open(request, timeout=timeout) as response:
            if response.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
                raise ValueError("JSON の応答が必要です。")
            raw = response.read(D1_MAX_RESPONSE + 1)
            if len(raw) > D1_MAX_RESPONSE:
                raise ValueError("D1 の応答が大きすぎます。")
            return response.status, raw
    except HTTPError as error:
        error.close()
        return error.code, b""


def d1_result(value, columns, limit, mode):
    if (not isinstance(value, dict) or set(value) - {"success", "errors", "messages", "result"}
            or value.get("success") is not True or value.get("errors") != [] or value.get("messages") != []
            or not isinstance(value.get("result"), list) or len(value["result"]) != 1):
        raise ValueError("D1 の応答が不正です。")
    result = value["result"][0]
    require_exact_keys(result, ("success", "results", "meta"))
    if (result["success"] is not True or not isinstance(result["results"], list) or len(result["results"]) > limit
            or mode == "explain" and not result["results"]):
        raise ValueError("D1 の結果が不正です。")
    for row in result["results"]:
        require_exact_keys(row, columns)
        if mode == "explain" and (any(type(row[key]) is not int or row[key] < 0 for key in ("id", "parent", "notused"))
                                  or not isinstance(row["detail"], str)):
            raise ValueError("D1 の実行計画が不正です。")
        for item in row.values():
            if type(item) not in (str, int, float, bool, type(None)) or isinstance(item, float) and not math.isfinite(item):
                raise ValueError("D1 の行が不正です。")
    meta = result["meta"]
    known = {"rows_read", "rows_written", "duration", "changed_db", "changes", "last_row_id", "served_by_colo",
             "served_by_primary", "served_by_region", "size_after", "timings"}
    if not isinstance(meta, dict) or set(meta) - known or not {"rows_read", "rows_written", "duration"} <= set(meta):
        raise ValueError("D1 の meta が不正です。")
    timings = meta.get("timings", {})
    if not isinstance(timings, dict) or set(timings) - {"sql_duration_ms"}:
        raise ValueError("D1 の timings が不正です。")
    numbers = meta | timings
    for key in ("rows_read", "rows_written", "duration", "changes", "last_row_id", "size_after", "sql_duration_ms"):
        if key not in numbers:
            continue
        number = numbers[key]
        if (type(number) not in (int, float) or number < (-2**63 if key == "last_row_id" else 0) or number > 2**63 - 1
                or not math.isfinite(number) or key not in ("duration", "sql_duration_ms") and type(number) is not int):
            raise ValueError("D1 の実行統計が不正です。")
    for key, kind in (("served_by_colo", str), ("served_by_primary", bool)):
        if key in meta and type(meta[key]) is not kind:
            raise ValueError("D1 の実行元が不正です。")
    if "served_by_region" in meta and meta["served_by_region"] not in ("WNAM", "ENAM", "WEUR", "EEUR", "APAC", "OC"):
        raise ValueError("D1 の region が不正です。")
    if meta["rows_written"] != 0 or meta.get("changed_db", False) is not False or meta.get("changes", 0) != 0:
        raise ValueError("D1 の書込みを検出しました。")
    return result["results"], {key: meta[key] for key in ("rows_read", "rows_written", "duration")}


def d1_parser():
    parser = Parser(prog="cloudflare-inspect --reviewed d1 read", allow_abbrev=False)
    parser.add_argument("--definition", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--params-file")
    parser.add_argument("--mode", choices=("select", "explain"), default="select")
    parser.add_argument("--limit", type=int, help="SELECT の LIMIT。計画行数の上限は定義の max_plan_rows。")
    return parser


def r2_parser():
    parser = Parser(prog="cloudflare-inspect --reviewed r2 objects list", allow_abbrev=False)
    parser.add_argument("--definition", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--limit", type=int)
    return parser


def r2_plan(options):
    raw = private_bytes(options.definition)
    if not re.fullmatch(r"[a-f0-9]{64}", options.sha256) or hashlib.sha256(raw).hexdigest() != options.sha256:
        raise ValueError("確認済み定義の hash と一致しません。")
    definition = strict_json(raw)
    require_exact_keys(definition, ("version", "account_id", "bucket", "prefix", "jurisdiction", "fields",
                                    "max_keys", "timeout_seconds", "max_credential_remaining_seconds"))
    if type(definition["version"]) is not int or definition["version"] != 1:
        raise ValueError("未対応の R2 定義です。")
    if not isinstance(definition["account_id"], str) or not re.fullmatch(r"[a-f0-9]{32}", definition["account_id"]):
        raise ValueError("対象 account が不正です。")
    bucket = definition["bucket"]
    if not isinstance(bucket, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket):
        raise ValueError("対象 bucket が不正です。")
    prefix = definition["prefix"]
    if (not isinstance(prefix, str) or not prefix.endswith("/") or len(prefix.encode("utf-8")) > 1024
            or any(ord(char) < 32 or ord(char) == 127 for char in prefix)):
        raise ValueError("非空で slash 終端の prefix が必要です。")
    if definition["jurisdiction"] != "default":
        raise ValueError("default jurisdiction だけを受理します。")
    fields = definition["fields"]
    allowed = ("key", "size", "etag", "last_modified")
    if (not isinstance(fields, list) or not fields or len(fields) > len(allowed)
            or any(not isinstance(field, str) or field not in allowed for field in fields)
            or len(set(fields)) != len(fields)):
        raise ValueError("fields は重複のない許可項目の非空部分集合にしてください。")
    for name, maximum in (("max_keys", 1000), ("timeout_seconds", 30), ("max_credential_remaining_seconds", 900)):
        if type(definition[name]) is not int or not 1 <= definition[name] <= maximum:
            raise ValueError("件数または期限の上限が不正です。")
    limit = options.limit if options.limit is not None else min(100, definition["max_keys"])
    if not 1 <= limit <= definition["max_keys"]:
        raise ValueError("--limit は定義の max_keys 以下にしてください。")
    return definition, limit


def r2_base64url(segment):
    if not isinstance(segment, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", segment):
        raise ValueError("session token の JWT 形式が不正です。")
    try:
        decoded = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("session token の JWT 形式が不正です。") from None
    if base64.urlsafe_b64encode(decoded).rstrip(b"=").decode("ascii") != segment:
        raise ValueError("session token の JWT 形式が不正です。")
    return decoded


def r2_credentials(definition):
    access_key_id, secret_access_key, session_token = (os.environ.get(name, "") for name in R2_CREDENTIAL_ENV)
    if (not re.fullmatch(r"[A-Za-z0-9]{1,256}", access_key_id)
            or any(ord(char) < 33 or ord(char) > 126 for char in secret_access_key)
            or not secret_access_key or len(secret_access_key) > 256
            or not session_token or len(session_token) > R2_MAX_SESSION_TOKEN
            or any(ord(char) < 33 or ord(char) > 126 for char in session_token)):
        raise ValueError("R2 の専用一時資格情報3値が必要です。")
    try:
        encoded_token = base64.b64decode(session_token, validate=True)
        if base64.b64encode(encoded_token).decode("ascii") != session_token:
            raise ValueError
        token_text = encoded_token.decode("ascii")
    except (binascii.Error, UnicodeError, ValueError):
        raise ValueError("R2 の session token 形式が不正です。") from None
    if not token_text.startswith("jwt/"):
        raise ValueError("R2 の session token 形式が不正です。")
    jwt = token_text[4:]
    if not jwt or len(jwt) > R2_MAX_JWT:
        raise ValueError("R2 の session token が長すぎます。")
    pieces = jwt.split(".")
    if len(pieces) != 3 or len(r2_base64url(pieces[2])) != 32:
        raise ValueError("R2 の session token の JWT 形式が不正です。")
    try:
        header = strict_json(r2_base64url(pieces[0]).decode("utf-8"))
        claims = strict_json(r2_base64url(pieces[1]).decode("utf-8"))
    except (UnicodeError, ValueError, RecursionError):
        raise ValueError("R2 の session token の JWT JSON が不正です。") from None
    if header != {"alg": "HS256", "typ": "JWT"}:
        raise ValueError("R2 の session token の header が不正です。")
    require_exact_keys(claims, ("iss", "sub", "aud", "iat", "exp", "actions", "bucket", "paths"))
    host = definition["account_id"] + ".r2.cloudflarestorage.com"
    if (claims["iss"] != access_key_id or claims["sub"] != definition["account_id"] or claims["aud"] != host
            or claims["bucket"] != definition["bucket"] or claims["actions"] != ["ListObjectsV2"]):
        raise ValueError("R2 の一時資格情報 scope が定義と一致しません。")
    paths = claims["paths"]
    if (not isinstance(paths, dict) or set(paths) not in ({"prefixPaths"}, {"prefixPaths", "objectPaths"})
            or paths["prefixPaths"] != [definition["prefix"]]
            or "objectPaths" in paths and paths["objectPaths"] != []):
        raise ValueError("R2 の一時資格情報 paths が定義と一致しません。")
    issued, expires = claims["iat"], claims["exp"]
    now = int(time.time())
    if (type(issued) is not int or type(expires) is not int or issued >= expires or issued > now + 60
            or expires <= now or expires > now + definition["max_credential_remaining_seconds"]):
        raise ValueError("R2 の一時資格情報の期限が定義と一致しません。")
    derived_secret = hashlib.sha256(jwt.encode("ascii")).hexdigest()
    if not hmac.compare_digest(secret_access_key, derived_secret):
        raise ValueError("R2 の一時資格情報の局所整合性検査に失敗しました。")
    return {"access_key_id": access_key_id, "secret_access_key": secret_access_key,
            "session_token": session_token, "jwt": jwt, "expires": expires}


def r2_redaction_values():
    values = dict(zip(("access_key_id", "secret_access_key", "session_token"),
                      (os.environ.get(name, "") for name in R2_CREDENTIAL_ENV)))
    session_token = values["session_token"]
    if session_token and len(session_token) <= R2_MAX_SESSION_TOKEN:
        try:
            encoded = base64.b64decode(session_token, validate=True)
            if base64.b64encode(encoded).decode("ascii") == session_token:
                token_text = encoded.decode("ascii")
                if token_text.startswith("jwt/") and len(token_text[4:]) <= R2_MAX_JWT:
                    values["jwt"] = token_text[4:]
        except (binascii.Error, UnicodeError, ValueError):
            pass
    return values


def r2_quote(value):
    return quote(value, safe="-_.~", encoding="utf-8", errors="strict")


def r2_signing_key(secret, day):
    key = hmac.new(("AWS4" + secret).encode("ascii"), day.encode("ascii"), hashlib.sha256).digest()
    key = hmac.new(key, b"auto", hashlib.sha256).digest()
    key = hmac.new(key, b"s3", hashlib.sha256).digest()
    return hmac.new(key, b"aws4_request", hashlib.sha256).digest()


def r2_request(definition, limit, credentials):
    host = definition["account_id"] + ".r2.cloudflarestorage.com"
    day_time = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    day = day_time[:8]
    query = sorted((r2_quote(name), r2_quote(value)) for name, value in (
        ("list-type", "2"), ("prefix", definition["prefix"]), ("max-keys", str(limit)), ("encoding-type", "url")))
    canonical_query = "&".join(name + "=" + value for name, value in query)
    payload_hash = hashlib.sha256(b"").hexdigest()
    signed_headers = "host;x-amz-content-sha256;x-amz-date;x-amz-security-token"
    canonical_headers = ("host:" + host + "\n" + "x-amz-content-sha256:" + payload_hash + "\n"
                         + "x-amz-date:" + day_time + "\n" + "x-amz-security-token:" + credentials["session_token"] + "\n")
    canonical_request = "\n".join(("GET", "/" + definition["bucket"], canonical_query, canonical_headers,
                                    signed_headers, payload_hash))
    scope = day + "/auto/s3/aws4_request"
    string_to_sign = "AWS4-HMAC-SHA256\n" + day_time + "\n" + scope + "\n" + hashlib.sha256(canonical_request.encode()).hexdigest()
    signature = hmac.new(r2_signing_key(credentials["secret_access_key"], day), string_to_sign.encode(), hashlib.sha256).hexdigest()
    authorization = ("AWS4-HMAC-SHA256 Credential=" + credentials["access_key_id"] + "/" + scope
                     + ", SignedHeaders=" + signed_headers + ", Signature=" + signature)
    url = "https://" + host + "/" + definition["bucket"] + "?" + canonical_query
    return Request(url, method="GET", headers={
        "Accept-Encoding": "identity",
        "Authorization": authorization,
        "X-Amz-Content-Sha256": payload_hash,
        "X-Amz-Date": day_time,
        "X-Amz-Security-Token": credentials["session_token"],
    })


def r2_exchange(opener, request, timeout):
    def read(response):
        encoding = (response.headers.get("Content-Encoding", "") or "").strip().lower()
        raw = b"" if encoding not in ("", "identity") else response.read(R2_MAX_RESPONSE + 1)
        return raw, {"content-type": response.headers.get("Content-Type", ""), "content-encoding": encoding}

    try:
        with opener.open(request, timeout=timeout) as response:
            raw, headers = read(response)
            return response.status, raw, headers
    except HTTPError as error:
        try:
            raw, headers = read(error)
        finally:
            error.close()
        return error.code, raw, headers


def r2_error_code(raw, headers):
    document = r2_xml_document(raw)
    if (len(raw) > R2_MAX_RESPONSE or headers.get("content-encoding", "") not in ("", "identity")
            or headers.get("content-type", "").split(";", 1)[0].strip().lower() not in ("application/xml", "text/xml")
            or document is None):
        return "unknown"
    try:
        root = ET.fromstring(document)
        code_nodes = [child for child in root if child.tag in ("Code", "{" + R2_NAMESPACE + "}Code")]
        code = code_nodes[0].text if root.tag in ("Error", "{" + R2_NAMESPACE + "}Error") and len(code_nodes) == 1 else None
    except (ET.ParseError, LookupError, ValueError, RecursionError):
        return "unknown"
    return code if isinstance(code, str) and code in R2_ERROR_CODES else "unknown"


def r2_xml_text(element, *, strip=False):
    if element.attrib or len(element):
        raise ValueError("R2 XML の要素形式が不正です。")
    value = element.text or ""
    if element.tail and element.tail.strip():
        raise ValueError("R2 XML の要素形式が不正です。")
    return value.strip() if strip else value


def r2_xml_document(raw):
    try:
        text = raw.decode("utf-8", "strict")
    except UnicodeError:
        return None
    upper = text.upper()
    if "\x00" in text or "<!DOCTYPE" in upper or "<!ENTITY" in upper:
        return None
    declaration = re.match(r"\ufeff?<\?xml\s+(.*?)\?>", text, re.IGNORECASE | re.DOTALL)
    if declaration:
        attributes = declaration.group(1)
        encoding = re.search(r"\bencoding\s*=\s*(['\"])(.*?)\1", attributes, re.IGNORECASE)
        if (re.search(r"\bencoding\b", attributes, re.IGNORECASE)
                and (encoding is None or encoding.group(2).lower() != "utf-8")):
            return None
    return text


def r2_decode_url(value):
    if re.search(r"%(?![a-fA-F0-9]{2})", value):
        raise ValueError("R2 XML の URL encoded key が不正です。")
    try:
        return unquote_to_bytes(value).decode("utf-8", "strict")
    except UnicodeError:
        raise ValueError("R2 XML の URL encoded key が不正です。") from None


def r2_page(raw, headers, definition, limit):
    document = r2_xml_document(raw)
    if (len(raw) > R2_MAX_RESPONSE or headers.get("content-encoding", "") not in ("", "identity")
            or headers.get("content-type", "").split(";", 1)[0].strip().lower() not in ("application/xml", "text/xml")
            or document is None):
        raise ValueError("R2 XML の応答形式または上限が不正です。")
    root = ET.fromstring(document)
    if root.tag != "{" + R2_NAMESPACE + "}ListBucketResult" or root.attrib or root.text and root.text.strip():
        raise ValueError("R2 XML の応答 root が不正です。")
    single = {}
    contents = []
    allowed_root = {"Name", "Prefix", "KeyCount", "MaxKeys", "IsTruncated", "EncodingType", "NextContinuationToken"}
    for child in root:
        if child.tag == "{" + R2_NAMESPACE + "}Contents":
            if child.attrib or child.text and child.text.strip() or child.tail and child.tail.strip():
                raise ValueError("R2 XML の Contents が不正です。")
            contents.append(child)
            continue
        if not isinstance(child.tag, str) or not child.tag.startswith("{" + R2_NAMESPACE + "}"):
            raise ValueError("R2 XML に未知 namespace があります。")
        name = child.tag[len("{" + R2_NAMESPACE + "}"):]
        if name not in allowed_root or name in single:
            raise ValueError("R2 XML に未知または重複した要素があります。")
        single[name] = r2_xml_text(child, strip=True)
    required = {"Name", "Prefix", "KeyCount", "MaxKeys", "IsTruncated", "EncodingType"}
    if set(single) - required - {"NextContinuationToken"} or not required <= set(single):
        raise ValueError("R2 XML の必須要素が不正です。")
    if (single["Name"] != definition["bucket"] or r2_decode_url(single["Prefix"]) != definition["prefix"]
            or single["EncodingType"] != "url" or single["MaxKeys"] != str(limit)
            or not re.fullmatch(r"0|[1-9][0-9]{0,3}", single["KeyCount"])):
        raise ValueError("R2 XML の対象または件数が一致しません。")
    if single["IsTruncated"] not in ("true", "false"):
        raise ValueError("R2 XML の継続状態が不正です。")
    truncated = single["IsTruncated"] == "true"
    continuation = single.get("NextContinuationToken")
    if (truncated and (not continuation or len(continuation) > 4096 or any(ord(char) < 32 for char in continuation))
            or not truncated and continuation is not None):
        raise ValueError("R2 XML の継続情報が不正です。")
    if int(single["KeyCount"]) != len(contents) or len(contents) > limit:
        raise ValueError("R2 XML の key count と Contents が一致しません。")
    items = []
    allowed_object = {"Key", "LastModified", "ETag", "Size", "StorageClass"}
    for content in contents:
        values = {}
        for child in content:
            if not isinstance(child.tag, str) or not child.tag.startswith("{" + R2_NAMESPACE + "}"):
                raise ValueError("R2 XML の Contents に未知 namespace があります。")
            name = child.tag[len("{" + R2_NAMESPACE + "}"):]
            if name not in allowed_object or name in values:
                raise ValueError("R2 XML の Contents に未知または重複した要素があります。")
            values[name] = r2_xml_text(child, strip=name != "Key")
        if not {"Key", "LastModified", "ETag", "Size"} <= set(values):
            raise ValueError("R2 XML の Contents に必須要素がありません。")
        key = r2_decode_url(values["Key"])
        if (not key.startswith(definition["prefix"]) or len(key.encode("utf-8")) > 1024
                or any(ord(char) < 32 or ord(char) == 127 for char in key)):
            raise ValueError("R2 XML の object key が許可 prefix 外です。")
        if (not re.fullmatch(r"0|[1-9][0-9]{0,18}", values["Size"]) or int(values["Size"]) > 2**63 - 1
                or not values["ETag"] or len(values["ETag"]) > 1024
                or any(ord(char) < 32 for char in values["ETag"])):
            raise ValueError("R2 XML の object metadata 型が不正です。")
        timestamp = values["LastModified"]
        if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?(?:Z|[+-][0-9]{2}:[0-9]{2})", timestamp):
            raise ValueError("R2 XML の LastModified が不正です。")
        try:
            parsed_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        except ValueError:
            raise ValueError("R2 XML の LastModified が不正です。") from None
        if parsed_time.tzinfo is None:
            raise ValueError("R2 XML の LastModified が不正です。")
        projected = {"key": key, "size": int(values["Size"]), "etag": values["ETag"], "last_modified": timestamp}
        items.append({field: projected[field] for field in definition["fields"]})
    return items, truncated


def redact_r2(value, credentials):
    secrets_to_remove = tuple(sorted((secret for secret in (credentials.get("access_key_id"),
        credentials.get("secret_access_key"), credentials.get("session_token"), credentials.get("jwt")) if secret),
        key=len, reverse=True))
    if isinstance(value, list):
        return [redact_r2(item, credentials) for item in value]
    if isinstance(value, dict):
        return {key: redact_r2(item, credentials) for key, item in value.items()}
    if isinstance(value, str):
        for secret in secrets_to_remove:
            value = value.replace(secret, "[非表示]")
    return value


def perform_r2(arguments, notify, started):
    options = r2_parser().parse_args(arguments)
    definition, limit = r2_plan(options)
    deadline = started + definition["timeout_seconds"]
    notify({"deadline": deadline})
    credentials = r2_redaction_values()
    record = D1Record()
    notify({"record_locator": record.path})
    audit = {"utc": datetime.now(timezone.utc).isoformat(), "operation": "r2 objects list", "status": "pending",
             "end_reason": "interrupted_or_deadline", "attempts_started": 0, "definition_sha256": options.sha256,
             "account_id": definition["account_id"], "bucket": definition["bucket"], "prefix": definition["prefix"],
             "jurisdiction": definition["jurisdiction"], "fields": definition["fields"], "max_keys": definition["max_keys"],
             "requested_max_keys": limit, "timeout_seconds": definition["timeout_seconds"],
             "max_credential_remaining_seconds": definition["max_credential_remaining_seconds"], "returned_count": None,
             "http_status": None, "service_error_code": None,
             "implementation": {"api_contract": "r2-listobjects-v2-v1", "helper_path": str(Path(__file__).resolve()),
                                "helper_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}}
    reason = "credential_validation"
    request_started = False
    try:
        record.write(redact_r2(audit, credentials))
        credentials.update(r2_credentials(definition))
        request = r2_request(definition, limit, credentials)
        reason = "transport_configuration"
        opener = d1_opener()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            reason = "deadline_exceeded"
            raise ValueError("R2 の全体期限を過ぎています。")
        audit["attempts_started"] = 1
        reason = "record_failed"
        record.write(redact_r2(audit, credentials))
        notify({"attempts_started": 1})
        request_started = True
        reason = "request_failed"
        status, raw, headers = r2_exchange(opener, request, remaining)
        audit["http_status"] = status
        if status != 200:
            audit["service_error_code"] = r2_error_code(raw, headers)
            reason = "http_error"
            raise ValueError("R2 object list request failed")
        reason = "invalid_response"
        items, truncated = r2_page(raw, headers, definition, limit)
        audit.update(status="truncated" if truncated else "complete", end_reason="truncated" if truncated else "complete",
                     returned_count=len(items), items=items)
        reason = "record_failed"
        record.write(redact_r2(audit, credentials))
        return {key: audit[key] for key in ("status", "returned_count", "end_reason", "attempts_started")} | {"record_locator": record.path}
    except (ValueError, OSError, RecursionError, HTTPException, ET.ParseError, LookupError, UnicodeError):
        audit.update(status="failed", end_reason=reason)
        if not request_started:
            audit["attempts_started"] = 0
        audit.pop("items", None)
        try:
            record.write(redact_r2(audit, credentials))
        except OSError:
            audit["end_reason"] = "record_failed"
        return {key: audit.get(key) for key in ("status", "returned_count", "end_reason", "attempts_started")} | {"record_locator": record.path}
    finally:
        record.close()


def r2_worker(sender, arguments, started, environment):
    os.environ.clear()
    os.environ.update(environment)
    try:
        result = perform_r2(arguments, sender.send, started)
    except Exception:
        result = {"status": "failed", "end_reason": "invalid_request", "attempts_started": 0, "record_locator": None}
    try:
        sender.send({"result": result})
    finally:
        sender.close()


def inspect_r2(arguments):
    started = time.monotonic()
    deadline = started + 30
    environment = {name: os.environ[name] for name in R2_CREDENTIAL_ENV + R2_TRANSPORT_ENV if name in os.environ}
    context = multiprocessing.get_context("fork")
    receiver, sender = context.Pipe(duplex=False)
    worker = context.Process(target=r2_worker, args=(sender, arguments, started, environment))
    state = {"status": "failed", "end_reason": "request_failed", "attempts_started": 0, "record_locator": None}
    worker.start()
    sender.close()
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not receiver.poll(remaining):
                state["end_reason"] = "deadline_exceeded"
                break
            try:
                message = receiver.recv()
            except EOFError:
                break
            if "deadline" in message:
                deadline = min(deadline, message["deadline"])
            elif "result" in message:
                state.update(message["result"])
                break
            else:
                state.update(message)
    finally:
        if worker.is_alive():
            worker.kill()
        worker.join()
        if state["end_reason"] == "deadline_exceeded":
            while receiver.poll():
                try:
                    notice = receiver.recv()
                except EOFError:
                    break
                notice = notice.get("result", notice)
                for key in ("record_locator", "attempts_started"):
                    if key in notice:
                        state[key] = notice[key]
        receiver.close()
    return state


def perform_d1(arguments, notify, started):
    options = d1_parser().parse_args(arguments)
    definition, body, limit = d1_plan(options, os.environ.get("CLOUDFLARE_ACCOUNT_ID", ""))
    result_limit = definition["max_plan_rows"] if options.mode == "explain" else limit
    deadline = started + definition["timeout_seconds"]
    notify({"deadline": deadline})
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    if not token or any(ord(c) < 32 for c in token):
        raise ValueError("D1 Read の token が必要です。")
    record = D1Record()
    notify({"record": record.path})
    audit = {"utc": datetime.now(timezone.utc).isoformat(), "mode": options.mode, "status": "pending",
             "stop_reason": "interrupted_or_deadline", "attempts_started": 0, "definition_sha256": options.sha256,
             "account_id": definition["account_id"], "database_id": definition["database_id"], "query": body,
             "limit": limit, "result_limit": result_limit, "timeout_seconds": definition["timeout_seconds"], "returned_count": None,
             "rows_read": None, "rows_written": None, "duration": None,
             "query_plan": None, "query_plan_reason": "not_requested" if options.mode == "select" else "not_completed",
             "implementation": {"cli_pin": VERSION, "api_contract": "d1-query-v1", "helper_path": str(Path(__file__).resolve()),
                                "helper_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}}
    reason = "record_failed"
    request_started = False
    try:
        record.write(redact(audit, token))
        request = Request("https://api.cloudflare.com/client/v4/accounts/" + definition["account_id"] +
                          "/d1/database/" + definition["database_id"] + "/query", method="POST",
                          data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                                                                  "Accept": "application/json", "User-Agent": "dotfiles-cloudflare-inspect/" + VERSION})
        reason = "transport_configuration"
        opener = d1_opener()
        audit["attempts_started"] = 1
        reason = "record_failed"
        record.write(redact(audit, token))
        reason = "deadline_exceeded"
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError("D1 の全体期限を過ぎています。")
        notify({"attempts_started": 1})
        request_started = True
        reason = "request_failed"
        status, raw = http_exchange(opener, request, remaining)
        if status != 200:
            reason = "http_error"
            raise ValueError("D1 の参照に失敗しました。")
        reason = "invalid_response"
        columns = definition["select"] if options.mode == "select" else ["id", "parent", "notused", "detail"]
        rows, meta = d1_result(strict_json(raw), columns, result_limit, options.mode)
        audit.update(status="success", returned_count=len(rows),
                     stop_reason="limit_reached_unknown" if options.mode == "select" and len(rows) == limit else "complete", **meta)
        if options.mode == "select":
            audit["results"] = rows
        else:
            audit.update(query_plan=rows, query_plan_reason=None)
        reason = "record_failed"
        record.write(redact(audit, token))
        return {key: audit[key] for key in ("status", "returned_count", "stop_reason", "attempts_started", "rows_read", "rows_written", "duration")} | {"record": record.path}
    except (ValueError, OSError, RecursionError, HTTPException):
        audit.update(status="failed", stop_reason=reason)
        if not request_started:
            audit["attempts_started"] = 0
        audit.pop("results", None)
        audit["query_plan"] = None
        try:
            record.write(redact(audit, token))
        except OSError:
            audit["stop_reason"] = "record_failed"
        return {key: audit.get(key) for key in ("status", "returned_count", "stop_reason", "attempts_started", "rows_read", "rows_written", "duration")} | {"record": record.path}
    finally:
        record.close()


def d1_worker(sender, arguments, started):
    try:
        result = perform_d1(arguments, sender.send, started)
    except Exception:
        # 定義・transport・保存の例外本文に含まれる利用環境の値を IPC へ渡さない。
        result = {"status": "failed", "stop_reason": "invalid_request"}
    try:
        sender.send({"result": result})
    finally:
        sender.close()


def inspect_d1(arguments):
    started = time.monotonic()
    deadline = started + 30
    context = multiprocessing.get_context("fork")
    receiver, sender = context.Pipe(duplex=False)
    worker = context.Process(target=d1_worker, args=(sender, arguments, started))
    state = {"status": "failed", "stop_reason": "request_failed", "attempts_started": 0, "record": None}
    worker.start()
    sender.close()
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not receiver.poll(remaining):
                state["stop_reason"] = "deadline_exceeded"
                break
            try:
                message = receiver.recv()
            except EOFError:
                break
            if "deadline" in message:
                deadline = min(deadline, message["deadline"])
            elif "result" in message:
                state.update(message["result"])
                break
            else:
                state.update(message)
    finally:
        if worker.is_alive():
            worker.kill()
        worker.join()
        if state["stop_reason"] == "deadline_exceeded":
            # deadline より先に送られた開始通知を捨てて、架空の0試行にしない。
            while receiver.poll():
                try:
                    notice = receiver.recv()
                except EOFError:
                    break
                notice = notice.get("result", notice)
                for key in ("record", "attempts_started"):
                    if key in notice:
                        state[key] = notice[key]
        receiver.close()
    return state


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError("許可外または不正な引数です。対応する引数は --help と調査手順を確認してください。")


def redact(value, token):
    # shortcut: 未知の項目の秘密値は判別しない, 参照する API の機密項目が増えたら更新する。
    if isinstance(value, list):
        return [redact(item, token) for item in value]
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            name = re.sub(r"[^a-z0-9]", "", key.lower())
            sensitive = name in {"vars", "bindings", "env", "environment", "environmentvariables", "authorization", "cookie", "cookies", "setcookie", "proxyauthorization", "cfaccessjwtassertion", "xauthkey"} or name.endswith(
                ("token", "password", "passwd", "secret", "secrets", "privatekey", "apikey", "credential", "credentials")
            )
            result[redact(key, token)] = "[非表示]" if sensitive else redact(item, token)
        return result
    return value.replace(token, "[非表示]") if isinstance(value, str) and token else value


def read_cf(arguments, *, local=False):
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    if not local and (not token or not re.fullmatch(r"[a-fA-F0-9]{32}", account)):
        raise ValueError("必要な調査権限を持つ CLOUDFLARE_API_TOKEN と対象の CLOUDFLARE_ACCOUNT_ID が必要です。")
    inherited = ("LANG", "LC_ALL", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                 "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS", "NIX_SSL_CERT_FILE")
    environment = {key: os.environ[key] for key in inherited if key in os.environ}
    scratch = Path("/tmp/codex")
    scratch.mkdir(mode=0o700, exist_ok=True)
    metadata = scratch.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise ValueError("/tmp/codex は本人所有の private directory が必要です。")
    with tempfile.TemporaryDirectory(prefix="cloudflare-inspect-", dir=scratch) as temporary:
        # project の .env・実行可能設定・保存済み認証を読み込ませない。
        environment.update(HOME=temporary, TMPDIR=temporary, XDG_CONFIG_HOME=temporary, XDG_CACHE_HOME=temporary,
                           XDG_DATA_HOME=temporary, XDG_STATE_HOME=temporary, CI="true", NO_COLOR="1",
                           CF_SEND_TELEMETRY="false", DO_NOT_TRACK="1", CF_DELEGATION="1",
                           CLOUDFLARE_API_BASE_URL="https://api.cloudflare.com/client/v4",
                           CLOUDFLARE_COMPLIANCE_REGION="public")
        def invoke(args):
            result = subprocess.run([str(Path(__file__).resolve().with_name("cf")), *args], capture_output=True, text=True, timeout=120,
                                    cwd=temporary, env=environment)
            if result.returncode:
                raise ValueError("cf の参照に失敗しました。必要な調査権限・対象・接続状態を確認してください。")
            return result.stdout
        version = invoke(["--version"]).strip()
        if version != VERSION:
            raise ValueError("cf の版が検証済み pin と一致しません。ユーザー環境を更新してください。")
        if arguments == ["--version"]:
            return version
        if not local:
            environment.update(CLOUDFLARE_API_TOKEN=token, CLOUDFLARE_ACCOUNT_ID=account)
        try:
            value = json.loads(invoke(arguments))
        except (ValueError, RecursionError):
            raise ValueError("cf の参照に失敗したか、出力が正しい JSON ではありません。") from None
    return json.dumps(redact(value, token), ensure_ascii=False)


def query_logs(arguments):
    parser = Parser(prog="cloudflare-inspect o11y telemetry query", allow_abbrev=False)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--limit", type=int, default=100)
    options = parser.parse_args(arguments)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,255}", options.worker):
        raise ValueError("--worker は英数字・ハイフン・アンダースコアの1〜255文字で指定してください。")
    if not 1 <= options.limit <= 1000:
        raise ValueError("--limit は1〜1000にしてください。")
    try:
        for value in (options.start, options.end):
            if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?(?:Z|[+-][0-9]{2}:[0-9]{2})", value):
                raise ValueError
        start, end = (datetime.fromisoformat(value) for value in (options.start, options.end))
    except ValueError:
        raise ValueError("--start と --end はタイムゾーン付きの ISO 8601 日時で指定してください。小数秒はミリ秒までです。") from None
    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
    if not timedelta(0) < end - start <= timedelta(hours=24) or end > datetime.now(timezone.utc) or start < epoch:
        raise ValueError("過去の開始・終了日時を昇順で指定し、期間を24時間以内にしてください。")
    body = {"queryId": "cloudflare-inspect", "timeframe": {"from": (start - epoch) // timedelta(milliseconds=1), "to": (end - epoch) // timedelta(milliseconds=1)},
            "view": "events", "limit": options.limit, "dry": True,
            "parameters": {"datasets": ["cloudflare-workers"],
                           "filters": [{"key": "$metadata.service", "operation": "eq", "type": "string", "value": options.worker}]}}
    return read_cf([*LOG_QUERY, "--body", json.dumps(body)])


def main(arguments):
    if not arguments or arguments == ["--help"]:
        print("使い方: cloudflare-inspect <cf の参照操作> [引数]\n対応操作:\n" +
              "\n".join("  " + " ".join(command) for command in OPERATIONS) +
              "\n過去ログ: o11y telemetry query --worker NAME --start ISO日時 --end ISO日時 [--limit 100]" +
              "\n  最大24時間・1000件。日時のタイムゾーンは必須。" +
              "\n確認後の追加参照: --reviewed d1 get <database-id> [--fields FIELDS]" +
              "\n限定読取り: --reviewed d1 read --definition PATH --sha256 HASH [--params-file PATH] [--mode select|explain] [--limit N]" +
              "\n  確認済み宣言形式のみ。最大1000件・1 HTTP試行・全体30秒。" +
              "\n限定読取り: --reviewed r2 objects list --definition PATH --sha256 HASH [--limit N]" +
              "\n  確認済み宣言形式のみ。先頭1ページ・1 HTTP試行・全体30秒。" +
              "\n版表示: --version（認証不要、ローカルのみ）" +
              "\n検索: cli search <固定語彙>\n  " + " / ".join(SEARCH_TERMS))
        return 0
    if arguments == ["--version"]:
        print(read_cf(arguments, local=True))
        return 0
    reviewed = arguments[:1] == ["--reviewed"]
    if reviewed:
        arguments = arguments[1:]
    if arguments[:2] == ["d1", "read"]:
        if not reviewed:
            raise ValueError("D1 の限定参照は操作ごとの確認後に --reviewed を指定してください。")
        if any(argument in ("-h", "--help") for argument in arguments[2:]):
            d1_parser().print_help()
            return 0
        summary = inspect_d1(arguments[2:])
        print(json.dumps(summary, ensure_ascii=False))
        return int(summary["status"] != "success")
    if arguments[:len(R2_LIST)] == list(R2_LIST):
        if not reviewed:
            raise ValueError("R2 の限定参照は操作ごとの確認後に --reviewed を指定してください。")
        if any(argument in ("-h", "--help") for argument in arguments[len(R2_LIST):]):
            r2_parser().print_help()
            return 0
        summary = inspect_r2(arguments[len(R2_LIST):])
        print(json.dumps(summary, ensure_ascii=False))
        return int(summary["status"] == "failed")
    if arguments[:len(LOG_QUERY)] == list(LOG_QUERY):
        print(query_logs(arguments[len(LOG_QUERY):]))
        return 0
    if arguments[:2] == ["cli", "search"]:
        if len(arguments) != 3 or arguments[2] not in SEARCH_TERMS:
            raise ValueError("コマンド検索には --help に示した固定の product 語彙だけを指定してください。")
        print(read_cf(arguments, local=True))
        return 0
    command = next((key for key in OPERATIONS | REVIEWED if arguments[:len(key)] == list(key)), None)
    if command is None or command in REVIEWED and not reviewed:
        raise ValueError("自動許可対象外です。操作内容と理由をユーザーへ示して確認してください。制限付き過去ログ検索以外の Write 操作と秘密値取得は確認後も受理しません。")
    parser = Parser(prog="cloudflare-inspect", allow_abbrev=False)
    if command in REVIEWED:
        parser.add_argument("database_id")
    options = (OPERATIONS | REVIEWED)[command]
    for option in options:
        parser.add_argument("--" + option, type=int if option in {"page", "per-page"} else str)
    parsed = vars(parser.parse_args(arguments[len(command):]))
    if "page" in options:
        parsed["page"] = parsed["page"] if parsed["page"] is not None else 1
        if parsed["page"] < 1:
            raise ValueError("--page は1以上にしてください。")
    if "per-page" in options:
        parsed["per_page"] = parsed["per_page"] if parsed["per_page"] is not None else 100
        if not 1 <= parsed["per_page"] <= 100:
            raise ValueError("--per-page は1〜100にしてください。")
    allowed = {"order": {"name"}, "direction": {"asc", "desc"},
               "order_by": {"created_on", "modified_on", "name"}, "cf_r2_jurisdiction": {"default", "eu"}}
    for key, value in parsed.items():
        if isinstance(value, str) and (not value or len(value) > 2048 or any(ord(c) < 32 for c in value)):
            raise ValueError("文字列の引数が空、長すぎる、または制御文字を含んでいます。")
        if key in allowed and value is not None and value not in allowed[key]:
            raise ValueError("指定した引数の値は許可されていません。")
    args = list(command)
    if database := parsed.pop("database_id", None):
        if not re.fullmatch(r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", database):
            raise ValueError("database-id は UUID で指定してください。")
        args.append(database)
    args.extend("--" + option + "=" + str(parsed[option.replace("-", "_")]) for option in options
                if parsed[option.replace("-", "_")] is not None)
    print(read_cf(args))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except ValueError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2) from None
    except (OSError, subprocess.TimeoutExpired, RecursionError):
        print("Cloudflare の参照を安全に完了できませんでした。CLI の配備と接続状態を確認してください。", file=sys.stderr)
        raise SystemExit(1) from None
