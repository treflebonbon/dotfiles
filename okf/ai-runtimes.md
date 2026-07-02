---
type: concept
title: AI runtimes
description: nix-devshell の AI ツールと Claude Code / Codex マルチランタイム設定、更新経路
tags: [ai, claude-code, codex, nix, llm-agents]
---

# AI runtimes

## nix-devshell の AI ツール

AI/LLM ツールは `github:numtide/llm-agents.nix` flake 経由で管理（`modules/ai.nix`）:

- **LLM CLI**: claude-code, codex, copilot-cli, antigravity
- **コードレビュー**: coderabbit-cli
- **ワークフロー**: rtk

外部 skill / plugin は apm が担当する（→ [skill-harness](skill-harness.md)）。Nix devshell は CLI バイナリを供給する。

## Claude Code / Codex マルチランタイム

workflow パイプライン（mattpocock skills）は Claude Code の Skill tool 前提だが、汎用コーディングは Codex でも行える二刀流を維持する。

- **Claude**: `private_dot_claude/settings.json.tmpl` → `~/.claude/settings.json`。`language: japanese`、`effortLevel: xhigh`、`teammateMode: auto`、deny ルール群、`enabledPlugins`（LSP / codex / security-guidance / claude-code-setup）。個人・端末差分は `~/.claude/settings.local.json`（管理外）。
- **Codex**: `private_dot_config/codex/`（config.toml / rules / AGENTS.md / hooks.json / environments）を `run_onchange_after_codex-*.sh.tmpl` が `~/.config/codex/` 経由で `~/.codex/`（`$CODEX_HOME`）へマージ配置する。宣言的設定のみ管理しローカル state は保全する。
- **AGENTS.md** — Codex / OpenCode / Zed / Cursor 向け指示（`~/AGENTS.md`、`private_dot_gemini/AGENTS.md` は Gemini 向け）。CLAUDE.md は Claude Code 向けに別管理。

MCP サーバーは `.mcp.json` / `private_dot_mcp.json` で設定（context7 / serena / effect-docs）。

## AI ツール更新の 2 経路

| 経路 | 対象 | 管理ファイル |
| ---- | ---- | ------------ |
| nix devshell binary | claude-code / codex / copilot-cli / coderabbit-cli / rtk 等 | `private_dot_config/nix-devshell/{flake.nix,modules/ai.nix,packages/*}` |
| APM skill / plugin | 外部 skill / Claude marketplace plugin | `apm.yml` / `apm.lock.yaml` |

「AI ツールを更新したい」ときは両経路を確認する。

関連: [architecture](architecture.md) / [skill-harness](skill-harness.md)
