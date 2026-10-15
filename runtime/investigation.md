---
type: concept
title: Google Cloud と GitHub の調査
description: 既存の認証を使う調査コマンド、設定の機密項目の除外、未対応操作の実行前確認
tags: [gcloud, github, codex, claude-code, permissions]
---

# Google Cloud と GitHub の調査

通常の Codex と Claude Code は、既存の認証でアクセスできる Google Cloud プロジェクトと GitHub repo を調査できる。private repo も含む。新しいアクセス権の付与や認証設定の変更は、調査許可に含まれない。`codex-worktree` の raw 隔離版は別の認証・通信境界を使い、この入口の対象外。

## Google Cloud

自動調査には `gcloud-inspect` を使う。既存の `gcloud` が PATH に必要。操作とオプションを検証してから CLI を呼び、JSON の既知の機密項目を `[非表示]` に置き換える。

```bash
gcloud-inspect logging read 'severity>=ERROR' --project PROJECT_ID --freshness 1h --limit 50
gcloud-inspect run services describe SERVICE --project PROJECT_ID --region asia-northeast1
gcloud-inspect container clusters describe CLUSTER --project PROJECT_ID --location asia-northeast1
gcloud-inspect compute instances describe INSTANCE --project PROJECT_ID --zone asia-northeast1-a
gcloud-inspect projects get-iam-policy PROJECT_ID
```

初期対応は projects、Logging の logs/sinks/metrics/buckets、Monitoring の dashboards/policies、Cloud Run の services/revisions、GKE の clusters、Compute Engine の instances/networks/firewall-rules、IAM の service-accounts/roles の一覧・設定参照。projects、Cloud Run services、IAM service-accounts の IAM policy 参照と `config list` も扱う。正確なコマンド一覧は `gcloud-inspect --help` で確認する。

一覧とログは既定で最大100件。`--limit` は1〜1000を指定できる。`--project`、`--region`、`--zone`、`--location`、`--bucket`、`--service`、`--filter`、`--sort-by`、`--freshness`、`--order` を受理するが、実際に使えるオプションは各 gcloud 操作の仕様に従う。出力形式の変更、flags file、認証切替、HTTP ログの出力などは自動許可しない。API の自動有効化も無効にする。

時系列データは固定した Monitoring API の GET を使う。認証トークンは内部で取得し、コマンド引数・結果・エラーへ出力しない。別の宛先への redirect は追跡しない。

```bash
gcloud-inspect monitoring time-series list \
  --project PROJECT_ID \
  --filter 'metric.type="compute.googleapis.com/instance/cpu/utilization"' \
  --start 2026-10-15T00:00:00Z --end 2026-10-15T01:00:00Z --limit 100
```

開始・終了にはタイムゾーン付きの日時を指定する。1ページの件数は既定100、最大1000。レスポンスに `nextPageToken` があれば、同じ条件に `--page-token TOKEN` を追加して次のページを読む。

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

Secret Manager の秘密値や認証トークン自体の取得は禁止。credential ファイルの直接参照も既存の保護に従う。設定の環境変数、password/token/private key/credential 類、GKE の masterAuth、Compute Engine の metadata items、過去の適用設定などの既知の機密項目を除外する。

通常ログは閲覧できる。ログ本文や未知の設定項目に誤って書かれた秘密値を完全に判別する保証はなく、この混入リスクは受容している。秘密値の意図的な取得や、既知の機密項目の除外を解除する許可として扱わない。
