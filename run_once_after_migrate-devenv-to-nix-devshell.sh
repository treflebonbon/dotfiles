#!/usr/bin/env bash
# 旧 deploy 先 ~/.config/devenv/ を掃除する（run_once: 初回のみ実行）
# Phase 2 (devenv → nix-devshell リネーム) 後に旧ディレクトリが残っているケースに対応する。
# chezmoi apply で ~/.config/nix-devshell/ が新規展開された後、旧 ~/.config/devenv/ は
# chezmoi の管理から外れて孤児化するため、ここで明示的に削除する。
set -euo pipefail

OLD="$HOME/.config/devenv"

# 3 条件 AND チェック:
#   - 実ディレクトリとして存在する
#   - シンボリックリンクではない（ユーザーが意図的にリンクしている可能性を保護）
#   - flake.nix が直下にある（無関係なディレクトリの誤削除を防ぐ）
if [ -d "$OLD" ] && [ ! -L "$OLD" ] && [ -f "$OLD/flake.nix" ]; then
  rm -rf -- "$OLD"
  echo "migrate-devenv-to-nix-devshell: $OLD を削除しました"
fi
