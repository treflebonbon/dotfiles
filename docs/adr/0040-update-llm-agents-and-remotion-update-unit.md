---
type: decision
title: llm-agents snapshot と Remotion payload を一つの更新単位として採用する
description: llm-agents の品質 floor と実体が変わる Remotion payload を一つの atomic update unit として採用し、Impeccable と Matt Pocock / APM main の変更は別境界に保つ
tags: [adr, nix, llm-agents, apm, remotion, claude-code, codex, antigravity]
timestamp: 2026-08-21
status: accepted
---

# llm-agents snapshot と Remotion payload を一つの更新単位として採用する

2026-08-21 の調査と grilling で、導入済み AI ツールセットと導入済み Agent Skill セットのうち、同じ互換性ゲート・検証結果・配備境界・rollback 境界を共有する変更だけを一つの更新単位として採用することを決めた。

## Decision

- `llm-agents.nix` は exact snapshot `d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da` を採用する。
- Claude Code の quality floor は `2.1.238`、Codex は `0.149.0` とする。Antigravity CLI `1.1.17` は snapshot に追従するが、品質 floor は新設しない。
- APM は stable `0.28.0` を維持し、selected payload が変わる Remotion だけを `7fc6dea333869e23f58bf9e9861010e9ba589e5e` へ進める。revision-only の dependency は現行 pin を維持する。
- 対応 system は `x86_64-linux`、`aarch64-linux`、`aarch64-darwin` の3 systemを維持する。
- 実装の正本は Nix flake / lock、`modules/ai.nix`、`apm.yml` / `apm.lock.yaml` とし、配備先を直接編集しない。

## Verification boundary

- Nix source gate は exact snapshot、package metadata、quality-floor assertions、3 system evaluation を検証する。
- CLI gate は既存の Claude/Codex trust・config 契約に加え、候補の version / startup smoke を検証する。
- APM gate は隔離 runtime layout の frozen install、lock no-rewrite、audit、Remotion selected payload の materialization / discovery を検証する。
- いずれかの core source gate が実際に失敗した場合、この更新単位は採用済みとみなさず、旧 source pin を fallback とする。Remotion だけ、または CLI だけを部分採用しない。managed session の実行制約で binary smoke などが未確認になった場合は、source gate の成功と分けて verification record に明記し、未確認の live behavior を保証したとは主張しない。
- managed session が read-only の場合、source gate を弱めず `chezmoi apply` と live discovery は未確認として記録する。

## Deliberately separate

- Impeccable の selected payload / Design Hook compatibility gate は別の更新単位とする。hook の runtime 契約が異なるため、この変更では pin を動かさない。
- Matt Pocock workflow migration（`writing-great-skills` → `writing-for-agents`、wizard / phase boundary 等）は別の workflow 更新とする。既存の skill 名とローカル override 契約をこの変更で移行しない。
- APM main の trust-bin / no-trust-bin 変更は unreleased behavior のため別評価とし、`0.28.0` から動かさない。

## Consequences

この境界により、snapshot の sandbox / MCP / session 修正と Remotion の selected payload 変更を同じ verification / rollback 証跡で扱える。一方、上流の revision-only 更新を自動的に追従しないため、次回更新時に別途 payload の実体差分を確認する必要がある。

関連: [issue #163](https://github.com/treflebonbon/dotfiles/issues/163)、[ticket #164](https://github.com/treflebonbon/dotfiles/issues/164)、[ticket #165](https://github.com/treflebonbon/dotfiles/issues/165)、[ticket #166](https://github.com/treflebonbon/dotfiles/issues/166)、[ADR-0039](0039-update-llm-agents-and-selected-skill-payloads.md)
