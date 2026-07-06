---
type: decision
title: 設計→実装ワークフローをシナリオ別の3チェーンに分岐する（ADR-0004 のチェーン決定を amend）
description: ADR-0004 が定めた単一チェーン（to-worktree → grill-with-docs → to-prd → to-issues → triage → to-pr）は要件未確定のシナリオにのみ妥当で、要件確定済み実装・バグ修正では to-issues/triage を経由しない近道が必要だったため、シナリオ別の3チェーンに分岐する
tags: [adr, skills, mattpocock, workflow]
timestamp: 2026-07-06
---

# 設計→実装ワークフローをシナリオ別の3チェーンに分岐する（ADR-0004 のチェーン決定を amend）

## Status

Accepted (2026-07-06)。本 ADR の「シナリオ別3チェーン」という枠組み自体は [ADR-0014](0014-triage-not-after-to-issues.md)（2026-07-07）で、上流 `ask-matt` の main-flow/on-ramp 構造に合わせた「メインフロー1本 + on-ramp 2つ」に amend 済み（`triage` を `to-issues` 産出物に使わない、という個別の是正も含む）。

## Context

[ADR-0004](0004-fill-mattpocock-gaps.md) はワークフローチェーンを `to-worktree → grill-with-docs → to-prd → to-issues → triage → to-pr` の単一チェーンとして決定し、CLAUDE.md にもそのまま記載していた。しかしこの単一チェーンは「要件未確定（新機能をゼロから設計する）」シナリオにのみ妥当で、以下2シナリオでは `to-issues` / `triage` を経由する必要がなく、`to-worktree` から直接実装フェーズへ入るべきだった:

- **要件確定済み実装**: 何を作るか既に決まっている小さな作業（issue 化・triage を経る意味がない）
- **バグ修正**: 再現・原因が明確な不具合対応

単一チェーンの記載はこの3シナリオを区別せず、要件確定済み実装・バグ修正でも to-issues/triage を経由するかのように読めていた（[#18](https://github.com/treflebonbon/dotfiles/issues/18)）。

## Decision

CLAUDE.md の「設計→実装ワークフロー」節を、シナリオ別の3チェーンとして記載し直す:

- **要件未確定**: `to-worktree` → `grill-with-docs` → `to-prd` → `to-issues` → `triage` で ready-for-agent にする（実装は下記いずれかのチェーンへ引き継ぐ）
- **要件確定済み実装**: `to-worktree` → `tdd` → `code-review` → `to-pr`（`to-issues` / `triage` を経由しない）
- **バグ修正**: `to-worktree` → `diagnosing-bugs` → `code-review` → `to-pr`（同上）

いずれのチェーンも実装フェーズに user-invoked skill は無く、model-invoked 層（`tdd` / `code-review` / `diagnosing-bugs` / `domain-modeling` / `codebase-design` / `prototype` / `research`）が自動発火する点は ADR-0004 から変更しない。

worktree 隔離（`to-worktree` / Orca セッションでの `orca-cli` 優先）・`setup-matt-pocock-skills` によるリポジトリ初期設定・`to-pr` の役割等、ADR-0004 のその他の決定はそのまま維持する。本 ADR は「チェーンは1本である」という部分のみを amend する。

## Consequences

- 要件確定済み実装・バグ修正では issue トラッカーを経由しない軽量な作業が、ワークフロー上正式なパスとして認められる
- CLAUDE.md の記載がシナリオ別に分岐し、迷ったときにどのチェーンを使うべきか判断しやすくなる
- `to-issues` / `triage` は「要件未確定」シナリオ専用ではなく、他経路で生まれた issue の triage にも引き続き使われる（triage skill 自体の役割に変更はない）

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [issue #18](https://github.com/treflebonbon/dotfiles/issues/18)
