---
type: decision
title: Claude Code の Advisor tool (experimental) を既定で有効化
description: undocumented な advisor tool を settings.json.tmpl に既定 ON で組み込み、Sonnet 5 executor に Fable 5 advisor を付与する
tags: [adr, claude-code, advisor-tool, experimental]
timestamp: 2026-07-04
---

# Claude Code の Advisor tool (experimental) を既定で有効化

## Status

Accepted (2026-07-04)。2026-07-06、[Issue #13](https://github.com/treflebonbon/dotfiles/issues/13) を受けて `advisorModel` を `fable` から `opus` に変更。Anthropic 公式ドキュメントが Opus 系を主要ユースケースとして推奨している点に合わせた、本 ADR が想定していた低コストな反転（Decision/Consequences 本文は当時の判断記録として変更しない）。

## Context

Anthropic の Advisor tool（`advisor_20260301`、beta）は、実行役の executor モデルが会話全体を読む advisor モデルへ途中で助言を求められる API 機能。Claude Code 本体（インストール済み 2.1.199/2.1.200 バイナリで確認済み）は `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` env var と `advisorModel` 設定でこれを取り込んでいるが、v2.1.200 の GitHub Release Notes に一切記載がない undocumented な機能。

バイナリの文字列解析で以下を確認した:

- env var 未設定でも、内部の段階的ロールアウトフラグ（`tengu_sage_compass2`）により一部セッションはすでに有効化されうる。
- env var を明示すると (a) そのロールアウトフラグをバイパスして強制 ON になり、(b) `advisorModel` の互換性チェック（advisor はベースモデル以上の能力が必要、という catalog 上の rank 比較）も丸ごとスキップされる。
- 緊急停止用に `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` という kill switch が別途存在する。
- 現在の default executor（`"model": "sonnet"` → Sonnet 5）は Sonnet 5 同士では advisor になれず、Opus 4.8 / Opus 4.7 / Fable 5 / Mythos 5 のみが有効な advisor候補（Anthropic 公式ドキュメントの互換表より）。

## Decision

- `private_dot_claude/settings.json.tmpl` に `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL: "1"` と `advisorModel: "fable"` を追加し、全 devcontainer の全セッションで既定 ON にする。
- 緊急停止したい場合は `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` を `~/.claude/settings.local.json`（chezmoi 管理外）またはシェル環境変数で個別に上書きする。
- 既存の experimental env var 3 種（`ENABLE_TOOL_SEARCH` / `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` / `CLAUDE_CODE_NO_FLICKER`）には ADR も rationale コメントも無いが、今回は明示的に ADR を残す。undocumented な機能を共有 infra（chezmoi 配布の `settings.json.tmpl`）に既定 ON で展開する判断は、domain-modeling skill の3条件（元に戻すコストがある／将来の読み手が驚く／本物のトレードオフがある）を満たすため。

## Consequences

- advisor 呼び出しは advisor モデル（Fable 5）のレートで別課金され、コスト・レイテンシが増える。`effortLevel: xhigh` と方向性が重なり、コスト増が二重に積み上がる。
- **データフロー**: advisor tool は会話全体（システムプロンプト・ツール定義・過去のやり取り・ツール結果を含む）を advisor モデル（Fable 5）へ server-side で追加送信する。executor モデルとは別の推論パスにデータが渡ることになるため、全 devcontainer の全セッションに既定適用する今回の判断はこの点も踏まえた上でのものである。
- undocumented 機能のため、将来の claude-code アップデートで env var 名や挙動が変わる、または機能自体が削除されるリスクがある。floor bump 時はこの ADR と [ai-runtimes](../../runtime/ai-runtimes.md) の該当節を再確認する。
- advisor モデルに Fable 5 を選んだが、Anthropic ドキュメントは Opus 系（Opus 4.8 等）を主要ユースケースとして推奨しており、Fable 5 の実績情報は少ない。効果が薄い、またはコストに見合わない場合は `advisorModel` の値を差し替えるだけでよく、この選択自体は容易に反転できる。

関連: [ai-runtimes](../../runtime/ai-runtimes.md)
