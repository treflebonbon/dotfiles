---
type: decision
title: grilling skill (productivity カテゴリ) を追加し ADR-0004 の前提誤りを訂正
description: 上流 README を一次情報で確認した結果、grilling は README 非掲載ではなく productivity/Model-invoked に明記された grill-with-docs/grill-me の共通ループだったと判明。ADR-0004 の除外判断を訂正し apm.yml に追加する
tags: [adr, skills, mattpocock, apm]
timestamp: 2026-07-04
---

# grilling skill (productivity カテゴリ) を追加し ADR-0004 の前提誤りを訂正

## Status

Accepted (2026-07-04)

## Context

[ADR-0004](0004-fill-mattpocock-gaps.md) は `grilling` を「README 非掲載の unlisted、fail-soft で model が inline 対話に委譲」として意図的に非導入とした。しかし `grill-with-docs` スキル実行時に `/grilling` を呼ぼうとしても該当スキルが存在せず、この前提を上流 README の一次情報で確認し直した。

`gh api repos/mattpocock/skills/contents/README.md` で本文を直接取得したところ、`grilling` は **Productivity カテゴリの Model-invoked** に明記されていた:

> **grilling** — Interview the user relentlessly about a plan or design until every branch of the decision tree is resolved. **The reusable loop behind `grill-me` and `grill-with-docs`.**

つまり `grilling` は非掲載ではなく、この repo が既に導入している `grill-with-docs` が依存する共通ループそのものであり、ADR-0004 の前提は誤りだった（`engineering/` カテゴリのみを走査し `productivity/` カテゴリの Model-invoked 項目を見落としたと見られる）。同じ環境内の別 repo（`hermes-fly`）は `productivity/grilling` を正しく導入済みで、`docs/agents/MATTPOCOCK-SKILLS.md` 相当のドキュメントにも出所として明記していた。

## Decision

- `apm.yml` に `mattpocock/skills/skills/productivity/grilling` を追加する（Model-invoked セクション末尾）。
- `apm.yml` 内の該当コメントから「grilling も非導入 = fail-soft」の記述を削除し、本 ADR を参照するよう訂正する。
- `cd ~ && apm lock` でロックファイルを再生成し、`chezmoi re-add apm.lock.yaml` でソースへ取り込んだ上で `chezmoi apply` を実行し、`run_onchange_after_apm-install.sh.tmpl`（`apm install --frozen` + `apm prune`）を発火させて実体を配備した。
- `grill-me`（productivity/User-invoked、no-codebase 向けの `grill-with-docs` 相当）は [ADR-0002](0002-mattpocock-over-superpowers.md) が「軽量化のため pin を除去」と明示的に決めた対象であり、意図的に除去されたままとする。これは `grilling`（Model-invoked の共通ループ、今回の訂正対象）とは別の判断であり、本 ADR では扱わない。

## Consequences

- `grill-with-docs` / `ask-matt` が参照する `/grilling` セッションが実際に解決可能になった。`.claude/skills/grilling` / `.agents/skills/grilling` に配備され、Claude Code のスキル一覧にも表示されることを確認済み。
- `apm.yml` の mattpocock ブロックにあった判断根拠のコメントは、上流の一次情報（README）を確認しないまま記述された誤りだったと判明した。今後 upstream 由来 skill の promoted/unlisted 判定をコメントに残す際は、README 全文（複数カテゴリ）を確認してから記述すること。
- Codex 向けには `~/.codex/skills/grilling` は配備されない。これは他の Model-invoked skill（`domain-modeling` 等）と同じ挙動で、Codex は `~/.agents/skills/` を直接読むためのものであり異常ではない。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [ADR-0007](0007-split-okf-by-cross-repo-value.md) / [skill-harness](../../runtime/skill-harness.md)
