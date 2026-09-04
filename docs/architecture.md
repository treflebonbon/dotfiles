---
type: concept
title: Architecture
description: chezmoi dotfiles のレイアウトと 2 種類の flake devShell、per-repo 言語テンプレート
tags: [chezmoi, nix, flake, devshell]
---

# Architecture

chezmoi 管理の dotfiles。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。

**編集・配備ルール**: engineering change は validated task worktree 内の source で行う。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi apply` して `~/` へ反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source へ戻す。live source は init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される。

CLAUDE.md / AGENTS.md / `runtime/` バンドルは chezmoi が `~/` へ配備する（`~/CLAUDE.md` がグローバル指示の実体、`~/runtime/` が agent 向け知識バンドル）。この `docs/architecture.md` 自体は repo ローカル専用（`.chezmoiignore` で `~/docs/` へは非配備）— dotfiles repo 自身の構造説明は他 repo で作業中の agent には価値が無いため。

## 2 種類の flake devShell

混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（chezmoi / lefthook / cocogitto / shellcheck / shfmt / oxfmt / bats / bun / playwright-driver など lint・format・test 一式）。通常の `.#default` は非 WSL の互換経路を維持し、WSL2 では marker `.wsl-browser-free` により `.#wsl`（browser binary なし）を自動選択する。`cd "$(chezmoi source-path)"` で direnv が自動ロード。加えて per-repo flake の `templates` output（go/rust/elixir/perl/gleam/bun）を公開する。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム（node / python3 / bun）+ 横断ツール + AI ツール。`.#default` は従来のローカル browser 互換経路、`.#wsl` は Playwright browser を closure に含めず Managed Windows CDP adapter だけを配布する。WSL2 の direnv と global environment cache は `.#wsl` を自動選択し、`nix-direnv` で評価結果をキャッシュする。node / python3 / bun は AI / 汎用ツールが script を実行する汎用ランタイムとして常駐する。プロジェクト言語（go/rust/elixir/perl/gleam）の toolchain は持たない。

`flake.nix` は `modules/*.nix`（node, python, runtimes, shell, editor, git, k8s, security, formatters, testing, docs, ai）を plain fragment として import し、`pkgs.mkShell` に packages / env / shellHook を fold する。ユーザー環境と per-repo template はともに `nixpkgs-26.05-darwin` を使い、x86_64-linux / aarch64-linux / aarch64-darwin の3 system に対応する。AI package は原則 `llm-agents` の shared overlay を使うが、source/LTO build が大きい Codex だけは同じ immutable `llm-agents` input の direct package を使い、通常の upstream version では Numtide CI の binary cache と derivation を一致させる。これにより snapshot の一貫性を変えず、consumer 側の stable nixpkgs との差で毎回 source build になることを避ける。upstream 未収録版を一時的に local override する期間だけは source build となり、upstream 追従時に override を削除して cacheable な経路へ戻す（[ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md)）。x86_64-darwin は upstream package の対応縮小と local override の継続コストを受け、2026-08-06 にサポートを終了した（[ADR-0034](adr/0034-update-ai-toolset-safety-baselines.md)）。

## per-repo 言語テンプレート

プロジェクト言語は per-repo `flake.nix` で供給する。新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。テンプレ実体は `templates/<lang>/`、ルート `./flake.nix` の `templates` output で公開（`.chezmoiignore` で home には非配備）。

## ツール追加先の使い分け

- chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`
- 横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/flake.nix` と配下の `modules/*.nix`（[ai-runtimes](../runtime/ai-runtimes.md) 参照）
- プロジェクト言語ツール → per-repo flake / `templates/<lang>/`

関連: [shell-environment](../runtime/shell-environment.md) / [skill-harness](../runtime/skill-harness.md) / [adr/](adr/)
