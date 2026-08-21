---
type: decision
title: Matt Pocock v1.2.3 の workflow semantics を local contract へ採用する
description: 公式 v1.2.3 の frontier grilling、phase boundary、prototype lifecycle を採用し、repo 固有の安全境界と Builder-Evaluator 契約を instruction 層で調停する
tags: [adr, skills, mattpocock, workflow, grilling, prototype, safety]
timestamp: 2026-08-21
status: accepted
---

# Matt Pocock v1.2.3 の workflow semantics を local contract へ採用する

## Context

[ADR-0040](0040-adopt-mattpocock-v1-2-3-full-set.md) で公式 `mattpocock/skills` v1.2.3 の full set を APM 管理へ移行した。上流の v1.2.3 は skill の追加だけでなく、grilling の一問一答から frontier round への変更、phase boundary の5択、logic prototype の single self-contained HTML 化を含むため、旧 pin のままでは workflow semantics が配備物と分離する。

一方、この repo には worktree/branch 単位の Builder-Evaluator、Contract / Verification Matrix、Claude / Codex の別指示層、外部書込み・secret・permission の安全境界が既にある。外部 skill 本文を fork せず、repo の instruction 層で公式 semantics と local override を明示する必要がある。

## Decision

1. `grilling` は frontier round を採用する。各 round では依存関係が解決済みの全 decision を推奨付きで提示し、人間の回答を待つ。環境から得られる facts は探索してよいが、未回答の decision は推測して進めない。`ui-grill-with-docs` も同じ semantics を使い、visual comparison が必要な質問だけ disposable mockup を添える。
2. phase boundary の公式選択肢を `Continue → /clear → /handoff → Subagent → /compact` の順で採用する。同じ harness / directory の relevant context は `/compact`、新しい harness / directory / repo / colleague への portability が必要な場合だけ `/handoff` とする。smart zone の目安は ~150k tokens とし、`Continue` を最初に検討する。
3. Builder-Evaluator の local override は維持する。同一 worktree/branch では ticket をまたいで実装し、ticket 境界で同じ harness / directory の context を残す場合は `/compact` を使う。`tdd`、commit、`code-review`、full verification、worktree/branch 単位の `to-pr` 一回という既存の verification boundary は変更しない。
4. model-invoked discipline は current repository の実装契約内で動く。外部書込みは親 Contract または明示的に起動した user-invoked skill の承認範囲に限る。機密情報・credential・CI secret の読み出し、出力、commit、無断変更と、権限拡大・permission bypass の自己判断を禁止する。
5. `prototype` の logic path は single self-contained HTML とする。build / server 不要、inline pure logic、free-play、guided walkthroughs、操作後の全 state 表示を必須の lifecycle とする。決定を本実装へ反映した後も prototype 全体は throwaway branch に primary source として残し、implementation issue から参照する。main branch には決定だけを残す。
6. `AGENTS.md` と `CLAUDE.md` は別管理を維持する。共有する workflow / safety contract は双方で整合し、Codex 系と Claude Code の runtime-specific な差分は各指示層へ残す。
7. この ADR は、旧一問一答・120k smart-zone・旧 phase boundary の local contract と、ADR-0022 の `grill-me` / `teach` 非導入判断、ADR-0037 の旧20-skill pin 据え置き理由を workflow migration の範囲で supersede する。旧 ADR 本文は履歴として書き換えない。full set の配備判断自体は ADR-0040 が正本である。

## Consequences

- Planner は frontier round ごとに人間の decision を受け取り、Builder-Evaluator は same worktree/branch を保ったまま ticket を連続処理できる。
- 同じ harness / directory で context を維持する phase boundary は `/compact` が既定になり、`/handoff` は portability のために限定される。
- `grill-me`、`teach`、`writing-for-agents` は公式 managed set として配備される。旧除外・旧 `writing-great-skills` 名は history と cleanup contract にだけ残る。
- prototype の HTML は main の production artifact ではなく、検証済み decision を説明する primary source として throwaway branch に保管される。
- 4値 verdict gate、evidence JSON schema、外部 skill の fork、permission mode ごとの workflow 分岐は導入しない。

## Verification

- `tests/workflow-contract.bats` が frontier round、phase boundary、Builder-Evaluator、safety、prototype lifecycle、AGENTS / CLAUDE 分離、supersede 記録を検証する。
- `tests/apm-runtime.bats` が v1.2.3 full set の APM materialization を検証する。
- upstream の v1.2.3 [phase boundaries](https://github.com/mattpocock/skills/blob/6acc160e4e0cd062dbbbd7a1b26ae92855edf07e/skills/engineering/ask-matt/PHASE-BOUNDARIES.md)、[grilling](https://github.com/mattpocock/skills/blob/6acc160e4e0cd062dbbbd7a1b26ae92855edf07e/skills/productivity/grilling/SKILL.md)、[logic prototype](https://github.com/mattpocock/skills/blob/6acc160e4e0cd062dbbbd7a1b26ae92855edf07e/skills/engineering/prototype/LOGIC.md) と照合した。

関連: [Issue #171](https://github.com/treflebonbon/dotfiles/issues/171) / [ADR-0022](0022-align-mattpocock-v1-1-workflow.md) / [ADR-0037](0037-update-llm-agents-and-compatible-skill-pins.md) / [ADR-0040](0040-adopt-mattpocock-v1-2-3-full-set.md) / [skill-harness](../../runtime/skill-harness.md)
