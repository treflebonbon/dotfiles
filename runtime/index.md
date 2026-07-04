---
type: index
title: treflebonbon/dotfiles knowledge bundle
description: home 配下のどの repo でも共通する、ambient なシェル環境・skill 配備・AI ランタイム知識を OKF (Open Knowledge Format) で表現した agent 向けバンドル
tags: [dotfiles, chezmoi, runtime]
---

# treflebonbon/dotfiles — knowledge bundle

このディレクトリは [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) (OKF v0.1) に沿った知識バンドルです。各 concept は 1 ファイルの markdown で、`type` frontmatter を必須とし、markdown リンクで相互参照します。

chezmoi が `~/runtime/` へ配備するため、home 配下のどの repo で作業している agent もここを読める。**このディレクトリに置くのは、home 配下のどの repo でも同じ意味を持つ ambient な知識だけ**（シェル環境・skill 配備の仕組み・AI ランタイム設定）。ディレクトリ名は「runtime」— OKF は書式（markdown + frontmatter）の名前であり、内容を表す名前ではないため使わない。dotfiles repo 自身の内部構造（chezmoi source レイアウト、commit/lint 規約など）は、他 repo で作業中の agent には価値が無いため `docs/`（repo ローカル、`.chezmoiignore` で home 非配備）に置く（[ADR-0007](../docs/adr/0007-split-okf-by-cross-repo-value.md) 参照）。

## Concepts

- [shell-environment](shell-environment.md) — bash + starship/atuin/fzf/zoxide/ghq のシェル環境
- [skill-harness](skill-harness.md) — apm 経由の skill 群、mattpocock ワークフロー、playwright-cli
- [ai-runtimes](ai-runtimes.md) — nix-devshell の AI ツールと Claude/Codex マルチランタイム、更新経路

dotfiles repo 自身の構造・規約は [docs/architecture.md](../docs/architecture.md) / [docs/conventions.md](../docs/conventions.md)（repo ローカル）を参照。

## Decisions

意思決定記録（ADR）は mattpocock skills 標準に合わせて `docs/adr/`（repo root、repo ローカル）に一本化した。`runtime/` 配下には置かない（[ADR-0006](../docs/adr/0006-consolidate-decisions-into-docs-adr.md) 参照）。
