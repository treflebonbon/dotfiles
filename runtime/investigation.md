---
type: concept
title: Google Cloud・Cloudflare・GitHub の調査
description: 既存の認証を使う調査コマンド、設定の機密項目の除外、未対応操作の実行前確認
tags: [gcloud, cloudflare, github, codex, claude-code, permissions]
---

# Google Cloud・Cloudflare・GitHub の調査

通常の Codex と Claude Code は、既存の認証でアクセスできる Google Cloud プロジェクトと GitHub repo を調査できる。private repo も含む。新しいアクセス権の付与や認証設定の変更は、調査許可に含まれない。`codex-worktree` の raw 隔離版は別の認証・通信境界を使い、この入口の対象外。

## Google Cloud

自動調査には `gcloud-inspect` を使う。既存の `gcloud` が PATH に必要。操作とオプションを検証してから CLI を呼び、JSON の既知の機密項目を `[非表示]` に置き換える。

通常の `gcloud <引数>` を、リテラルの引数だけで単独に1回呼んだ場合は、PreToolUse hook（`gcloud-inspect-hook`）が `gcloud-inspect <引数>` へ書換える。許可の判定と機密項目の除外は `gcloud-inspect` が行う。次の入力は書換えず、理由つきで拒否する。拒否後は案内に従って呼び直し、直接の `gcloud` や別の実行方法で迂回しない。

- 複合 shell（`cd … &&`、パイプ、`;`、コマンド置換）: `gcloud <引数>` を単独で1回呼ぶ。
- 展開（`$…`、バッククォート、glob、`~`、`{}`）、環境変数の代入、リダイレクト、改行・コメント: リテラルの引数だけにする。
- 先頭の `--reviewed`: ユーザーの確認後に、明示的な `gcloud-inspect --reviewed …` を使う。

`command gcloud`・`env gcloud`・`/bin/gcloud`・`/usr/bin/gcloud`、および hook の失敗・timeout・未信頼では書換えず、元の command が既存の禁止ルールで拒否される。それ以外の絶対パス・別名・interpreter 経由は技術的には遮断されないが、迂回は禁止する（行動契約。[ADR-0073](../docs/adr/0073-allow-investigation-commands.md) の既存の限界と同じ）。Codex は hook の trust が済むまで hook をスキップするため、配備後は trust 済みであることを確認する。`gh` は書換えない。設計の経緯は [ADR-0077](../docs/adr/0077-route-investigation-commands-through-hooks.md)。

```bash
gcloud-inspect logging read 'severity>=ERROR' --project PROJECT_ID --freshness 1h --limit 50
gcloud-inspect run services describe SERVICE --project PROJECT_ID --region asia-northeast1
gcloud-inspect container clusters describe CLUSTER --project PROJECT_ID --location asia-northeast1
gcloud-inspect compute instances describe INSTANCE --project PROJECT_ID --zone asia-northeast1-a
gcloud-inspect projects get-iam-policy PROJECT_ID
```

初期対応は projects、Logging の logs/sinks/metrics/buckets、Monitoring の dashboards/policies、Cloud Run の services/revisions、GKE の clusters、Compute Engine の instances/networks/firewall-rules、IAM の service-accounts/roles の一覧・設定参照。projects、Cloud Run services、IAM service-accounts の IAM policy 参照と `config list` も扱う。正確なコマンド一覧は `gcloud-inspect --help` で確認する。

初期対応外の読み取りは、対象・コマンド・必要な理由をユーザーへ示して回答を待つ。確認後は、先頭に `--reviewed` を付けた同じ入口を使う。`list`・`describe`・`get-iam-policy`・`read` に限り、CLI の help の `NAME` で正式なコマンドであることを検証してから実行する。引数の検証と機密項目の除外は同じ処理を通る。help を確認できない CLI 版や、未対応の引数構造では実行しない。

```bash
# この操作についてユーザーの確認を得た後に実行する。
gcloud-inspect --reviewed compute disks describe DISK --project PROJECT_ID --zone asia-northeast1-a
```

`--reviewed` を付けること自体をユーザーの承認の代わりにしない。Codex の prompt、Claude Code の ask にも登録する。通常の `gcloud` は引数の並べ方による秘密取得や出力制限の迂回を防ぐため、一括禁止を維持する。`command gcloud`、`env gcloud`、`/bin/gcloud`、`/usr/bin/gcloud` も禁止する。

一覧とログは既定で最大100件。`--limit` は1〜1000を指定できる。`--project`、`--region`、`--zone`、`--location`、`--bucket`、`--service`、`--filter`、`--sort-by`、`--freshness`、`--order` を受理するが、実際に使えるオプションは各 gcloud 操作の仕様に従う。出力形式の変更、flags file、認証切替、HTTP ログの出力などは自動許可しない。API の自動有効化も無効にする。

