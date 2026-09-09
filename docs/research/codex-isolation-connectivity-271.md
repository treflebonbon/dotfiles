---
type: research
title: Codex 隔離実行の最小認証・通信境界
description: Issue 270 の未完了事項である実モデルと読み取り専用 GitHub API の最小通信経路を、Codex 0.153.4 と bubblewrap 0.11.2 について調査した記録。
tags: [research, codex, bubblewrap, github, secrets, network]
timestamp: 2026-09-10
---

# Codex 隔離実行の最小認証・通信境界

対象は [#270](https://github.com/treflebonbon/dotfiles/issues/270) の未完了事項と、その成果を使う [#271](https://github.com/treflebonbon/dotfiles/issues/271) である。#270 の合成 fixture は `--unshare-all` 内で loopback の合成サービスへ接続できることまでを確認した。本調査は、host の HOME、既存の Codex/GitHub 認証、任意の TCP 接続、control socket を隔離プロセスへ公開せずに、実サービスへの最小の経路を作れるかを確認する。調査後、実装した gateway による実サービス接続も実測した。認証値は host gateway のみで使用し、端末・ログ・隔離側の環境やファイルへ出力していない。

## 結論

検証した構成は **サービスごとに 1 個の host 所有 AF_UNIX socket を明示公開し、そこに request allowlist・認証注入を固定した gateway を置く** 構成である。`--unshare-all` を維持し、host network や HOME を共有しない。

| 用途        | 隔離側                                                            | 公開する socket | host 側 gateway          | host への許可範囲                                                                                                              |
| ----------- | ----------------------------------------------------------------- | --------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| モデル      | Codex custom provider → sandbox 内 `127.0.0.1` TCP-to-UDS sidecar | `model.sock`    | Responses 専用 broker    | `POST /v1/responses` のみ。API key 経路は公式 `codex responses-api-proxy` を利用できる。ChatGPT login 経路は別 broker が必要。 |
| GitHub 検証 | `gh` の `http_unix_socket`                                        | `github.sock`   | GitHub read-only gateway | `GET /repos/octocat/Hello-World` のみ。host の gh が既存ログインで取得し、公開 repository 名だけを返す。                       |

socket は互いに別ディレクトリへ置き、各 socket の親ディレクトリだけを `bwrap --ro-bind` する。隔離側に渡す GitHub token は gateway が受理しないダミー値であり、host token、host `GH_CONFIG_DIR`、host `CODEX_HOME`、Git credential helper、Nix daemon socket は mount しない。各 socket は別の handler instance と許可経路を持つ。同じ信頼済み host supervisor のスレッドとして動くが、socket ごとの API は共有しない。

WSL2 の実 bwrap 内で専用 socket ディレクトリを read-only bind し、モデル応答と GitHub GET の両方が成功した。ホスト network namespace の共有は使用していない。

## 確認した前提

この環境で `codex --version` は `0.153.4`、`bwrap --version` は `0.11.2`、`gh version` は `2.96.0` だった。Codex の Nix output は `codex`、実 ELF、`codex-code-mode-host`、`logs_client` と bwrap resource から成り、proxy の独立した executable はない。ただし接続を起こさない `codex responses-api-proxy --help` で、同 proxy が hidden subcommand として起動でき、`--port`、`--server-info`、`--http-shutdown`、`--upstream-url`、`--dump-dir` を持つことを確認した。

bubblewrap の `--unshare-all` は `--unshare-net` を含む。`--share-net` はそれを取り消して host network namespace を保持するため、この用途では使えない。[bubblewrap 0.11.2 manual](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml#L1766-L1775) `--ro-bind` は host path を read-only で隔離側へ bind する。[同 manual](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml#L2025-L2058)

従って host 上の `127.0.0.1:<port>` は、`--unshare-all` した隔離側の loopback ではない。公式 Responses proxy を単に host loopback で起動するだけでは届かず、`--share-net` は host の任意ネットワーク接続まで戻すため要件を満たさない。

## モデル接続

### API key を使える場合

公式の [Responses API proxy](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/responses-api-proxy/README.md#L225-L259) は、権限を持つ host 側プロセスが標準入力から API key を受け、`POST /v1/responses` だけを `https://api.openai.com/v1/responses` へ転送し、Authorization を注入する。他の method/path は 403 にする。listen 先は `127.0.0.1` に固定されている。[実装](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/responses-api-proxy/src/lib.rs#L138-L176)

したがって API key を使う構成では、host に key を保持した `codex responses-api-proxy` を置き、その loopback TCP だけへ接続する model UDS forwarder を host 側に置けばよい。隔離側には、その UDS へ接続する TCP-to-UDS sidecar のみを置く。Codex は次のような一時 `CODEX_HOME` の custom provider で sidecar へ向ける。

```toml
model_provider = "isolation-model"

[model_providers.isolation-model]
name = "isolation model gateway"
base_url = "http://127.0.0.1:<sandbox-port>/v1"
wire_api = "responses"
requires_openai_auth = false
```

`base_url` と `wire_api` は provider schema の設定項目であり、`requires_openai_auth` の既定値は false である。[Codex 0.153.4 schema](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/config.schema.json#L2214-L2265) この profile は隔離側に OpenAI key や既存 login を読ませない。

`--dump-dir` は実モデルの prompt と response を保存するため、本番検証では指定しない。key が host process の memory にのみ存在することと、gateway のログが authorization、request body、response body を保存しないことを受入条件にする。

### 既存 ChatGPT login だけを使う場合

現在の Codex 0.153.4 バイナリには `https://chatgpt.com/backend-api/codex` と `ChatGPT-Account-Id` が含まれる。対応する公式 source では ChatGPT auth 時の provider base URL は `https://chatgpt.com/backend-api/codex` である。[provider source](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/model-provider-info/src/lib.rs#L33-L37) ChatGPT backend client は bearer authorization と `ChatGPT-Account-Id` header を組み立てる。[backend client](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/backend-client/src/client.rs)

このため新しい API key は #270 の実モデル確認に必須ではない。しかし公式 Responses proxy は API key を前提とし、ChatGPT login の auth record を読み、refresh し、account ID を注入する機能は提供しない。親仕様は必要な開発ツール認証を明示選別して渡すことを許容する。ただし今回の実証は host 側に認証を保ち、許可された endpoint のみを公開する方式を採用した。

ChatGPT login を使うなら、host だけが既存 Codex auth を使用し、隔離側からの `POST /v1/responses` を `https://chatgpt.com/backend-api/codex/responses` へ転送する **ChatGPT Responses broker** が必要である。この broker は bearer と account ID を隔離側から受け取らず、次を必ず満たす。

- `POST /v1/responses` 以外を拒否する。
- upstream host と path を固定し、redirect を追わない。
- 認証値、account ID、prompt、response をログ、環境、子プロセスへ出さない。
- 隔離側へ socket 以外を公開しない。今回の prototype は現在有効な access token のみを使い、refresh は実装しない。期限切れは失敗し、host の正規ログインで更新して再試行する。
- broker の停止時は隔離 Codex を失敗にし、direct network への fallback を持たない。

これは Codex が公式に提供する standalone broker ではなく、上記 source を前提にした小規模な新規実装である。最小の実モデル検証に含める対象はこの 1 endpoint に限り、cloud task、MCP、web search、analytics、update check は無効化または隔離 profile から除外する。

Codex の `network_proxy` feature は outer bubblewrap の代替ではない。これは Codex が管理する command sandbox 向けに in-process で proxy を開始する実装であり、既に `--unshare-all` で host network から切れた Codex 本体を host へ接続する standalone bridge にはならない。[NetworkProxySpec](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/src/config/network_proxy_spec.rs#L135-L154)

### Nix の依存取得を限定 egress に通す場合

Codex 0.153.4 の managed network proxy は起動時の `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` を上流 HTTP proxy として読む。`allow_upstream_proxy` の既定値は `true` であり、HTTPS target は `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY` の順に選ぶ。[設定既定値](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/src/config.rs#L150-L169) [上流選択](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/src/upstream.rs#L43-L100) 現行の `features.network_proxy = true` と `dotfiles-secure` profile はこの既定値を維持する。managed requirements/constraints が将来この値を `false` に制約した場合だけ採用されないため、実行時の fetch で確認する。

従って `features.network_proxy = true` と既存の `dotfiles-secure` domain allowlist を維持したまま、Codex 起動前の outer netns 環境に `HTTP_PROXY=http://127.0.0.1:<port>` と `HTTPS_PROXY=http://127.0.0.1:<port>` を置ける。内蔵 proxy は tool child の proxy 環境を自分の loopback listener へ上書きし、その listener から outer listener を上流に選択する。[child 環境の設定](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/src/proxy.rs#L725-L783) したがって outer listener を専用 UDS 経由の host CONNECT gateway にだけ接続させれば、tool に host network や host socket を与えずに Nix fetch を通せる。

Linux sandbox に標準搭載された host bridge は、Codex が host namespace で起動されることを前提に、bwrap 前に fork して host egress を開く。[proxy routing implementation](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/linux-sandbox/src/proxy_routing.rs#L75-L120) その自動 bridge を「Codex 全体を外側 `bwrap --unshare-all` に入れる」launcher の host escape として使うことはできない。一方で本構成の listener は外側 netns 内で明示的に起動する TCP-to-UDS sidecar であり、既存 model gateway と同じく bind したサービス専用 UDS にしか届かない。上流 proxy の env chaining 自体はこの manual sidecar でも機能するが、これは Codex の自動 host bridge ではないため、Nix の実 fetch 1 件と allowlist 外の拒否を必ず同じ launcher で検証する。

この用途では effective mode が既定の `full` のままであることを確認する。`limited` は HTTPS CONNECT を MITM なしでは拒否するため、通常の HTTPS package fetch を通せない。[network proxy README](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/README.md#L116-L121) host gateway は CONNECT の method、destination host、port、解決 IP を allowlist で照合し、redirect、proxy authentication、allowlist 外と DNS 解決失敗を fail closed にする。Codex proxy の domain allowlist は一層目であり、DNS rebinding を完全に防げないことを upstream も明記している。[security notes](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/README.md#L215-L238)

`allow_local_binding` を true にする必要はない。上流 proxy を選んだ接続は direct-target の private-address 判定を通らないため、outer listener が loopback でも接続できる。[connector implementation](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/network-proxy/src/connect_policy.rs#L40-L58) 一方、managed proxy が tool child の `NO_PROXY` を空に上書きするので、tool が outer listener を直接利用する設計にはしない。Codex 本体の custom model loopback gateway には、起動 wrapper 側で `NO_PROXY=localhost,127.0.0.1,::1` を設定し、モデル通信をこの Nix egress chain へ誤送出しない。

## GitHub の単一 read-only GET

#270 の通信前提の実証は、GitHub への書込みを含めない。`GET /repos/octocat/Hello-World` のような公開 metadata の単一 endpoint を固定し、成功、method/path 逸脱の拒否、host token が隔離側の環境・ファイル・ログにないことを確認すれば足りる。private repository を読む必要がある場合も、検証時点では同じ単一 GET path を gateway に固定する。

GitHub CLI は `http_unix_socket` を設定できる。[`gh config` manual](https://cli.github.com/manual/gh_config#L534-L551) そのため GitHub 経路は sandbox 内 TCP listener を増やさず、隔離用の `GH_CONFIG_DIR` だけに次を設定できる。

```bash
GH_CONFIG_DIR=/home/agent/.config/gh \
  gh config set http_unix_socket /run/codex-boundary/github.sock

GH_CONFIG_DIR=/home/agent/.config/gh \
  GH_HOST=github.com GH_TOKEN=broker-placeholder GH_PROMPT_DISABLED=1 \
  gh api repos/octocat/Hello-World --method GET
```

`GH_TOKEN` は GitHub CLI が認証済み request を作るためのダミー値である。host gateway は request の Authorization を捨て、host 所有の限定 token で置き換える。GitHub CLI が使う `go-gh` は Unix domain socket transport を提供する。[go-gh client options](https://github.com/cli/go-gh/blob/v2.13.0/pkg/api/client_options.go#L63-L105) `https://api.github.com` の request であっても socket 側は raw HTTP となるため、TLS と certificate verification は host gateway から `api.github.com` への upstream 接続で行う。[go-gh HTTP client](https://github.com/cli/go-gh/blob/v2.13.0/pkg/api/http_client.go#L40-L69)

gateway は次の固定 policy を持つ。

- `GET` と `HEAD` 以外を拒否する。query、redirect、request body、CONNECT、upgrade を拒否する。
- Host は `api.github.com:443` のみ、path は検証対象の完全一致 1 件のみとする。
- 隔離側の Authorization、Proxy-Authorization、Cookie、任意の `X-Forwarded-*` を削除する。host token だけを Authorization に設定する。
- upstream response は必要な status、headers、body だけを返し、token を含むリクエストを記録しない。
- token は対象 repository と読み取り endpoint に必要な最小権限・有効期限へ制限する。GitHub は credential の最小権限化を推奨し、fine-grained token の endpoint ごとの必要権限を公開している。[GitHub security guidance](https://docs.github.com/en/rest/authentication/keeping-your-api-credentials-secure#limit-the-permissions-of-your-credentials) [permission matrix](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)

## 受入前の実証項目

実装を #271 の本番移行の根拠にする前に、合成値で次を自動化し、その後に明示承認済みの実モデル 1 request と GitHub GET 1 request を同じ境界で行う。

1. `bwrap --unshare-all` 内の Codex と `gh` から、公開した socket 以外の host TCP、host loopback、host Unix socket が利用できない。
2. `model.sock` は `POST /v1/responses` だけを通し、model broker の upstream host/path、method、redirect、logs を検査する。ChatGPT auth を使う場合は refresh を含め、credential value が隔離側・証跡・標準出力・標準エラーに残らない。
3. `github.sock` は固定 GET を 1 回だけ通し、`POST`、別 path、別 host、dummy token の改変、socket 外の経路を拒否する。
4. いずれの gateway も socket close、upstream timeout、TLS error、401/403 時に失敗し、direct network へ fallback しない。
5. 証跡の redact scan は broker の標準出力・標準エラー・保存ログ・Codex JSONL・`gh` config を含める。auth record、host HOME、host `GH_CONFIG_DIR` は scan のためにも隔離側へコピーしない。
6. 通常 Linux と WSL2 の両方で同じ probe を成功させる。#270 の記録は WSL2 のみであり、片方の kernel 名を変更して代用しない。

## 今回の範囲と未解決事項

この調査は #270 の「実サービスの最小認証・通信経路」を具体化するが、実サービスへの接続はまだ実施していない。GitHub の issue/PR 操作、push、Git credential 利用、MCP の認証付き HTTP 接続、任意 repo の API 閲覧、host worktree を入力として選ぶ手順、差分を元 worktree へ戻す契約は対象外である。後二者は #270 の別の未完了事項として、通信境界とは独立して受入条件を定義する必要がある。

## 2026-09-10 の実測

実装は [gateway](../../scripts/secret-isolation-gateway.py)、[worktree 起動 CLI](../../scripts/secret-isolation-worktree.py)、[外部挙動テスト](../../tests/secret-isolation-worktree.bats) にある。

- 独立した public snapshot を同じ絶対 worktree/Git metadata path に置き、専用 Nix store で `nix print-dev-env` と shellHook を実行した。
- 同じ起動内で実 Codex 0.153.4 が hosted model を使用し、子 Python の境界検査、通常コードの編集・build・test・commit、実 gh の認証付き公開 GET、stdio MCP の境界検査を完了した。結果 commit を元の linked worktree へ返却し、host の dummy dotenv が保存されていることも確認した。
- GitHub の別 path と POST、dependency gateway の allowlist 外 host・localhost・別 port を拒否した。
- dependency gateway は `cache.nixos.org:443` だけに CONNECT を許可する。DNS の全回答が public IP であることを確認し、その検証済み IP に接続する。Nix が実際に `nix-cache-info` を取得し専用 store に保存した。CA は明示指定した信頼済み Nix package の公開証明書のみを渡した。
- この dependency fetch は外側隔離内の Nix で測定した。Codex の managed proxy を重ねた経路は上記 source に基づく推論であり、まだ実測結果に含めない。

再現には `SECRET_ISOLATION_REAL_MODEL=1`、`SECRET_ISOLATION_REAL_SERVICES=1`、`SECRET_ISOLATION_REAL_DEPENDENCIES=1` と公開 CA の `SECRET_ISOLATION_CA_BUNDLE` を指定する。最小 GitHub probe は公開 GET だけで、push・PR・private data・共有状態の変更は行わない。これらの実通信は WSL2 上で検証した。Linux VM では合成サービスと worktree transfer を検証し、実サービス認証を持ち込んでいない。

## 共通入口での実測（2026-09-10）

共通 raw entry で hosted model の編集・テスト・commit・返却、および Nix の初回依存取得と Codex managed proxy の連鎖に成功した。上記の proxy 連鎖に関する推論は、[実装・検証記録](raw-codex-isolation-271.md) の実測で更新する。DNS を渡さない構成では Codex の private-address 検査に拒否されたため、同じドメイン allowlist の公開 IP だけを返す専用 resolver を追加した。host DNS と host network は共有していない。
