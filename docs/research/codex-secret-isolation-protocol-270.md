---
type: research
title: "#270 の合成 Responses API と stdio MCP 検証プロトコル"
description: 実インストールされた Codex CLI を、認証情報を使わない合成 Responses API と最小 stdio MCP に接続して、外側の隔離境界を検証するための一次資料に基づく手順。
tags: [research, codex, sandbox, responses-api, mcp, secret]
timestamp: 2026-09-09
---

# #270 の合成 Responses API と stdio MCP 検証プロトコル

## 結論

隔離起動の受入テストは、実インストール済みの **Codex CLI 0.153.4** を起動しつつ、モデル側だけを loopback の合成 Responses API に置き換えられる。Codex は custom `model_providers` の `base_url` と `wire_api = "responses"` を受け付ける。[Codex 0.153.4 の公式 proxy README](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/responses-api-proxy/README.md) は同じ provider 設定で `POST /v1/responses` を使用している。

これは **実ホスト推論、ChatGPT 認証、実プロジェクト秘密の検証ではない**。確認できるのは、Codex 本体が隔離内で起動し、合成モデルが要求した shell tool とローカル stdio MCP を Codex が実行し、応答を次ターンへ返せること、および fixture 外の秘密を取得できないことだけである。

## 最小の構成

合成 API 用の profile は、隔離用の一時 `CODEX_HOME` 内にだけ置く。実ユーザー設定を mount も参照もしない。

```toml
model_provider = "fixture"
model = "fixture-model"

[model_providers.fixture]
name = "fixture Responses API"
base_url = "http://127.0.0.1:<port>/v1"
wire_api = "responses"
requires_openai_auth = false

[mcp_servers.fixture]
command = "/fixture/bin/mcp-probe"
args = []
cwd = "/workspace"
startup_timeout_sec = 10
tool_timeout_sec = 10
enabled_tools = ["probe"]

[mcp_servers.fixture.tools.probe]
approval_mode = "approve"
```

`mcp_servers.<id>.command`、`args`、`cwd` は stdio server の起動設定であり、Codex は local stdio process を `env_clear()` して設定済みの環境だけを渡す。[Codex source: stdio launcher](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/rmcp-client/src/stdio_server_launcher.rs) したがって MCP fixture 自身についても、外側 sandbox の mount と環境 allowlist が実効境界となる。

`auto` は「自動承認」ではない。これは annotation などから判断する mode で、annotation を持たない fixture tool は approval-required になり得る。#270 では server 全体を緩めず、`enabled_tools = ["probe"]` と単一 tool の `approval_mode = "approve"` を組み合わせる。`approve` はこの release の `AppToolApproval` enum の明示値であり、`tools.<name>.approval_mode` は MCP server の per-tool policy として schema に定義されている。[Codex 0.153.4 config schema: enum](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/config.schema.json#L202-L228) [MCP per-tool policy](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/config.schema.json#L2030-L2049) [MCP server allow-list and defaults](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/config.schema.json#L3126-L3151)

実行は非対話的な `codex exec` に固定し、synthetic API 専用の provider を指定する。legacy `--sandbox` は permission profile を置換するため、実装時は両者を混在させない。

```text
codex exec --skip-git-repo-check --ask-for-approval never \
  "Run the requested fixture command, call the fixture MCP tool, then report the exact final marker."
```

## Responses API の scripted sequence

Codex は `POST /v1/responses` を `stream: true` で呼ぶ。fixture server は request の全 schema を再実装せず、次の SSE sequence を request ごとに返せばよい。

1. 最初の POST: `response.created`、`response.output_item.done` の `function_call`（`name: "exec_command"`, `call_id: "call-shell"`, `arguments: "{...}"`）、`response.completed`。
2. 二番目の POST: 入力に `function_call_output` の `call-shell` があることを assertion し、fixture MCP 用の namespaced `function_call` を返す。
3. 三番目の POST: MCP の `function_call_output` があることを assertion し、assistant output text の最終 marker と `response.completed` を返す。