時系列データは固定した Monitoring API の GET を使う。認証トークンは内部で取得し、コマンド引数・結果・エラーへ出力しない。別の宛先への redirect は追跡しない。

```bash
gcloud-inspect monitoring time-series list \
  --project PROJECT_ID \
  --filter 'metric.type="compute.googleapis.com/instance/cpu/utilization"' \
  --start 2026-10-15T00:00:00Z --end 2026-10-15T01:00:00Z --limit 100
```

開始・終了にはタイムゾーン付きの日時を指定する。1ページの件数は既定100、最大1000。レスポンスに `nextPageToken` があれば、同じ条件に `--page-token TOKEN` を追加して次のページを読む。

## Cloudflare

通常の `cf <引数>` と公式別名 `cloudflare <引数>` は、共通の `gcloud-inspect-hook` が `cloudflare-inspect <引数>` へ書き換える。エージェントは通常のコマンド名から調査でき、操作・引数の許可と機密項目の除外は helper が行う。単独のリテラル引数だけを受理し、複合 shell・展開・代入・リダイレクトなどは Google Cloud と同じく理由つきで拒否する。専用入口の直接呼出しも可能。

一覧・検索として自動許可する API 操作は次の4件。`--page` は1以上、`--per-page` は1〜100（既定100）。コマンドごとの引数は固定版 CLI の確認済みのものだけを通す。Workers の過去ログ検索は後述の制限付き入口を使う。

```bash
cf durable-objects namespaces list --page 1 --per-page 20
cf d1 list --name example
cf r2 buckets list --direction asc --per-page 20
cf workers scripts search --name example
```

`CLOUDFLARE_API_TOKEN` と対象 account の32桁の `CLOUDFLARE_ACCOUNT_ID` を実行環境に安全に注入する。通常の参照は Read 権限だけを使い、過去ログ検索には例外として `Workers Observability Write` が必要になる。token の値をチャット、コマンド履歴、出力、ログに残さない。token がない場合に保存済みのログインへ切り替えない。

token の作成は人が Cloudflare のプロフィール内の API Tokens 画面で custom token を選び、Account 権限の `Workers Scripts: Read`、`D1: Read`、`Workers R2 Storage: Read` を付ける。過去ログ検索を使う場合だけ `Workers Observability Write` を加え、Account Resources を調査対象 account に限定する。作成した値は承認済みの秘密値保管先へ直接登録する。権限付与・token 作成・認証設定の変更は自動調査の許可範囲に含めない。[token 作成手順](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)

### Workers の過去ログ検索

