---
type: decision
title: Codex の default subagent を GPT-6 Sol へ切り替える
description: GPT-6 Sol / Luna の一般提供を受け、GPT-5.6 Terra に後継がないことを実リクエストで確認し、subagent 既定モデルを gpt-6-sol へ更新する。main model と minCodex は据え置く
tags: [adr, codex, model, subagent]
timestamp: 2026-09-23
status: accepted
---

# Codex の default subagent を GPT-6 Sol へ切り替える

2026-09-23、OpenAI が GPT-6 Sol と GPT-6 Luna を発表した（[Introducing GPT-6 Sol and Luna](https://openai.com/index/introducing-gpt-6-sol-and-luna/)、[GPT-6 Sol model page](https://developers.openai.com/api/docs/models/gpt-6-sol)、[GPT-6 Luna model page](https://developers.openai.com/api/docs/models/gpt-6-luna)）。GPT-6 ファミリーは Astra（最重要タスク向け flagship）/ Sol（complex coding・agentic workflows 向け）/ Luna（cost-sensitive・high-volume 向け）の3モデル構成であり、GPT-5.6 世代の Sol/Terra/Luna のうち Terra に対応する GPT-6 後継は存在しない。managed config の subagent は現行 `gpt-5.6-terra` を使っており、世代として立ち行かなくなるため見直しが必要になった。

## Decision

- `private_dot_config/codex/config.toml.tmpl` の `[agents].default_subagent_model` を `gpt-5.6-terra` から `gpt-6-sol` へ変更する。`default_subagent_reasoning_effort = "high"` は変更しない。
- `private_dot_config/codex/AGENTS.md`「Codex reasoning effort」節の subagent 既定表記を `gpt-6-sol` / `high` へ更新する。
- managed main model は `gpt-6-astra` / `medium`（設計・レビュー時 `xhigh` 提案の2段階運用）のまま維持する。公式ドキュメントが Astra を引き続き "the most demanding and important projects" 向け flagship と位置づけており、AGENTS.md の既存エスカレーション方針（通常 `medium`、設計・レビューで `xhigh` 提案）と整合するため、Sol への切替は採用しない。
- `minCodex` は `0.155.0` のまま据え置く。理由は次の Verification boundary を参照。
- subagent の切替先は Luna ではなく Sol とする。Luna は "cost-sensitive/high-volume" 向けであり、旧 Terra が担っていた「品質とコストの均衡」役を引き継ぐには役割不一致。過去に subagent を `gpt-5.6-luna` → `gpt-5.6-terra` へ品質目的で切り替えた経緯（[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)）とも整合する。

## Verification boundary

- インストール済み `codex-cli 0.155.1`（pin・floor とも変更前の状態）から実アカウント（ChatGPT 認証、`codex doctor` で `stored ChatGPT tokens: true` を確認済み）に対し、`codex exec -m gpt-6-sol -c model_reasoning_effort=low -s read-only "reply with exactly this token and nothing else: SOL_01551_OK"` と同様の `gpt-6-luna` 版を実行し、いずれも 400 にならず期待トークン（`SOL_01551_OK` / `LUNA_01551_OK`）をそのまま返す実応答を確認した。両モデルとも 0.155.1 の strict config / CLI `-m` 経路で受理されるため、モデル指定のためだけの pin・floor 前進は不要と判断した。
- `codex doctor` で `latest version 0.156.1 available (current 0.155.1)` を確認した。0.156.1 の公式 release note（GitHub Releases）はモデルピッカーへの GPT-6 Sol/Luna 追加と rate-limit 切替文言の更新のみで、セキュリティ・trust boundary 関連の記載がないため、ADR-0047 の floor 判断基準（untrusted project instruction・managed deny-read・credential redaction・remote MCP・Unix shutdown 等）に合致せず `minCodex` は据え置く。
- `tests/codex-config.bats` の managed config 期待値（`assert_codex_managed_values` および2件の merge-preservation fixture）を `gpt-6-sol` へ追従させ、`bun run test`（`bats tests/`）で full suite が通過することを確認した。
- 未検証: aarch64 系での実リクエスト、GPT-6 Sol/Luna の xhigh/max effort 経路、Codex 0.156.1 自体（pin 未変更のため）。

## Consequences

subagent は世代として存続する GPT-6 ファミリー（Sol）へ移行し、GPT-5.6 Terra への依存を解消する。main model の flagship 判断（Astra 維持）は変更しないため、通常作業のコスト構造・エスカレーション運用に影響はない。`gpt-6-sol` は GPT-5.6 世代比で API 価格が半減しており、subagent は品質を落とさずコストが下がる副次効果がある。

関連: [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0047](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
