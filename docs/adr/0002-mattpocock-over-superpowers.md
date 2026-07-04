---
type: decision
title: workflow 層を superpowers から mattpocock skills へ
description: 軽量化のため superpowers plugin を外し mattpocock 設計→実装ワークフローに置換
tags: [adr, skills, superpowers, mattpocock]
timestamp: 2026-07-02
---

# workflow 層を superpowers から mattpocock skills へ

## Status

Accepted (2026-07-02)

## Context

superpowers plugin は TDD / 計画 / コードレビュー等のプロセスを強制するが、implement に時間がかかる。モデルが進化した今、重いプロセス強制を外して軽量化したい。GitHub Issue 駆動の独自ワークフロー package は使わない。

## Decision

- `settings.json` `enabledPlugins` から `superpowers@superpowers-marketplace` を除去
- `apm.yml` から `agent-browser`（playwright-cli と重複）と `grill-me` pin を除去
- mattpocock `engineering/{setup-matt-pocock-skills, grill-with-docs, to-prd, to-issues, triage, tdd}` を apm 追加
- superpowers がカバーしていたプロセス系（systematic-debugging / using-git-worktrees / code-review / verification 等）の穴は**埋めず、モデルのネイティブ能力に委譲**
- frontend/vercel 系 skill と security-guidance は保持

## Consequences

- implement が軽くなる一方、debugging / worktree / review の定型プロセスは agent の自律判断に依存する
- workflow は Claude Code の Skill tool 前提（Codex は汎用コーディングのみ）
- mattpocock ワークフローは per-repo で `setup-matt-pocock-skills` が構成する

関連: [skill-harness](../../runtime/skill-harness.md)
