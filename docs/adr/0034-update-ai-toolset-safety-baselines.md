---
type: decision
title: AI ツールセットを更新し Claude Code 2.1.222 と Codex 0.146.1 を品質ベースラインにする
description: 共有 nixpkgs を固定したまま llm-agents snapshot を更新し、worktree 隔離・permission・auto-review の安全修正を新しい床として採用する
tags: [adr, nix, llm-agents, claude-code, codex, apm]
timestamp: 2026-08-06
status: accepted
---

# AI ツールセットを更新し Claude Code 2.1.222 と Codex 0.146.1 を品質ベースラインにする

## Context

Claude Code 2.1.222 は worktree 隔離 session / subagent が main checkout に destructive git command を実行できる問題と、background agent task で PreToolUse auto-allow hook が tool restriction を迂回できる問題を修正した。Codex 0.146.1 は cyber-capable model の auto-review 既定値を安全側へ修正した。どちらもこの repo が依存する worktree 隔離・managed hook・auto-review の安全境界に直接関係する。

同じ `llm-agents.nix` snapshot では APM も 0.27.0 から 0.28.0 へ進む。copilot-cli 1.0.78、antigravity-cli 1.1.10、RTK 0.44.2 は変化しない。

## Decision

- `llm-agents.nix` を immutable snapshot `efa77d0fc9553758c11ddd22274cb39018aabd48` に固定し、ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` は据え置く。
- `minClaudeCode` を 2.1.221 から 2.1.222、`minCodex` を 0.146.0 から 0.146.1 へ引き上げる。
- x86_64-darwin の claude-code override は 2.1.222 の vendor artifact から実測した sha256 へ更新する。Codex 0.146.1 が要求する librusty_v8 は 149.2.0 のままなので、その override は変更しない。version 不変の copilot-cli / antigravity-cli override も変更しない。
- Linux host からの Intel Darwin 検証は4-systemの derivation 評価と vendor artifact hash までとし、Intel Mac 実機での実行確認とは扱わない。

## Consequences

今後も snapshot version と品質 floor は別に扱い、pin 上の version が変わった package は床の変化に関係なく x86_64-darwin override を再確認する。APM 0.28.0 を使う lock 再生成と検証済み Impeccable pin の採否は [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) の互換性ゲートに従う。

関連: [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
