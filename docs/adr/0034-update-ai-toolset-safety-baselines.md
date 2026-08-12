---
type: decision
title: AI ツールセットを更新し Intel Mac サポートを終了する
description: 共有 nixpkgs を固定したまま安全性 floor と APM skill を更新し、3-system化によって Intel Darwin 専用 override を廃止する
tags: [adr, nix, llm-agents, claude-code, codex, apm, darwin]
timestamp: 2026-08-06
status: accepted
---

# AI ツールセットを更新し Intel Mac サポートを終了する

> 2026-08-12 に [ADR-0035](0035-update-llm-agents-snapshot-and-trust-boundary-baseline.md) が snapshot と `minClaudeCode`/`minCodex` の値を更新したため、本決定のうちその部分は superseded。x86_64-darwin サポート終了と3-system化の決定は本 ADR がそのまま正本。

## Context

Claude Code 2.1.222 は worktree 隔離 session / subagent が main checkout に destructive git command を実行できる問題と、background agent task で PreToolUse auto-allow hook が tool restriction を迂回できる問題を修正した。Codex 0.146.1 は cyber-capable model の auto-review 既定値を安全側へ修正した。どちらもこの repo が依存する worktree 隔離・managed hook・auto-review の安全境界に直接関係する。

同じ `llm-agents.nix` snapshot では APM も 0.27.0 から 0.28.0 へ進む。copilot-cli 1.0.78、antigravity-cli 1.1.10、RTK 0.44.2 は変化しない。

`llm-agents.nix` は x86_64-darwin packaging を既に終了しており、この repo は Claude Code / Codex / Copilot CLI / Antigravity CLI の4 packageを vendor artifact と手動 hash で復旧していた。pin 更新のたびに version skew と artifact URL を個別検証する必要がある一方、Intel Mac を現行の対応 system として維持する必要性はなくなった。

## Decision

- `llm-agents.nix` を immutable snapshot `efa77d0fc9553758c11ddd22274cb39018aabd48` に固定し、ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` は据え置く。
- `minClaudeCode` を 2.1.221 から 2.1.222、`minCodex` を 0.146.0 から 0.146.1 へ引き上げる。
- repo 全体の対応 system を x86_64-linux / aarch64-linux / aarch64-darwin の3つに統一し、x86_64-darwin を終了する。
- AI CLI 4種の Intel Darwin override、Claude Code 専用 derivation、`allowBroken` 例外、Intel向け release asset/hashを削除し、supported system は pin 済みの `llm.*` packageを直接使う。

## Consequences

今後も snapshot version と品質 floor は別に扱うが、pin 更新時の Intel Darwin artifact 追跡は不要になる。Nix の検証対象は3 systemとし、APM 0.28.0 を使う lock 再生成と検証済み Impeccable pin の採否は [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) の互換性ゲートに従う。本決定は [ADR-0028](0028-claude-code-darwin-x64-local-override.md) と [ADR-0033](0033-update-llm-agents-snapshot-and-claude-baseline.md) を supersede する。

関連: [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0033](0033-update-llm-agents-snapshot-and-claude-baseline.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
