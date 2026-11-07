# ADR-0087: R2 object の限定一覧を追加する

- Status: Accepted
- Date: 2026-11-07

## Context

[ADR-0083](0083-add-read-only-cloudflare-inspection.md) は通常の Cloudflare 参照を固定版 CLI 経由に制限し、[ADR-0086](0086-constrain-storage-inspection-definitions.md) は D1 の一問合せ固定 HTTP を例外として認めた。R2 の既存 REST 一覧は応答後に項目を削る前に HTTP/custom metadata を取得するため、object 本文・metadata を要求しない一覧操作には使えない。

Cloudflare R2 は S3 `ListObjectsV2` と local signing による `actions` 制限付きの一時資格情報を提供する。[R2 S3 API](https://developers.cloudflare.com/r2/api/s3/api/)、[temporary credentials](https://developers.cloudflare.com/r2/api/s3/temporary-credentials/)、[local signing example](https://developers.cloudflare.com/r2/examples/authenticate-r2-temp-credentials/)、[ListObjectsV2](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html)。実 service での claim 強制と運用開始は未確認であり、この ADR はそれを承認しない。

## Decision

`cloudflare-inspect --reviewed r2 objects list --definition PATH --sha256 HASH [--limit N]` を追加する。これは D1 固定読取り定義と同様に、本人所有・mode0600 の通常ファイルを一度だけ読み、承認済み hash と同じ bytes を parse する。定義は account、bucket、非空で `/` 終端の prefix、`jurisdiction: "default"`、許可 field、max keys、timeout、credential の残存時間上限を固定する。対象・投影・上限・endpoint の caller override は受け付けない。

操作ごとの人の確認を引き継ぐ。通常の `cf` hook は `--reviewed` を追加せず、reviewed なしの R2 object list は通信前に拒否する。人が agent session 外で保持する bucket 限定 Read の親 credential から、`actions: ["ListObjectsV2"]` と承認 prefix 1件の短期 credential を local signing で発行する。helper は専用の access key ID / secret access key / session token だけを使い、親 credential を取得・発行・更新しない。

これは ADR-0083 と ADR-0086 に対する R2 object list 限定の固定 S3 HTTP 入口の例外である。path-style HTTPS GET、SigV4 region `auto` / service `s3`、RFC3986 query encoding、`Accept-Encoding: identity` を固定し、最大1ページ・最大1 HTTP 試行とする。redirect、retry、credential refresh、credential chain、AWS CLI / SDK、continuation request は使わない。

session token 内の JWT と SHA-256-derived secret、対象・action・path claim、期限を局所整合性として検査する。helper は親鍵を使って JWT 署名を検証しない。この検査を credential の真正性、人の承認、R2 側の claim 強制の証明として説明しない。Cloudflare 側の `actions`・`prefixPaths`・audience 強制は実サービスで未確認とする。

R2 子 process へ渡す環境は3つの専用 credential、必要な proxy/CA、locale に絞り、`CLOUDFLARE_API_TOKEN`、`AWS_*`、`SSLKEYLOGFILE`、endpoint/debug 設定、保存済み認証を継承しない。これは OS 隔離の保証ではない。親 credential を agent の実効環境外に置くことは別途必要な運用前提であり、既存 D1 等の共有 token 配置は変更しない。

S3 XML は既知の namespace・要素・件数・対象・prefix・型・継続状態を検証する。不正な XML、DOCTYPE/ENTITY、未知要素・namespace、圧縮、サイズ超過、型・件数・prefix の不整合では items を保存しない。private 記録には許可 items と匿名化した error class を保存し、credential、JWT、raw XML、元の error body、continuation token は保存しない。公開 JSON には status、returned count、試行数、終了理由、一般的な record locator だけを返す。

## Consequences

- key・size・etag・last_modified の必要な部分だけを private に保存できる。公開出力と hook の operation-specific な確認は既存境界を使う。
- 先頭 page の `IsTruncated` を `truncated` と報告し、続きは取得しない。件数と秒数の上限を走査量・費用の保証とは扱わない。
- 実 R2 での資格情報発行、claim 強制、実 service 受入れ、配備・運用開始は別途対象・操作・件数・時間・費用範囲を決めて承認する。実装の merge はその承認を意味しない。
