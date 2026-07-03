---
type: decision
title: mattpocock 移行後の穴埋め（上流スキル追加 + to-pr マルチランタイム skill）
description: 実装オーケストレーション / レビュー / 診断の上流 skill を追加し、実装後のブラウザ AC 検証 + PR 作成を軽量 chezmoi ローカル skill (to-pr) で補完する
tags: [adr, skills, mattpocock, antigravity, chezmoi, to-pr]
timestamp: 2026-07-03
---

# mattpocock 移行後の穴埋め（上流スキル追加 + to-pr マルチランタイム skill）

## Status

Accepted (2026-07-03)

## Context

[decisions/2026-07-02-mattpocock-over-superpowers](2026-07-02-mattpocock-over-superpowers.md) の軽量化で、移行前の旧ワークフロー基盤が担っていた 3 領域のうち以下が抜けた:

- **ブラウザ AC 検証**（旧 `active-evaluator`）— `tdd` はコードの behavior test のみ
- **実装後の PR 成果物**（旧 `finalize-epic`）— 上流 `implement` すら末尾は commit-to-branch で PR を作らない
- **実装オーケストレーション / レビュー / 診断** — 上流 `implement` / `code-review` / `diagnosing-bugs` が未導入

加えて、インストール済みの `grill-with-docs` / `triage` が未導入の `/domain-modeling` に委譲する**依存の抜け**があった。

## Decision

- `apm.yml` を上流 README の promoted セット（User-invoked / Model-invoked の公式分類）に整合させる:
  - User-invoked: `setup-matt-pocock-skills` / `grill-with-docs` / `to-prd` / `to-issues` / `triage` / `ask-matt` / `improve-codebase-architecture`
  - Model-invoked: `tdd` / `code-review` / `diagnosing-bugs` / `domain-modeling`（依存の抜け修正）/ `codebase-design` / `prototype` / `research`
  - ワークフローチェーンは **`grill-with-docs → to-prd → to-issues → triage → to-pr`**。実装フェーズに user-invoked skill は無く、model-invoked 層が自動発火する（上流ルール: user-invoked は他の user-invoked を呼ばない）
  - 非導入: `implement` / `resolving-merge-conflicts`（README 非掲載の unlisted。`implement` は一度導入したが model-invoked 発火で冗長な5行の糊と判明し除去）、`grilling`（fail-soft、model native に委譲）
- `apm.yml` `targets` は `claude` / `codex`（apm の `install` は `antigravity` target 非対応）。ただし apm は全 skill を APM-native の共有ハブ `~/.agents/skills/` へ target 非依存で materialize し、そこが Antigravity のグローバル skill dir でもあるため、追加スキルは target 指定なしで 3 ランタイムに可視
- 実装後のブラウザ AC 検証 + PR 作成は、軽量 chezmoi ローカル skill **`to-pr`** で補完する:
  - `local-skills/to-pr/` を SoT に、`run_onchange_after_deploy-local-skills.sh.tmpl` が `~/.agents/skills` / `~/.claude/skills` / `~/.codex/skills` へ materialize（orphan-cleanup の `preserve_local_skills` で保護）
  - 変更が browser-observable なら `playwright-cli` で AC 検証、非 UI なら検証を skip して draft PR を開く
  - スクリーンショットは既定で埋め込まず、ユーザー明示確認時のみ `.github/pr-assets/` に commit し SHA 固定 blob URL で PR 本文へ
- 旧ワークフロー基盤の重機構（wiki/ADR 自動生成、CEG impact graph、epic branch reconciliation、auto-merge、issue 自動 close、4値 verdict gate、evidence JSON schema、hero≤800KB 選定、trace/video 必須化）は**復活させない**
- 旧ワークフロー基盤の独自スキル7つ（`dogfood-to-issues` / `harness-feedback` / `marp` / `md-agents-review` / `md-claude-review` / `rop` / `worktree-gc`）を整理して `local-skills/` へ移植。メガパッケージ型の 3層 plugin 構造（`plugins/<ns>/{claude,codex,common}` 型）は不採用 — 必然性は hooks + agents + marketplace 登録にあり skill-only なら flat で足りる。bin 依存は skill 内 `scripts/` 同梱で閉じ、worktree-gc の SessionStart 自動 GC hook と skill 評価ハーネス（eval.yaml / tasks/）は持ち込まない

## Consequences

- 実装後の検証と PR 公開が skill 化され、Claude / Codex / Antigravity から共通に使える
- `to-pr` は draft PR + 正直な軽量検証ノートまで。マージ判断・wiki 同期・証跡アーカイブは人間 / 別プロセスに委ねる
- chezmoi ローカル skill が第 4 の配布経路として確立（apm が唯一の管理点ではなくなった）
- apm.lock 上、mattpocock 追加 4 skill は上流 HEAD (`e9dea69`) に解決されるが、対象 4 skill は既存 pin (`7a83a3a`) と内容同一のため実害なし

関連: [skill-harness](../skill-harness.md) / [2026-07-02-mattpocock-over-superpowers](2026-07-02-mattpocock-over-superpowers.md)
