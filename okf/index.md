---
type: index
title: treflebonbon/dotfiles knowledge bundle
description: chezmoi 管理 dotfiles のアーキテクチャと運用知識を OKF (Open Knowledge Format) で表現した agent 向けバンドル
tags: [dotfiles, chezmoi, okf]
---

# treflebonbon/dotfiles — knowledge bundle

このディレクトリは [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) (OKF v0.1) に沿った知識バンドルです。各 concept は 1 ファイルの markdown で、`type` frontmatter を必須とし、markdown リンクで相互参照します。

chezmoi が `~/okf/` へ配備するため、home で動く agent はここを読んで dotfiles の構造・意思決定を把握できます。

## Concepts

- [architecture](architecture.md) — chezmoi レイアウトと 2 つの flake devShell、per-repo 言語テンプレート
- [shell-environment](shell-environment.md) — bash + starship/atuin/fzf/zoxide/ghq のシェル環境
- [skill-harness](skill-harness.md) — apm 経由の skill 群、mattpocock ワークフロー、playwright-cli
- [ai-runtimes](ai-runtimes.md) — nix-devshell の AI ツールと Claude/Codex マルチランタイム、更新経路
- [conventions](conventions.md) — コミット・lint・認証の規約

## Decisions

- [decisions/index](decisions/index.md) — アーキテクチャ意思決定の一覧
