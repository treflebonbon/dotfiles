#!/usr/bin/env -S python3 -I

"""Cloudflare の確認済み参照操作だけを、機密項目を除外して返す。"""

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


VERSION = "1.0.0-beta.24"
OPERATIONS = {
    ("d1", "list"): ("page", "per-page", "name"),
    ("durable-objects", "namespaces", "list"): ("page", "per-page"),
    ("r2", "buckets", "list"): ("per-page", "name-contains", "start-after", "cursor", "order", "direction", "cf-r2-jurisdiction"),
    ("workers", "scripts", "search"): ("page", "per-page", "name", "id", "order-by"),
}
REVIEWED = {("d1", "get"): ("fields",)}
SEARCH_TERMS = ("durable objects namespaces", "d1 databases", "r2 buckets", "workers scripts")
LOG_QUERY = ("o11y", "telemetry", "query")


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
            sensitive = name in {"vars", "bindings", "env", "environment", "environmentvariables", "authorization", "cookie", "cookies", "setcookie"} or name.endswith(
                ("token", "password", "passwd", "secret", "secrets", "privatekey", "apikey", "credential", "credentials")
            )
            result[redact(key, token)] = "[非表示]" if sensitive else redact(item, token)
        return result
    return value.replace(token, "[非表示]") if isinstance(value, str) and token else value


def read_cf(arguments, *, search=False):
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    if not search and (not token or not re.fullmatch(r"[a-fA-F0-9]{32}", account)):
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
        if invoke(["--version"]).strip() != VERSION:
            raise ValueError("cf の版が検証済み pin と一致しません。ユーザー環境を更新してください。")
        if not search:
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
              "\n検索: cli search <固定語彙>\n  " + " / ".join(SEARCH_TERMS))
        return 0
    reviewed = arguments[:1] == ["--reviewed"]
    if reviewed:
        arguments = arguments[1:]
    if arguments[:len(LOG_QUERY)] == list(LOG_QUERY):
        print(query_logs(arguments[len(LOG_QUERY):]))
        return 0
    if arguments[:2] == ["cli", "search"]:
        if len(arguments) != 3 or arguments[2] not in SEARCH_TERMS:
            raise ValueError("コマンド検索には --help に示した固定の product 語彙だけを指定してください。")
        print(read_cf(arguments, search=True))
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
