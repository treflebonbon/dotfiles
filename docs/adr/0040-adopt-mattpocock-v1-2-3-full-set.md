---
type: decision
title: Matt Pocock skills v1.2.3 の公式 full set を APM で管理する
description: 公式 plugin collection の25 skillを exact commit に固定し、Claude / Codex の共通 managed set として APM から配備する
tags: [adr, apm, skills, mattpocock, claude-code, codex]
timestamp: 2026-08-21
status: accepted
---

# Matt Pocock skills v1.2.3 の公式 full set を APM で管理する

## Context

この repo は Matt Pocock skills を20件の個別 APM dependency として管理していた。公式 v1.2.3 は plugin manifest で25 skillを公開し、`writing-great-skills` を `writing-for-agents` へ rename している。`grill-me` と `teach` も公式 full set に含まれるため、旧 ADR の個別除外を残したままでは、実際の managed set と repo の domain contract が分離する。

APM 0.28.0 は plugin collection を一つの lock record として materialize できる。Claude native plugin や universal installer を併用すると、managed update と discovery の所有者が複数になり、この repo の chezmoi / orphan cleanup 契約と衝突する。

## Decision

1. 公式 `mattpocock/skills` v1.2.3 を commit `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e` に固定する。
2. 25 skill の plugin collection を一つの APM dependencyとして Claude / Codex target に配備する。共有 hub の `.agents/skills` と Claude の `.claude/skills` は同じ payloadを materializeし、Codex は共有 hubを discovery source とする。
3. Matt collection は APM を唯一の配布経路とする。Claude native `enabledPlugins`、universal installer、runtime別の別 pin は導入しない。
4. upstream skill本文は fork / patch せず、repo固有の main flow、permission、secret、write、review の契約は `AGENTS.md`、`CLAUDE.md`、runtime contract、tests の instruction層で調停する。
5. 旧 `grill-me` / `teach` 除外と20件の個別 pinに関する判断は、この ADRで supersedeする。履歴としての旧 ADR本文は書き換えない。full set を配備することと main flowへ自動追加することは別の判断として扱う。
6. future revision は、隔離 runtimeでの lock materialization、frozen install、audit、skill deployment/discovery、workflow contract、chezmoi dry-run を通過した候補だけを明示採用する。初期採用では `@latest` や upstream `main` を使わない。

## Verification

今回の accepted snapshot は次の境界で確認した。

- `tests/apm-runtime.bats`: 10/10 pass。manifestの単一 root dependency、exact commit、`marketplace_plugin` lock record、25 skillの shared hub / Claude deploymentを確認。
- 隔離 runtime の `apm install --frozen --target claude,codex --https`: lock hash不変、25 skill全ての `.agents/skills` / `.claude/skills` directoryを確認。
- 同じ隔離 runtime の `apm audit --ci`: 10/10 pass、driftなし。
- 同じ隔離 runtime で、25 skill全てについて shared hub / Claude skill directoryの pair を照合。さらに `codex debug prompt-input` で共有 hub 由来の model-invoked `writing-for-agents` を確認した。`grill-me` / `teach` など user-invoked skill が Codex の model-visible prompt に出ないのは invocation分類上の境界であり、managed directoryからの明示起動対象としては配備済みと記録する。
- `bats tests/`: 340/340 pass。
- 既存 lock と新 lock の非 Matt dependencyについて、key、resolved commit、resolved ref、version、package type、content hashを比較し差分なし。

## Consequences

- managed set は公式 full set と一致し、Claude / Codex の source pin は一つになる。
- `grill-me` と `teach` は配備されるが、既存の main flowを変える invocation policy は別の workflow migrationで扱う。
- APM lock は plugin collection の一つの recordと、その配備ファイル一覧を持つ。従来の skillごとの Matt recordとは形式が変わる。
- APM / native plugin / universal installerの二重管理を避けるため、既存の orphan cleanup は APM real directoryを所有する契約に従う。

関連: [Issue #169](https://github.com/treflebonbon/dotfiles/issues/169) / [ADR-0002](0002-mattpocock-over-superpowers.md) / [ADR-0010](0010-productivity-skill-audit.md) / [ADR-0022](0022-align-mattpocock-v1-1-workflow.md) / [ADR-0039](0039-update-llm-agents-and-selected-skill-payloads.md) / [skill-harness](../../runtime/skill-harness.md)
