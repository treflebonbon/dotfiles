---
type: decision
title: claude-code の x86_64-darwin を local override で復旧する
description: numtide/llm-agents.nix が claude-code の darwin-x64 packaging を打ち切った後も、Anthropic 本家の配布バイナリを直接参照する自前パッケージで Intel Mac サポートを継続する
tags: [adr, nix, claude-code, darwin, llm-agents]
timestamp: 2026-07-25
status: accepted
---

# claude-code の x86_64-darwin を local override で復旧する

## Context

Issue #112（Claude Opus 5 対応）で `minClaudeCode` を 2.1.219 へ床上げする必要が生じた。`numtide/llm-agents.nix` は commit `718f56b955bb`（2026-07-21、「Drop x86_64-darwin support」）で claude-code の darwin-x64 hash 追跡を停止しており、2.1.217 以降のどの commit にも darwin-x64 の packaging は存在しない。素直に pin を進めると `llm.claude-code` は x86_64-darwin 上で `Unsupported system` を throw する。

`flake.nix` は元々 `nixpkgs-26.05-darwin`（Intel Darwin サポート終了は 2026-12-31）を pin し、`allowBroken = system == "x86_64-darwin"` などの互換対応も維持しており、この repo は Intel Mac を積極的にサポートする方針を既に持っている。一方、Anthropic 本家の配布バケット（`storage.googleapis.com/claude-code-dist-...`）を直接検証したところ、2.1.219 時点でも `darwin-x64` バイナリは配布されている（HTTP 200、hash 実測済み）。つまり今回の断絶は upstream nix packaging 側の追跡停止であり、Anthropic 自体の Intel Mac 打ち切りではない。

## Decision

`private_dot_config/nix-devshell/packages/claude-code-darwin-x64.nix` に、Anthropic の配布 URL を直接参照する自前の `stdenv.mkDerivation` を追加し、`modules/ai.nix` の `claudeCode` を `pkgs.stdenv.hostPlatform.system == "x86_64-darwin"` のときだけこちらへ差し替える。`llm.claude-code` は他の3 system ではそのまま使う。

トレードオフとして、今後 `minClaudeCode` を上げるたびに、このファイルの `version` / `hash` を手動更新する保守コストをこの repo 側が負う（更新手順はファイル内コメントに記載）。numtide 側が packaging を再開すれば、このファイルは削除して `llm.claude-code` に戻せる。