Codex の公式 test helper はこの event 形をそのまま構成している。`function_call` は `response.output_item.done` 内の `call_id`、`name`、JSON string の `arguments` を持ち、assistant message も同じ event 内の `output_text` である。[function call event](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/tests/common/responses.rs#L867-L876) [assistant message event](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/tests/common/responses.rs#L729-L739) [completed event](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/tests/common/responses.rs#L685-L702) 各 event は `event: <type>` と JSON `data:` 行を持つ SSE である。[SSE helper](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/tests/common/responses.rs#L666-L679)

shell call の arguments は、例えば次で足りる。

```json
{
  "cmd": "/fixture/bin/assert-boundary",
  "workdir": "/workspace",
  "yield_time_ms": 1000
}
```

Codex 自身の app-server test も `exec_command` とこの `cmd` / `workdir` / `yield_time_ms` 形を使う。[Codex test helper](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/app-server/tests/common/responses.rs#L3-L22)

MCP call は、この release の namespace-aware function call として返す。小さい fixture server を一つだけ有効にして deferred discovery を避け、request が公開した namespace / tool schema を server 側で記録してから、それと一致する `namespace` と tool name を返す。namespace を推測して固定しない。Codex の test helper は `namespace` を function call item の別フィールドとして送る。[namespace-aware event](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/tests/common/responses.rs#L878-L893)

## stdio MCP fixture

fixture server は JSON-RPC over stdio の `initialize`、`notifications/initialized`、`tools/list`、`tools/call` だけを実装する。`tools/list` は引数なしの `probe` を一つ返し、`tools/call(probe)` は固定の `{ "content": [{"type":"text","text":"MCP_OK"}] }` を返す。これで agent が実際に child process を起動し、MCP handshake と tool call を行った証跡を別ファイルに残せる。

MCP のコマンド、cwd、環境は host の config ではなくこの fixture profile に限定する。Codex の stdio launcher は `env_clear()` 後に server config の環境を設定するため、fixture に host secret を継承させない。[Codex source: launcher environment](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/rmcp-client/src/stdio_server_launcher.rs)

## 境界の assertions

shell fixture と MCP fixture は値を出力せず成功 marker だけを残す。少なくとも次を個別に assertion する。

- `/workspace` の通常ソースと shellHook が使う tool は読める。
- worktree root の `.env`、別 bind path の dummy secret、親から設定した synthetic secret environment variable は存在せず、読取りにも失敗する。
- `HOME`、`XDG_CONFIG_HOME`、`CODEX_HOME` は fixture 内の専用 path であり、host のユーザー設定を参照しない。
- shell tool の marker、MCP の `MCP_OK`、最終 assistant marker が全て揃う。
- provider server が、shell と MCP の `function_call_output` を含む順序どおりの POST を受けたことを確認する。

これらは sandbox の file denial assertion であり、合成モデルに秘密を送らないことも provider request log の sentinel 検索で別途確認する。log を repository に残す場合も sentinel 名だけを扱い、実値を決して記録しない。

## GitHub の read-only probe

この合成 fixture だけでは GitHub 実操作・stored credential の受入確認はできない。実接続は未確認として残す。ネットワーク許可を最小限に確認するなら、空の `GH_CONFIG_DIR`、`GH_PROMPT_DISABLED=1`、明示的に unset した token variables で public repository の `GET` を一回だけ実行する候補がある。

```text
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
  GH_CONFIG_DIR=/fixture/gh-config GH_PROMPT_DISABLED=1 GH_HOST=github.com \
  gh api repos/octocat/Hello-World --method GET --jq .full_name
```

`GH_CONFIG_DIR` は gh の設定位置を決め、token environment variables は stored credentials より優先する。[GitHub CLI environment](https://cli.github.com/manual/gh_help_environment) ただし `gh api` は authentication を前提に記述されているため、この invocation が当該 gh release で anonymous request に落ちない場合は、成功を求めず "認証なしでは実行不可" と記録する。GitHub REST API 自体は public data に anonymous GET を許可し、IP あたり毎時 60 request の制限を設ける。[GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)

## 実装判断への制約

- fixture の成功は、実 hosted inference、実 GitHub write、実 GitHub/MCP credentials、または任意の third-party MCP の安全性を証明しない。
- host で起動した synthetic HTTP server へ namespace を越えて接続するなら、loopback socket と server process の visibility は外側 sandbox の追加検証対象である。host network namespace を丸ごと共有する前提にしない。
- provider server が失敗・順序不正・sentinel 検出を返した時は、Codex を unisolated に再起動せず test を失敗にする。
- public GitHub GET は #272 の credential-bearing GitHub / PR workflow を代替しない。
