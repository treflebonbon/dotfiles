---
type: decision
title: agent teams の opt-in を撤回し、サブエージェント設定の根拠を記録する
description: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS と teammateMode を削除し、SUBAGENT_MODEL=sonnet の維持と _FORCE 未設定の根拠を残す
tags: [adr, claude, subagent, settings]
timestamp: 2026-10-28
status: accepted
---

# agent teams の opt-in を撤回し、サブエージェント設定の根拠を記録する

ユーザーの `/ask-matt` で参照した記事「[When to fold subagents into your main agent loop](https://claude.com/ja/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop)」を基準に、ローカルが管理するサブエージェント関連設定を `/grill-with-docs` で見直した。動機は予防的な棚卸しで、実害の事例はない。

## Decision

- `private_dot_claude/settings.json.tmpl` から `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` と `teammateMode` を削除する。`teammateMode` は teams の表示方式を選ぶ設定で、teams の有効化も通常の subagent の background 実行も制御しない。`AGENT_TEAMS` を外すと効かない休眠設定になるため、同時に外す。再度使うときは必要な設定を足し直す。
- `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` は維持する。これまでこの値の根拠を書いた記録は repo に見つからなかった。親の `model` も `sonnet` で、この override は親のモデルを切り替えても subagent を同じ tier に固定する。変更する理由が見つからないため現状を維持し、コストやレイテンシの比較は行っていない。
- `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` は未設定のままにする。設定すると upstream skill が per-spawn で指定する model を無視してしまい、upstream skill を変更しない方針と衝突する。
- Codex の `default_subagent_model` / `default_subagent_reasoning_effort` は [ADR-0065](0065-adopt-gpt-6-sol-and-luna-as-managed-models.md) が根拠なので変更せず、重複記述もしない。
- `README.md` と `runtime/ai-runtimes.md` の現在の設定説明から `teammateMode` の記述を削除する。`runtime/ai-runtimes.md`（240、327、343、369、389 行付近の changelog 評価）、`docs/research/`、[ADR-0005](0005-advisor-tool-default-enable.md)、[ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md)、[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) にある `teammateMode: auto` や `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` への言及（「この repo は `teammateMode: auto` を使うため直撃する」「既存の experimental env var」など）は、当時の前提の記録として書き換えない。これらは現在の設定を表すものではなく、この ADR が supersede する。

## 記事の基準の位置づけ

記事の基準は、サブエージェントをメインループへ畳み込むことを既定とし、分けるのは次のいずれかの場合に限る。

- 単一ループで測定可能な性能低下がある。
- 並列に進めて結果を捨てられる新しいコンテキストが必要。
- ツール選択やシステムプロンプトの指示が単一エージェントでは矛盾する。

この基準は、任意の委譲と今後ローカルで設計する構成の判断指針とする。Phase Boundary の5択と `Subagent` の条件文（`runtime/skill-harness.md`、`private_dot_claude/CLAUDE.md`、`GLOSSARY.md`）は upstream（matt skills）に準拠するため変更しない。upstream の `implement-spec` と `code-review`、ローカルの peer-refactor skill も変更しない。Phase Boundary は phase 間の委譲判断で、記事はエージェント構成の分割判断という別の軸であり、この基準で Phase Boundary を書き換えない。

## Consequences

今回の実効変更は agent teams の既定 opt-in の撤回だけである。通常の subagent は引き続き使える。委譲の回数、品質、レイテンシが改善するかは未測定で、この ADR は改善を主張しない。

repo 内の `tests/`、`local-skills/`、`runtime/`、`README.md` に、削除で壊れる直接依存は見つからなかった（Codex の read-only レビューと grep で確認）。agent teams を対話で使っていた場合は影響を受けるが、ユーザーは使っていないことを前提とした。`--agent-teams` 引数を使った CLI 全体の動作と、配備済み upstream skill 本体の確認は未実施。

記事の移行手順のうち、評価セットの作成と `implement-spec` の畳み込みは、upstream skill を変更しないため今回は扱わない。
