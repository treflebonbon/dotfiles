---
type: decision
title: Workers の過去ログ検索に限り Observability Write を認める
description: Worker・期間・件数を検査した過去ログ検索だけを自動許可する
tags: [adr, cloudflare, permissions, logs]
timestamp: 2026-11-05
status: accepted
---

# Workers の過去ログ検索に限り Observability Write を認める

Workers の障害調査で過去ログを検索できるよう、[ADR-0083](0083-add-read-only-cloudflare-inspection.md) の「Read 権限のみ」に例外を加える。ログ検索 API は `Workers Observability Write` を要求するため、この権限を認め、`cloudflare-inspect` が受理する操作を制限する。[公式 API 仕様](https://developers.cloudflare.com/api/resources/workers/subresources/observability/subresources/telemetry/methods/query/)

対象 Worker とタイムゾーン付きの開始・終了日時を必須にする。1回の期間は最大24時間、取得件数は既定100件・最大1000件とし、検査を通った過去ログ検索だけを自動許可する。呼出元の任意 JSON や保存クエリの指定で制約を変更させず、検査入口が検索条件を組み立てる。

検索する dataset は `cloudflare-workers` に固定し、Worker 名の完全一致フィルタと併用する。dataset の省略は全 dataset の検索になるため、同じ名前を持つ R2 バケットなどのログを取得しないよう、検査入口で必ず指定して上書きも認めない。

ログ収集設定の変更、保存クエリの作成・削除、リアルタイム監視、その他の書込みは対象外。token 自体の権限と helper の操作制限は別の境界であり、token が Read のみとは説明しない。権限付与・token 作成・認証設定の変更はこの実装に含めず、実サービスの検証は受入・live source からの対象限定配備の後に行う。
