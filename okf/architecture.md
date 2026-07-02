---
type: concept
title: Architecture
description: chezmoi dotfiles のレイアウトと 2 種類の flake devShell、per-repo 言語テンプレート
tags: [chezmoi, nix, flake, devshell]
---

# Architecture

chezmoi 管理の dotfiles。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。

**編集ルール**: ファイル編集は chezmoi source (`~/.local/share/chezmoi/`) 内で行い、`chezmoi apply` で `~/` に反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source へ戻す。

CLAUDE.md / AGENTS.md / この `okf/` バンドルは chezmoi が `~/` へ配備する（`~/CLAUDE.md` がグローバル指示の実体、`~/okf/` が agent 向け知識バンドル）。

## 2 種類の flake devShell

混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（chezmoi / lefthook / cocogitto / shellcheck / shfmt / oxfmt / bats / bun / playwright-driver など lint・format・test 一式）。`cd ~/.local/share/chezmoi` で direnv が自動ロード。加えて per-repo flake の `templates` output（go/rust/elixir/perl/gleam/bun）を公開する。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム（node / python3 / bun）+ 横断ツール + AI ツール。`nix-direnv` で評価結果をキャッシュ。node / python3 / bun は AI / 汎用ツールが script を実行する汎用ランタイムとして常駐する。プロジェクト言語（go/rust/elixir/perl/gleam）の toolchain は持たない。

`flake.nix` は `modules/*.nix`（node, python, runtimes, shell, editor, git, k8s, security, formatters, testing, docs, ai）を plain fragment として import し、`pkgs.mkShell` に packages / env / shellHook を fold する（4 system 対応）。

## per-repo 言語テンプレート

プロジェクト言語は per-repo `flake.nix` で供給する。新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。テンプレ実体は `templates/<lang>/`、ルート `./flake.nix` の `templates` output で公開（`.chezmoiignore` で home には非配備）。

## ツール追加先の使い分け

- chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`
- 横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/flake.nix` と配下の `modules/*.nix`（[ai-runtimes](ai-runtimes.md) 参照）
- プロジェクト言語ツール → per-repo flake / `templates/<lang>/`

関連: [shell-environment](shell-environment.md) / [skill-harness](skill-harness.md) / [decisions/index](decisions/index.md)