hook 経由の次の操作を自動許可する。`--worker`、`--start`、`--end` は必須。Worker は1つの名前の完全一致、日時はタイムゾーン付き ISO 8601（小数秒はミリ秒まで）で指定する。開始は1970年以降、終了は現在以前、期間は正の長さで最大24時間。`--limit` は1〜1000（既定100）。名前は英数字・ハイフン・アンダースコアの1〜255文字を受理する。`workers.dev` の DNS 名に対する63文字制限は、過去ログ検索には適用しない。[Worker 名の制限](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/#limitations)

```bash
cf o11y telemetry query --worker example --start 2026-11-01T00:00:00Z --end 2026-11-01T01:00:00Z --limit 100
```

この引数は検査入口の制限付き形式であり、生 CLI の引数へそのまま渡さない。helper が `cloudflare-workers` に固定した dataset、`$metadata.service` の完全一致フィルタ、Unix ミリ秒の期間、取得件数、`view: events`、`dry: true` を固定 JSON に組み立て、同梱 CLI の `--body` に渡す。dataset を固定して、同名の R2 バケットなどのログを検索対象から除く。`dry: true` は検索を実行しつつ結果を保存しない API の指定で、CLI の `--dry-run` とは別。呼出元の `--body`、保存済み query ID、任意の dataset・フィルタ・view・account・ページングによる上書きは受理しない。追加の期間は、各呼出しで同じ制約を検査する。

ログ検索 API は `Workers Observability Write` を要求するため、token 自体は Read のみではない。自動許可の境界は helper の操作・引数検査であり、ログ収集設定の変更、保存クエリの作成・削除、リアルタイム監視、その他の書込みには広げない。過去ログが収集されていない Worker の設定も自動変更しない。[API 仕様](https://developers.cloudflare.com/api/resources/workers/subresources/observability/subresources/telemetry/methods/query/)、[採用判断](../docs/adr/0084-allow-bounded-workers-log-queries.md)

### その他の操作と実行境界

`cf cli search` は認証情報を渡さず、`durable objects namespaces`、`d1 databases`、`r2 buckets`、`workers scripts` の固定語彙だけで使う。任意の名前・ドメイン・ID・token は検索語にしない。コマンド検索は同梱 index のローカル処理だが、CLI の使用状況 telemetry は常に `CF_SEND_TELEMETRY=false` と `DO_NOT_TRACK=1` で無効化する。`cf docs search` は今回の許可対象外。

初期対象外の Read 参照は、対象・コマンド・理由を示して人の確認後に `cloudflare-inspect --reviewed` を使う。現行の確認済み追加操作は `d1 get <database-id>`（UUID、任意の `--fields`）のみ。それ以外は確認後も未対応として停止する。追加操作の正式な schema・Read 権限・引数・出力を確認して helper とテストを更新するまで、生 CLI や別経路で代用しない。

```bash
# この操作・対象について人の確認を得た後に実行する。
cloudflare-inspect --reviewed d1 get 01234567-89ab-cdef-0123-456789abcdef --fields name
```

`--reviewed` は両 runtime の ask / prompt の対象で、hook は自動付加しない。過去ログ検索は `--reviewed` を付けても同じ制約を守る。それ以外の作成・更新・削除・deploy・認証変更・秘密値取得・`--force` は拒否する。既知の `vars`・`bindings`・環境変数・secret/token 類・Authorization・Proxy-Authorization・CF-Access-Jwt-Assertion・X-Auth-Key・Cookie を `[非表示]` にし、実 token の文字列反映も除外する。未知の機密値の完全な自動判別は保証しない。

helper と `cf` は同じユーザー環境の Nix package から配布する。helper は自身の実体と同じ immutable package 内の `cf` を絶対パスで起動し、caller の PATH 上の同名 CLI は信用しない。一時 HOME と空の作業ディレクトリで起動し、project の `.env`・実行可能設定・保存済み認証を読ませない。endpoint を公式の public API に固定し、`NODE_OPTIONS`・debug・profile・任意 endpoint の上書きを引き継がない。必要な proxy と CA は保持する。`cf` はユーザー環境の Nix package で exact pin し、helper も token を渡す前に版を照合する。`CF_DELEGATION=1` で project 内の別版への委譲を止める。更新は満7日以上経過した公開版で、schema と検査・配線の検証後に行う。

hook の失敗・timeout・未信頼時は元の `cf` / `cloudflare` を禁止ルールが拒否し、helper 不在・失敗時は別経路へ fallback しない。`command` / `env` と既知の `/bin` / `/usr/bin` の別名も禁止する。任意の絶対パスや interpreter まで完全に遮断する sandbox ではなく、拒否の迂回を禁止する行動契約は引き続き適用する。

自動検証と両 runtime のダミー検証では実 credential・実サービスを使わない。実サービスでの接続と必要な token 権限の確認は、受入・live source からの対象限定配備の後の別工程。書込みの 403 を確かめるために破壊的 API を試す場合も、操作・対象・範囲を示して事前確認を得る。未実施の確認は未確認として引き継ぐ。[初期の採用判断](../docs/adr/0083-add-read-only-cloudflare-inspection.md)、[ログ検索の例外](../docs/adr/0084-allow-bounded-workers-log-queries.md)

## GitHub

次の `gh` の参照コマンドを自動許可する。

- `pr view/list/diff/checks/status`、`issue view/list`
- `repo view/list`、`search code/issues/prs/commits/repos`
- `run view/list`、`workflow view/list`

```bash
gh pr view 42 --repo OWNER/REPO --comments
gh pr diff 42 --repo OWNER/REPO
gh search code 'QUERY' --repo OWNER/REPO
gh run list --repo OWNER/REPO --status failure
gh run view RUN_ID --repo OWNER/REPO --log-failed
```

`gh api` は `rate_limit` を含めて個別確認する。HTTP method や本文で変更操作になり得るため、任意 REST API・GraphQL は今回の自動許可に追加しない。既存の PR・Issue への定型書込みの承認範囲は、それぞれの依頼と既存の契約に従う。

## 未対応操作と機密情報

自動許可対象外の調査操作は、対象・コマンド・必要な理由をユーザーへ示し、実行前に回答を待つ。CLI の引数や実行方法を変えて拒否を迂回しない。Claude Code の auto 判定を、人間による個別確認の代わりにしない。`gcloud-inspect` が未対応を返した場合も、直接の `gcloud` へ自動で切り替えない。

これらのコマンドルールは、任意のプログラム経由の実行まで遮断する技術的な隔離ではない。認識できないラッパーや interpreter を使った迂回も禁止する。この既存の制約は [ADR-0055](../docs/adr/0055-disable-block-reads-outside-working-directories.md) と同じで、通常の runtime の filesystem・network 境界は変更しない。

Secret Manager の秘密値や認証トークン自体の取得は禁止。credential ファイルの直接参照も既存の保護に従う。設定の環境変数、password/token/private key/credential 類、GKE の masterAuth、Compute Engine の metadata items、過去の適用設定などの既知の機密項目を除外する。

通常ログは閲覧できる。ログ本文や未知の設定項目に誤って書かれた秘密値を完全に判別する保証はなく、この混入リスクは受容している。秘密値の意図的な取得や、既知の機密項目の除外を解除する許可として扱わない。
