---
type: decision
title: ログインシェルを zsh から bash へ
description: sheldon + zsh 専用対話プラグインを廃し bash に一本化
tags: [adr, bash, zsh, shell]
timestamp: 2026-07-02
---

# ログインシェルを zsh から bash へ

## Status

Accepted (2026-07-02)

## Context

bash を前提とする。従来検討していた zsh 構成は sheldon プラグインマネージャ + zsh 専用の対話プラグイン（autosuggestions / syntax-highlighting / history-substring-search）に依存する設計だった。

## Decision

- `dot_zsh{env,rc,profile}` を `dot_bashrc.tmpl` / `dot_bash_profile.tmpl` に置換
- sheldon を廃止し、`.bashrc` で各ツールの init を直接 `eval`
- zsh 専用の対話プラグインは移植せず、履歴系は atuin に一本化
- hook 基盤として bash-preexec を vendor（atuin の履歴記録・starship のプロンプト描画に必須。init 順序は bash-preexec → fzf → atuin → starship）
- ツール init 系（starship / atuin / fzf / zoxide / ghq / direnv / eza）と ghq 関数を実装（`Ctrl-G` は `bind -x`）
- nix-devshell グローバル env キャッシュは `nix print-dev-env` 出力が bash source 可能なため `.bash` 形式で保持し zcompile は使わない
- `install.sh` は bash デフォルト前提とし、シェル変更（chsh）ロジックは持たない

## Consequences

- autosuggestions / syntax-highlighting は失うが、atuin の履歴補完と `fzf` で実用上カバー
- 起動が軽くなり、プラグインマネージャの保守が不要になった

関連: [shell-environment](../../runtime/shell-environment.md)
