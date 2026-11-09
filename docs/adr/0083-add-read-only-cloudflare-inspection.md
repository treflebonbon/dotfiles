---
type: decision
title: Cloudflare の調査を Read token と検査入口に限定する
description: 通常の cf を共通 hook から検査入口へ接続し、Read 権限だけで4操作を自動許可する
tags: [adr, cloudflare, permissions, hooks]
timestamp: 2026-11-04
status: accepted
---

# Cloudflare の調査を Read token と検査入口に限定する

2026-11-05 更新: Workers の制限付き過去ログ検索については、[ADR-0084](0084-allow-bounded-workers-log-queries.md) で `Workers Observability Write` の例外を認めた。以下の Read のみという決定は初期採用時の記録とし、その他の操作・実行境界は引き続き適用する。

2026-11-06 更新: D1 の新しい限定参照に限る固定 HTTP 入口の設計上の例外を [ADR-0086](0086-constrain-storage-inspection-definitions.md) で定めた。実装・利用手順の更新前に対応済みとは扱わず、それ以外の操作は同梱 CLI と既存の承認境界を維持する。

公式 `cf` は API の書込みも扱い、読取り専用モードを持たない。通常の Claude Code / Codex に調査を許可するため、[ADR-0073](0073-allow-investigation-commands.md) の操作・出力検査と、[ADR-0077](0077-route-investigation-commands-through-hooks.md) の通常コマンドからの接続を踏襲する。

## 決定

[#568 の Agent Brief](https://github.com/treflebonbon/dotfiles/issues/568#issuecomment-6621729464) と maintainer の「Q1 Read のみ」に従い、token に Write の例外を認めない。初期対象は DO namespace・D1 database・R2 bucket の一覧と Worker scripts の検索の4操作。必要権限は Workers Scripts Read / D1 Read / Workers R2 Storage Read とし、対象 account を限定する。

Workers Logs の `o11y telemetry query` は問い合わせであっても公式仕様が `Workers Observability Write` を要求する。Logs の対象範囲より token の Read のみという境界を優先し、`--reviewed` でも受理しない。[公式 API 仕様](https://developers.cloudflare.com/api/resources/workers/subresources/observability/subresources/telemetry/methods/query/)

既存の `gcloud-inspect-hook` の構文判定を共有し、`cf` と公式別名 `cloudflare` を `cloudflare-inspect` へ書き換える。許可リストと出力検査は helper に集約し、hook に重複させない。既存の `gcloud` / `gh` の契約は維持する。hook 不調時の元コマンド拒否と、helper 不調時に fallback しない条件も引き継ぐ。

初期対象外の参照は、人の確認と ask / prompt を経た `--reviewed` に限る。最初の確認済み追加操作を D1 の metadata 取得 `d1 get` に限定する。未検証の操作を名前や GET という分類だけで安全と推定せず、引数・Read 権限・出力を確認するまで停止する。

CLI はユーザー環境の Nix package で公式 npm `cf@1.0.0-beta.26` と依存関係を固定する。公開日時は 2026-10-29T20:18:01.643Z で、2026-11-09 の更新時点で満7日以上経過している。beta.25 からの更新と既存7操作の schema 照合は [調査・検証記録](../research/update-tools-skills-20261109.md)を参照する。Node 要件は `^22.23.0 || ^24.22.0 || ^26.12.0`、管理下の Node 24.22.1 は適合する。ソースビルドせず公式 npm 配布物を使い、install script を実行しない。helper の版照合と `CF_DELEGATION=1` で、project 内の別版への委譲による pin の無効化を防ぐ。[公式配布情報](https://registry.npmjs.org/cf/1.0.0-beta.26)、[CLI の版の選択](https://developers.cloudflare.com/cf/get-started/)

helper を同じ Nix package に同梱し、自身の実体と同じ immutable package の `cf` を絶対パスで起動する。caller の PATH から実行ファイルを選ばず、版確認には token を渡さない。CLI に渡す認証は環境変数の token だけとし、一時 HOME・空の cwd・限定した環境で起動する。project の `.env`・実行可能設定・保存済みログインと、任意 endpoint・Node の起動オプションを引き継がない。endpoint は public の公式 API に固定し、proxy / CA は保持する。token は出力・ログ・エラーに出さず、既知の機密項目を表示前に除外する。[endpoint 変更の注意](https://developers.cloudflare.com/cf/environment-variables/)

`cf cli search` 本体はローカル index の検索で、docs 検索とは区別する。使用状況 telemetry は無効化し、検索語は初期対象の固定 product 語彙だけにする。

2026-11-05 の振り返りで合意した改善として、単独の `cf --version` と公式別名の版表示を検査入口で扱う。同じ immutable package 内のCLIの実際の版を既存のpinと照合し、成功した値だけを返す。認証情報は渡さず、外部APIは呼ばない。追加引数と `--reviewed` との併用は拒否し、既存のAPI操作・構文・fallbackの境界を維持する。

## 検証と配備

自動検証ではダミーの JSON と CLI を使い、書込みが呼ばれないこと、機密項目除外、エラー処理、構文・引数の保存、両 runtime の許可設定を固定する。実 runtime のダミー検証は opt-in とし、skip を成功扱いしない。token が書込みを拒否することだけを helper の安全性の証明にしない。

実サービスへの接続・Read token の権限・書込みの403は、受入後の live source からの対象限定配備に続く別工程とする。破壊的 API の試行には操作・対象・範囲を明示した承認を要する。今回の実装がその実測を自動承認したものとは扱わない。手順は [調査手順](../../runtime/investigation.md) に集約する。

raw 隔離 Codex の認証・通信境界、任意の interpreter まで遮断する新しい sandbox は対象外。既知のコマンド規則と迂回禁止の行動契約の組合せという既存の保証範囲を維持する。
