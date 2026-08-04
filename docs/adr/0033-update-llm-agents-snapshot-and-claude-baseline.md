---
type: decision
title: llm-agents snapshot を更新し Claude Code 2.1.221 を品質ベースラインにする
description: 共有 nixpkgs を固定したまま llm-agents と導入済み AI CLI を更新し、permission・workflow 修正を含む Claude Code 2.1.221 を新しい床として採用する
tags: [adr, nix, llm-agents, claude-code, codex, copilot-cli, antigravity-cli]
timestamp: 2026-08-04
status: accepted
---

# llm-agents snapshot を更新し Claude Code 2.1.221 を品質ベースラインにする

## Context

導入済み AI CLI を更新するため `llm-agents.nix` の snapshot を再評価した。Claude Code 2.1.221 は zsh の `[[ ]]` regex 内に隠したコマンドによる permission check 迂回を修正し、background session が `CLAUDE.md` の git 指示に従って依頼時だけ draft PR を開くよう変更している。RTK 0.44.2 は履歴 DB・tee log・audit log・既存 data directory の permission を owner-only に締め、APM 0.27.0 は install / lock / audit / auth / MCP・target mapping を修正している。

## Decision

- `llm-agents.nix` を immutable snapshot `71c0eafcae20331346e60154ca843d4791ba1245` に固定し、ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` は据え置く。
- 導入 version を claude-code 2.1.221、codex 0.146.0、copilot-cli 1.0.78、antigravity-cli 1.1.10、rtk 0.44.2、apm 0.27.0 とする。Claude Code の permission・workflow 修正はこの repo の auto mode と worktree 運用に直結するため、`minClaudeCode` を 2.1.219 から 2.1.221 へ上げる。`minCodex` は 0.146.0 のまま維持する。
- x86_64-darwin override は claude-code 2.1.221 と copilot-cli 1.0.78 の vendor artifact を直接取得した sha256、antigravity-cli 1.1.10 の build ID `6423386432339968` と sha512 へ更新する。codex 0.146.0 が要求する librusty_v8 は 149.2.0 のままなので変更しない。
- Linux host からの x86_64-darwin 検証は4-systemの derivation 評価と vendor artifact hash までとし、Intel Mac 実機での実行確認とは扱わない。

## Consequences

`runtime/ai-runtimes.md` には home-wide に必要な現在の snapshot・version・override 状態だけを置き、更新理由と検証境界は本 ADR を正本とする。将来の pin 更新では [ADR-0028](0028-claude-code-darwin-x64-local-override.md) に従い、床の変化ではなく pin 上の各 package version の変化をトリガーに local override を再確認する。

関連: [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
