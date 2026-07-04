---
type: decision
title: mattpocock/skills productivity カテゴリの全4件を棚卸しし handoff / writing-great-skills を追加
description: ADR-0009 の grilling 訂正を機に upstream README 全体（engineering + productivity、両 invocation 種別）を apm.yml と突き合わせて棚卸しした。engineering は完全一致、productivity の未検討3件（handoff/teach/writing-great-skills）を精査し、handoff と writing-great-skills を追加、teach はスコープ外として非導入とする
tags: [adr, skills, mattpocock, apm]
timestamp: 2026-07-04
---

# mattpocock/skills productivity カテゴリの全4件を棚卸しし handoff / writing-great-skills を追加

## Status

Accepted (2026-07-04)

## Context

[ADR-0009](0009-add-grilling-skill.md) で `grilling` の除外が前提の誤りだったと判明したのを受け、mattpocock/skills 依存全体に同種の見落としがないか棚卸しした。upstream README（183行、`gh api repos/mattpocock/skills/contents/README.md` で全文取得）の Reference セクションを `apm.yml` と突き合わせた結果:

- **Engineering**（User-invoked 7件 / Model-invoked 7件）: 全14件が導入済みで完全一致。見落としなし。
- **Productivity**（User-invoked 4件: `grill-me` / `handoff` / `teach` / `writing-great-skills`、Model-invoked 1件: `grilling`）: `grilling` は ADR-0009 で導入済み。`grill-me` は [ADR-0002](0002-mattpocock-over-superpowers.md) で「軽量化のため pin を除去」と明示決定済み（`grill-with-docs` が codebase ありのケースをカバーするため妥当な scope 判断）。残る `handoff` / `teach` / `writing-great-skills` の3件は、リポジトリ内のどの ADR にも comment にも一度も登場しておらず、検討された形跡がなかった。

3件それぞれの SKILL.md を取得して内容を精査した:

- **`handoff`**: 会話をハンドオフ文書に圧縮し別 agent に引き継ぐ。既存導入済みスキルと機能重複なし。
- **`teach`**: カレントディレクトリを個人学習用の stateful ワークスペース（`MISSION.md` / `lessons/*.html` 等）として扱う。dotfiles の「設計→実装ワークフロー」とは無関係で、リポジトリのディレクトリを学習ワークスペース化する用途とも噛み合わない。
- **`writing-great-skills`**: skill 執筆の語彙・原則（leading word / 情報階層 / pruning / premature completion 等）のリファレンス。既存の `anthropics/skills/skill-creator`（interview→draft→eval→iterate の**プロセス**)とは層が異なり重複しない。このリポジトリは `local-skills/` を自前で保守し、skill/prompt 品質を扱うスキル（`empirical-prompt-tuning` / `harness-feedback` / `md-agents-review` / `md-claude-review`）を既に多数抱えており、skill 執筆時の共有語彙として価値がある。

## Decision

- `apm.yml` に `mattpocock/skills/skills/productivity/handoff` と `mattpocock/skills/skills/productivity/writing-great-skills` を追加する。
- `teach` は「設計→実装ワークフロー」のスコープ外と判断し、意図的に非導入のままとする。将来 dotfiles とは別の個人学習用途が生まれた場合に再検討する。
- `cd ~ && apm lock` → `apm install`（配備を先に済ませ `deployed_files`/`deployed_file_hashes` を lock へ反映）→ `chezmoi re-add apm.lock.yaml` の順で反映した（[skill-harness](../../runtime/skill-harness.md) に明記された正しい手順。ADR-0009 の作業では順序を誤り drift を起こしたため、今回は手順通りに実施）。

## Consequences

- `handoff` / `writing-great-skills` は `~/.claude/skills/` と `~/.agents/skills/` に配備済みで、`tests/apm-runtime.bats` 全6件も通過を確認した。
- mattpocock/skills 依存は Engineering 全件 + Productivity のうち `grilling`/`handoff`/`writing-great-skills` を導入、`grill-me`/`teach` を意図的に除外、という状態が確定した。今後 upstream に新規 skill が追加された場合も、この2カテゴリ・2 invocation 種別の対応表で再棚卸しできる。

関連: [ADR-0009](0009-add-grilling-skill.md) / [ADR-0002](0002-mattpocock-over-superpowers.md) / [skill-harness](../../runtime/skill-harness.md)
