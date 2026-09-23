---
type: decision
title: Codex の managed model を GPT-6 Sol / GPT-6 Luna へ切り替える
description: GPT-6 Sol / Luna の一般提供を受け、GPT-5.6 Terra に後継がないことを実リクエストで確認する。main model を gpt-6-sol / high、subagent を gpt-6-luna / xhigh へ更新する（人間の明示指示）。minCodex は据え置く
tags: [adr, codex, model, subagent]
timestamp: 2026-09-23
status: accepted
---

# Codex の managed model を GPT-6 Sol / GPT-6 Luna へ切り替える

2026-09-23、OpenAI が GPT-6 Sol と GPT-6 Luna を発表した（[Introducing GPT-6 Sol and Luna](https://openai.com/index/introducing-gpt-6-sol-and-luna/)、[GPT-6 Sol model page](https://developers.openai.com/api/docs/models/gpt-6-sol)、[GPT-6 Luna model page](https://developers.openai.com/api/docs/models/gpt-6-luna)）。GPT-6 ファミリーは Astra（最重要タスク向け flagship）/ Sol（complex coding・agentic workflows 向け）/ Luna（cost-sensitive・high-volume 向け）の3モデル構成であり、GPT-5.6 世代の Sol/Terra/Luna のうち Terra に対応する GPT-6 後継は存在しない。managed config の subagent は現行 `gpt-5.6-terra` を使っており、世代として立ち行かなくなるため見直しが必要になった。

最初の検討では、公式ドキュメントが Astra を引き続き "the most demanding and important projects" 向け flagship と位置づけていることを根拠に、main model は `gpt-6-astra` / `medium` を維持し、subagent だけを `gpt-6-sol` / `high` へ更新する案を採用した。その後、人間から main を `gpt-6-sol` / `high`、subagent を `gpt-6-luna` / `xhigh` にする明示指示を受け、この ADR を上書きして最終決定とする（Sol は Astra より低コストで complex coding・agentic workflows 向けの位置づけであり、xhigh までの reasoning effort に対応する。この判断は人間が下したコスト・レイテンシ対 flagship 品質のトレードオフであり、エージェント側では再検討しない）。

## Decision

- managed main model を `gpt-6-astra` / `medium` から `gpt-6-sol` / `high` へ変更する（`private_dot_config/codex/config.toml.tmpl` の `model` / `model_reasoning_effort`）。
- managed default subagent を `gpt-5.6-terra` / `high` から `gpt-6-luna` / `xhigh` へ変更する（同ファイルの `[agents].default_subagent_model` / `default_subagent_reasoning_effort`）。
- `private_dot_config/codex/AGENTS.md`「Codex reasoning effort」節を新しい既定値に合わせて書き換える。通常の親作業は `gpt-6-sol` / `high`、設計・レビュー開始時に `xhigh` を提案する2段階運用は維持し、通常作業へ戻る際の提案先も `high` にする。subagent は `gpt-6-luna` / `xhigh` に固定する（parent と subagent の effort は独立した選択のまま）。
- `runtime/ai-runtimes.md` の現状サマリ行と「Codex の推論強度と試行」節を新しい既定値（`sol/high` → `sol/xhigh` の2段階、子は `luna/xhigh`）に合わせて書き換える。中間 rung を明示的に設けない旨の記述は、baseline 自体が `high` になったため削除する（もはや skip される中間 rung が存在しない）。
- `minCodex` は `0.155.0` のまま据え置く。理由は次の Verification boundary を参照。

## Verification boundary

- 最初の検討時、インストール済み `codex-cli 0.155.1` の実アカウント（ChatGPT 認証、`codex doctor` で `stored ChatGPT tokens: true` を確認済み）に対し `codex exec -m gpt-6-sol -c model_reasoning_effort=low` / `-m gpt-6-luna -c model_reasoning_effort=low` を実行し、いずれも 400 にならず期待トークン（`SOL_01551_OK` / `LUNA_01551_OK`）を返す実応答を確認した。
- 人間の指示を受けて最終決定した実際の managed 値（`gpt-6-sol` / `high`、`gpt-6-luna` / `xhigh`）についても、同じ `codex-cli 0.155.1` から `codex exec -m gpt-6-sol -c model_reasoning_effort=high` / `-m gpt-6-luna -c model_reasoning_effort=xhigh` を実行し、いずれも 400 にならず期待トークン（`SOL_HIGH_01551_OK` / `LUNA_XHIGH_01551_OK`）を返す実応答を確認した。両モデルとも 0.155.1 の strict config / CLI `-m` 経路でこれらの reasoning effort を受理するため、モデル・effort 指定のためだけの pin・floor 前進は不要と判断した。
- `codex doctor` で `latest version 0.156.1 available (current 0.155.1)` を確認した。0.156.1 の公式 release note（GitHub Releases）はモデルピッカーへの GPT-6 Sol/Luna 追加と rate-limit 切替文言の更新のみで、セキュリティ・trust boundary 関連の記載がないため、[0047-test-quality-floors-through-package-outputs.md](0047-test-quality-floors-through-package-outputs.md) の floor 判断基準（untrusted project instruction・managed deny-read・credential redaction・remote MCP・Unix shutdown 等）に合致せず `minCodex` は据え置く。
- `tests/codex-config.bats` の managed config 期待値（`assert_codex_managed_values`、および3件の merge-preservation / invalid-config fixture。`gpt-5.4`/`gpt-5.5` の legacy model-migration fixture は本変更と無関係のため対象外）を新しい既定値へ追従させ、`bats tests/codex-config.bats` と `bun run test`（`bats tests/`）full suite を再実行して通過を確認した（既知の pre-existing 失敗7件 — dotenv-migration 1件、mattpocock-update-gate 6件 — 以外は成功）。
- 未検証: aarch64 系での実リクエスト、GPT-6 Sol/Luna の max effort 経路、Codex 0.156.1 自体（pin 未変更のため）。task worktree から live HOME への `chezmoi apply` は行っていない。

## Consequences

managed main/subagent とも GPT-6 ファミリー（Sol/Luna）へ移行し、GPT-5.6 Terra および Astra flagship への依存を解消する。通常の親作業の reasoning effort が `medium` から `high` へ底上げされ、設計・レビュー時の上限は従来通り `xhigh` のまま据え置かれる。subagent は `high` から `xhigh` へ底上げされる。いずれも API 価格は GPT-5.6 世代・Astra 比で下がる方向だが、reasoning effort の底上げ自体はレイテンシ・トークン消費を増やす可能性があり、通常作業の体感速度は次回以降の実運用で確認する。

関連: [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [0047-test-quality-floors-through-package-outputs.md](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
