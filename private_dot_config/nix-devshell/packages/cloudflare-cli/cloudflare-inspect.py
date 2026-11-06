#!/usr/bin/env -S python3 -I

"""Cloudflare の確認済み参照操作だけを、機密項目を除外して返す。"""

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import math
import multiprocessing
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time
from urllib.request import Request


VERSION = "1.0.0-beta.25"
OPERATIONS = {
    ("d1", "list"): ("page", "per-page", "name"),
    ("durable-objects", "namespaces", "list"): ("page", "per-page"),
    ("r2", "buckets", "list"): ("per-page", "name-contains", "start-after", "cursor", "order", "direction", "cf-r2-jurisdiction"),
    ("workers", "scripts", "search"): ("page", "per-page", "name", "id", "order-by"),
}
REVIEWED = {("d1", "get"): ("fields",)}
SEARCH_TERMS = ("durable objects namespaces", "d1 databases", "r2 buckets", "workers scripts")
LOG_QUERY = ("o11y", "telemetry", "query")
D1_SCRATCH = Path("/tmp/codex")
D1_MAX_JSON = 65536


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


def keys(value, expected):
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
    keys(definition, ("version", "account_id", "database_id", "table", "allowed_columns", "select",
                      "where", "order_by", "parameters", "max_rows", "timeout_seconds"))
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
    for name, maximum in (("max_rows", 1000), ("timeout_seconds", 30)):
        if type(definition[name]) is not int or not 1 <= definition[name] <= maximum:
            raise ValueError("件数または期限の上限が不正です。")
    limit = options.limit if options.limit is not None else min(100, definition["max_rows"])
    if not 1 <= limit <= definition["max_rows"]:
        raise ValueError("許可外の取得件数です。")
    parameters = definition["parameters"]
    values = strict_json(private_bytes(options.params_file)) if options.params_file else {}
    if not isinstance(parameters, dict) or len(parameters) > 16:
        raise ValueError("引数定義が不正です。")
    keys(values, parameters)
    for name, rule in parameters.items():
        identifier(name)
        keys(rule, ("type", "max_length", "values"))
        if (rule["type"] != "string" or type(rule["max_length"]) is not int or not 1 <= rule["max_length"] <= 4096
                or not isinstance(rule["values"], list) or not rule["values"] or len(rule["values"]) > 256):
            raise ValueError("文字列引数の型・許可値が不正です。")
        for value in rule["values"]:
            if not isinstance(value, str) or len(value) > rule["max_length"] or any(ord(c) < 32 for c in value):
                raise ValueError("文字列引数の許可値が不正です。")
        if not isinstance(values[name], str) or values[name] not in rule["values"]:
            raise ValueError("許可外の引数値です。")
    where, order, bound, used = [], [], [], set()
    for collection in ("where", "order_by"):
        if not isinstance(definition[collection], list) or len(definition[collection]) > 16:
            raise ValueError("条件または並び順が不正です。")
    for condition in definition["where"]:
        keys(condition, ("column", "operator", "parameter"))
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
        keys(item, ("column", "direction"))
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


def http_exchange(opener, request, timeout):
    raise OSError("D1 transport は未実装です。")


def d1_result(value, columns, limit):
    if (not isinstance(value, dict) or set(value) - {"success", "errors", "messages", "result"}
            or value.get("success") is not True or value.get("errors") != [] or value.get("messages") != []
            or not isinstance(value.get("result"), list) or len(value["result"]) != 1):
        raise ValueError("D1 の応答が不正です。")
    result = value["result"][0]
    keys(result, ("success", "results", "meta"))
    if result["success"] is not True or not isinstance(result["results"], list) or len(result["results"]) > limit:
        raise ValueError("D1 の結果が不正です。")
    for row in result["results"]:
        keys(row, columns)
        for item in row.values():
            if type(item) not in (str, int, float, bool, type(None)) or isinstance(item, float) and not math.isfinite(item):
                raise ValueError("D1 の行が不正です。")
    meta = result["meta"]
    known = {"rows_read", "rows_written", "duration", "changed_db", "changes", "last_row_id", "served_by_colo",
             "served_by_primary", "served_by_region", "size_after", "timings"}
    if not isinstance(meta, dict) or set(meta) - known:
        raise ValueError("D1 の meta が不正です。")
    for key in ("rows_read", "rows_written", "duration"):
        number = meta.get(key)
        if type(number) not in (int, float) or not math.isfinite(number) or number < 0:
            raise ValueError("D1 の実行統計が不正です。")
    if meta["rows_written"] != 0 or meta.get("changed_db", False) is not False or meta.get("changes", 0) != 0:
        raise ValueError("D1 の書込みを検出しました。")
    return result["results"], {key: meta[key] for key in ("rows_read", "rows_written", "duration")}


def perform_d1(arguments, notify, started):
    parser = Parser(prog="cloudflare-inspect --reviewed d1 read", allow_abbrev=False)
    parser.add_argument("--definition", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--params-file")
    parser.add_argument("--mode", choices=("select", "explain"), default="select")
    parser.add_argument("--limit", type=int)
    options = parser.parse_args(arguments)
    definition, body, limit = d1_plan(options, os.environ.get("CLOUDFLARE_ACCOUNT_ID", ""))
    notify({"deadline": started + definition["timeout_seconds"]})
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    if not token or any(ord(c) < 32 for c in token):
        raise ValueError("D1 Read の token が必要です。")
    record = D1Record()
    notify({"record": record.path})
    audit = {"utc": datetime.now(timezone.utc).isoformat(), "mode": options.mode, "status": "pending",
             "stop_reason": "interrupted_or_deadline", "attempts_started": 0, "definition_sha256": options.sha256,
             "account_id": definition["account_id"], "database_id": definition["database_id"], "query": body,
             "query_plan": None, "query_plan_reason": "not_requested" if options.mode == "select" else "not_completed",
             "implementation": {"cli_pin": VERSION, "helper_path": str(Path(__file__).resolve()),
                                "helper_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}}
    reason = "record_failed"
    try:
        record.write(redact(audit, token))
        request = Request("https://api.cloudflare.com/client/v4/accounts/" + definition["account_id"] +
                          "/d1/database/" + definition["database_id"] + "/query", method="POST",
                          data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        audit["attempts_started"] = 1
        record.write(redact(audit, token))
        notify({"attempts_started": 1})
        reason = "request_failed"
        status, raw = http_exchange(None, request, definition["timeout_seconds"])
        if status != 200:
            reason = "http_error"
            raise ValueError("D1 の参照に失敗しました。")
        reason = "invalid_response"
        columns = definition["select"] if options.mode == "select" else ["id", "parent", "notused", "detail"]
        rows, meta = d1_result(strict_json(raw), columns, limit if options.mode == "select" else 1000)
        audit.update(status="success", returned_count=len(rows), stop_reason="limit_reached_unknown" if len(rows) == limit else "complete", **meta)
        if options.mode == "select":
            audit["results"] = rows
        else:
            audit.update(query_plan=rows, query_plan_reason=None)
        reason = "record_failed"
        record.write(redact(audit, token))
        return {key: audit[key] for key in ("status", "returned_count", "stop_reason", "attempts_started", "rows_read", "rows_written", "duration")} | {"record": record.path}
    except (ValueError, OSError, RecursionError):
        audit.update(status="failed", stop_reason=reason)
        audit.pop("results", None)
        audit["query_plan"] = None
        record.write(redact(audit, token))
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
        summary = inspect_d1(arguments[2:])
        print(json.dumps(summary, ensure_ascii=False))
        return int(summary["status"] != "success")
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
