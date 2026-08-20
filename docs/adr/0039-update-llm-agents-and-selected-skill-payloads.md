---
type: decision
title: llm-agents snapshot と selected Agent Skill payload を更新する
description: llm-agents.nix の trust/sandbox 修正を含む snapshot と、実体が変わる APM skill だけを一つの検証済み更新単位として採用し、Matt Pocock workflow migration は分離する
tags: [adr, nix, llm-agents, apm, skills, claude-code, codex]
timestamp: 2026-08-20
status: accepted
---

# llm-agents snapshot と selected Agent Skill payload を更新する

2026-08-20 の調査と grilling で、現行の「導入済み AI ツールセット」と「導入済み Agent Skill セット」を、互換性を確認した一つの更新単位として採用した。

## Decision

- `llm-agents.nix` は exact snapshot `20766586959e0dcc2f9e7cff6d49b0c710de30d6` を採用する。
- `minClaudeCode` は `2.1.237`、`minCodex` は `0.148.0` へ引き上げる。Antigravity CLI `1.1.16` は snapshot に追従し、Copilot CLI / RTK / APM は品質 floor を変更しない。
- APM は selected payload が実際に変わった3 dependencyだけを lock 更新する。Modern Web Guidance、Remotion、Orca `orca-cli` はそれぞれ `460e5536`、`21320596`、`5ca747da` に進め、revision だけが進み selected payload が不変の PDF、Shadcn、find-skills、Orca `computer-use` / `orchestration` は現行 lock を維持する。Impeccable の validated pin と Matt Pocock の pin も維持する。
- 一つの更新単位に含めるのは llm-agents snapshot、AI CLI floor、selected APM lock、対応する tests / ADR / runtime 文書である。Matt Pocock `v1.2.3` の `writing-great-skills` → `writing-for-agents`、grilling、prototype、phase boundary の変更は別 workflow migration とする。
- 対応 system は `x86_64-linux`、`aarch64-linux`、`aarch64-darwin` の3 systemを維持し、`x86_64-darwin` は再導入しない。
- `nix flake check --all-systems`、3 system deep evaluation、Linux host smoke、APM frozen/audit、Design Hook compatibility gate、Claude/Codex smoke がすべて green になったことを確認した。
- 全 gate 通過後に `chezmoi apply` と `apm install --frozen` を実行して source を実環境へ反映し、host smoke で最終状態を確認する。
- 実装は topic worktree で Conventional Commit まで行う。topic branch の push と PR 作成は本作業には含めず、別途 `/to-pr` が呼ばれたときに行う。

## Consequences

更新理由と検証境界は本 ADR と [調査ノート](../research/llm-agents-and-apm-update-2026-08-20.md) が持つ。[ADR-0037](0037-update-llm-agents-and-compatible-skill-pins.md) は 2026-08-18 候補の履歴として保持するが、今回の snapshot / floor / selected payload の判断については本 ADR が supersede する。managed session の home filesystem が read-only のため、`chezmoi apply` と live APM install は完遂できず、実環境への反映はこの commit の後段で行う。

Linux host smoke は候補 shell の package version と各 CLI の version/help 境界を確認し、Claude/Codex smoke は候補 binary で完了した。aarch64-darwin は Linux host からの derivation 評価までを検証境界とし、実機動作確認とは扱わない。

Matt Pocock migration は、現行の `AGENTS.md`、`runtime/skill-harness.md`、local skill override、質問 UX、phase boundary と照合する別 ADR / workflow として設計する。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md) / [ADR-0037](0037-update-llm-agents-and-compatible-skill-pins.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
