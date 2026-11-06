---
type: decision
title: 限定参照の読取り定義と実行上限を固定する
description: 利用環境が所有する宣言形式の読取り定義を人が確認し、内容と操作ごとの上限を固定する
tags: [adr, cloudflare, permissions, d1, r2]
timestamp: 2026-11-06
status: accepted
---

# 限定参照の読取り定義と実行上限を固定する

[#580](https://github.com/treflebonbon/dotfiles/issues/580) の triage で、2026-11-06 に読取り定義・実行上限・対象範囲・通信経路を合意した。#580 は D1 の限定参照を先行し、R2 は取得禁止を満たす入口と認証契約を設計する [#581](https://github.com/treflebonbon/dotfiles/issues/581) に分ける。以下を実装の契約とし、対応する操作・引数・利用手順は[調査手順](../../runtime/investigation.md)に記載する。

D1 の初期対応は、単一テーブル、明示した列、値の bind、比較条件、固定した並び順、LIMIT からなる狭い宣言形式に限定する。helper が SELECT を生成し、その SELECT または EXPLAIN QUERY PLAN のいずれか1つを選ぶ。JOIN・副問合せ・関数・集計・任意 SQL は初期対象から外す。承認済みの SQL 文字列を広く受理する方式より、取得列と単一 statement を実行前に検証しやすい境界を優先する。

固定読取り定義は利用環境側で管理し、対象・許可列・引数の型や範囲・上限を人が確認する。その内容の SHA-256 を操作時に固定し、不一致を拒否する。定義の変更後は再確認を必要とする。hash の一致は人の承認そのものではなく、既存の操作ごとの確認も維持する。業務固有の名称・対象・スキーマ・定義・値・個別の実行計画は、共通 helper・合成 fixture・公開資料へ持ち込まない。

期待 hash の出所は、人が利用環境の既存エディタ等で定義の内容を確認し、その時点で控えた承認記録とする。agent が実行直前に計算した値だけを承認済み hash として渡すことを、迂回禁止の行動契約で禁じる。所有者・mode の検査は人と同じ uid の agent を区別する保証ではない。helper は1回だけ読み取った同じ生バイト列で hash 照合と parse を行い、承認記録の有無と今回の操作承認は agent が別々に確認する。専用の定義表示モードは初期対象に追加しない。

人が確認する範囲は投影列だけでなく、条件・並び順に使う列と演算子も含む。本文・資格情報等の禁止列は条件・並び順にも使わず、呼出元がこれらを差し替えられない契約とする。

新しい参照操作の返却件数は既定100件・最大1000件、HTTP 試行は1操作につき1回、全体の待ち時間は最大30秒とする。利用側定義でさらに小さく制限できる。返却件数や timeout は、DB の走査量・費用・サーバ側処理の終了を保証しない。暗黙 retry を含む実試行数を制御・記録できない入口を、これらの条件に適合したと扱わない。

D1 の新しい限定参照に限り、helper 内に公式 Query API の固定 HTTP 入口を設ける。[ADR-0083](0083-add-read-only-cloudflare-inspection.md) の同梱 CLI を使う契約への例外を、この操作のために認める。固定版 CLI の command client は retry を0にしているが、HTTP 実試行数を出力せず、redirect の無効化も指定していない。CLI 呼出し数を実 HTTP 数とみなす方式より、helper が retry・redirect を止め、試行開始を記録し、全体期限を管理できる入口を選ぶ。

送信先は `https://api.cloudflare.com/client/v4/accounts/{account_id}/d1/database/{database_id}/query`、method は POST に固定し、検証済みの宣言形式から組み立てた単一 SELECT またはその EXPLAIN QUERY PLAN と bind 値だけを送る。任意 endpoint・SQL・JSON body を呼出元から受理しない。新しい入口も操作ごとの確認を必要とし、未対応・失敗時に生 CLI や別経路へ fallback しない。D1 Read、既存の認証注入、proxy・CA の保持と認証情報の非表示を維持する。利用手順の対応操作一覧は実装と同時に更新し、未実装の段階で実サービス操作を許可しない。

本文・資格情報・個人情報やその生成材料となる列、および R2 の HTTP/custom metadata の取得禁止は維持する。公開出力へ ID/key を混入させず、許可項目の private 保存と公開集計を分ける。実サービスでの受入れ、資格情報の作成・変更、再配備はこの合意に含めない。Read 権限、操作ごとの確認、未対応操作を別経路で代行しない境界は [ADR-0083](0083-add-read-only-cloudflare-inspection.md) と[調査手順](../../runtime/investigation.md)を引き継ぐ。

private 保存は、本人所有・private・symlink なしと検査した `/tmp/codex` 内に helper が作る、業務名を含まない一意の作業 directory に限定する。directory は mode0700、記録は mode0600 の新規通常ファイルとし、既存ファイルを上書きしない。任意保存先や Git による追跡対象判定を追加しない。生成した一般的な保存先 locator は呼出元へ返せるが、資源 ID・業務名・定義の内容は含めない。

実装では固定版 cf の同梱 schema と[公式 Query API](https://developers.cloudflare.com/api/resources/d1/subresources/database/methods/query/)を照合し、文字列配列の params と単一結果の応答契約を採用した。公式では任意の rows_read・rows_written・duration も、この入口では必須とし、欠落や未知・不整合な schema は失敗にする。EXPLAIN は [SQLite の4列構造](https://www.sqlite.org/eqp.html)に従い、id・parent・notused の整数と detail の文字列を採用し、ローカルの SQLite 合成データでも結果列を確認する。detail の内容を解析して費用を推定しない。実サービスの応答と配備済み実体は、このローカル検証だけで確認済みとは扱わない。
