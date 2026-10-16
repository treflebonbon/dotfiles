---
type: research
title: Herdr の別 pane からの agent 起動で観測したこと
description: 別 pane から agent を起動・操作したときの観測記録。原因と再現条件は未確認。
tags: [research, herdr, agent]
timestamp: 2026-10-16
---

# Herdr の別 pane からの agent 起動で観測したこと

単一環境での観測を記す。対象ツールの版・設定差と、他環境での再現性は未確認。外部配布の Herdr skill は `apm.yml` で pin されており、この記録は skill 本体を置き換えない。

## 観測した事実

- 新規 pane への `herdr agent start` が `agent_pane_busy` で失敗した。同じ pane で `herdr pane run <pane-id> "claude"` を使うと、Claude を起動できた。
- Claude 起動時に、個別セッションではなく agents ダッシュボードが開いた。
- Codex の初回起動時に `hooks need review` 画面が表示され、最初に送った prompt が通常の依頼入力にならなかった。

## 原因・再現条件は未確認

- `agent_pane_busy` と pane の revision、`--no-focus`、shell の検出状態との関係は未確認。直接起動による回避が他の agent や環境でも有効かも未確認。
- Claude のダッシュボード表示が、起動引数・設定・版のどれに由来するかは未確認。そこから送った prompt の処理先も未確認。
- Codex の確認画面が最初の入力に影響した仕組みと、その画面を Herdr が blocked と認識していたかは未確認。

## 操作時の注意

- `pane run` で直接起動する場合は、対象が空き shell で、前景に別プロセスがいないことを確認する。起動後は agent としての認識と、対象の個別セッションの画面を確認する。
- 確認画面では内容を読み、承認・信頼の判断はユーザーに委ねる。Escape による安全な終了を確認できるまでは、自動で閉じない。
- `agent prompt --wait` は turn 単位の追跡ではない。待機結果に加えて `agent read` で依頼への応答を確認し、timeout や stalled の場合も、受信・実行状況を確認してから再送する。
