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
| nix devshell binary | claude-code / codex / copilot-cli / rtk 等 | `private_dot_config/nix-devshell/{flake.nix,modules/ai.nix,packages/*}` |
| APM skill / plugin | 外部 skill / Claude marketplace plugin | `apm.yml` / `apm.lock.yaml` |

「AI ツールを更新したい」ときは両経路を確認する。

baseline は `modules/ai.nix` の `minClaudeCode` assert で床固定する（現 `2.1.199`）。床の根拠はモデル品質（Sonnet 5 default）＋ 多 agent ワークフローの信頼性（error 伝搬・background daemon 安定化）。

## claude-code 2.1.199 以降の挙動変更（設計→実装ワークフローへの影響）

`settings.json` は変更せず、認識だけ合わせる。ワークフロー側ドキュメント（CLAUDE.md の設計→実装ワークフロー / [skill-harness](skill-harness.md)）からはここを参照する。

- **subagent が既定で background 実行**（2.1.198）— 委譲中も本流が進み完了通知が来る。`teammateMode: auto` と整合。
- **worktree 完了時に自動 commit / push / draft PR**（2.1.198）— `claude agents` 起動の background agent は worktree でのコード作業を終えると停止して尋ねず自動で draft PR を開く。`to-worktree` → `to-pr` の想定と重なるので二重 PR に注意。
- **stacked slash-skill が先頭 5 個までロード**（2.1.199）— `/skill-a /skill-b ...` で先頭 skill だけでなく先頭 5 個を全ロード。user-invoked チェーンの連結起動に効く。
- **subagent の error 伝搬修正**（2.1.199）— rate-limit / API error を「成功」と誤報せず親へ正確に伝える。多 agent 実行の信頼性が上がる。
- **Explore agent が main model を継承**（opus cap, 2.1.198）／**`/agents` wizard 削除**（`.claude/agents/` 直接編集 or Claude に依頼）。

関連: [architecture](architecture.md) / [skill-harness](skill-harness.md)
