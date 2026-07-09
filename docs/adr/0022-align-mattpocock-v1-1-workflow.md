---
type: decision
title: mattpocock skills v1.1.0 に合わせて workflow 語彙と implement を採用する
description: 上流 mattpocock/skills v1.1.0 の promoted set に合わせ、to-prd/to-issues を to-spec/to-tickets に置き換え、implement・wayfinder・resolving-merge-conflicts を APM 導入する。既存の Builder-Evaluator 自律性と to-pr の PR 公開責務は維持する
tags: [adr, skills, mattpocock, workflow, implement, wayfinder]
timestamp: 2026-07-10
---

# mattpocock skills v1.1.0 に合わせて workflow 語彙と implement を採用する

## Status

Accepted (2026-07-10)

## Context

上流 `mattpocock/skills` の最新 release は v1.1.0（2026-07-08）。上流 README / engineering directory の promoted set は、この repo が採用していた `to-prd` / `to-issues` ではなく `to-spec` / `to-tickets` を現行名として扱っている。また `implement` / `wayfinder` / `resolving-merge-conflicts` が engineering skill として提供されている。

この repo は ADR-0004 / ADR-0015 で `implement` と `resolving-merge-conflicts` を非導入にしていた。主な理由は、当時の上流で `implement` の README 掲載・分類・review/commit 省略に不安があり、`tdd` / `code-review` を model-invoked discipline として直接使う方が明示的だったためである。一方で、ADR-0019 以降は Builder-Evaluator の commit 責務と安全モデル（worktree 隔離、自動テスト、PR レビュー）が repo 側で明文化され、`implement` を導入してもその安全モデルを維持できる状態になっている。

今回の目的は「最新の mattpocock skills に準拠」することであり、上流の現行語彙と導入セットに repo 側の agent-facing docs / APM 設定を合わせる必要がある。

## Decision

1. `to-prd` / `to-issues` を、上流現行名の `to-spec` / `to-tickets` に置き換える。過去 ADR 内の旧称は履歴として残すが、現在の運用語彙は `to-spec` / `to-tickets` とする。
2. `implement` を user-invoked の Builder-Evaluator entrypoint として導入する。`tdd` / `code-review` は消さず、`implement` の内部で使われる model-invoked discipline として位置づける。
3. `implement` は 1 ticket を完了する単位だが、この repo の ADR-0019 を維持し、AFK/明示依頼時は frontier 上の次 ticket へ同一 worktree/branch で連続実行してよい。smart zone に達したら `/handoff` で別セッションへ渡す。
4. `wayfinder` を user-invoked on-ramp として導入する。巨大で曖昧な作業は、まず調査・決定 ticket の map にして frontier を明確にし、その後 Planner / Builder-Evaluator に合流する。
5. `resolving-merge-conflicts` を model-invoked discipline として導入する。merge/rebase conflict 時に primary source を読んで両変更意図を保つための専門手順として扱う。
6. 既存ローカル `to-pr` は維持する。上流 `implement` は commit-to-branch で止まるため、PR body の Contract / Verification Matrix / Code Review 記録、push 前確認、PR 作成は引き続き `to-pr` が担う。
7. `grill-me` と `teach` は引き続き非導入とする。`grill-with-docs` と `writing-great-skills` で現在の用途は足りており、設計→実装ワークフローの最小セットを保つ。

## Consequences

- 現在のメインフローは `to-worktree` → `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr` になる。要件確定済みの小さな作業は Planner を省略して `implement` から入ってよい。
- `triage` は引き続き raw issue 専用 on-ramp であり、`to-tickets` が生成した ticket には使わない。
- `Planner` は `grill-with-docs` → `to-spec` → `to-tickets`、`Builder-Evaluator` は `implement` を入口に `tdd` / `code-review` を使う主体、という glossary に更新する。
- ADR-0004 / ADR-0015 の `implement` 非導入判断、ADR-0016 の `resolving-merge-conflicts` 非導入判断は本 ADR で置き換えられる。
- `apm.lock.yaml` は `cd ~ && apm lock` と `apm install` に依存するため、APM 設定更新後に再生成する。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [ADR-0014](0014-triage-not-after-to-issues.md) / [ADR-0015](0015-add-tdd-commit-confirmation.md) / [ADR-0019](0019-builder-evaluator-cross-issue-autonomy.md) / [skill-harness](../../runtime/skill-harness.md) / upstream [mattpocock/skills](https://github.com/mattpocock/skills)
