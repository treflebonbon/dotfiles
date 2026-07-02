#!/usr/bin/env bash
# GitHub CLI setup script managed by chezmoi (treflebonbon/dotfiles)
# run_after_: chezmoi apply のたびに実行（冪等性を確保）
set -euo pipefail

# gh がインストールされていない場合はスキップ
if ! command -v gh &>/dev/null; then
  exit 0
fi

# gh が認証されていない場合はスキップ
if ! gh auth status &>/dev/null; then
  exit 0
fi

# Extensions（pin したバージョンと不一致の場合は入れ替え）
GH_POI_VERSION="v0.17.2"
if ! gh extension list 2>/dev/null | grep -q "seachicken/gh-poi.*${GH_POI_VERSION}"; then
  # remove 前に pin 対象リリースへ到達可能か確認（オフライン時に既存拡張を消さない）
  if gh release view "${GH_POI_VERSION}" --repo seachicken/gh-poi >/dev/null 2>&1; then
    echo "Installing gh extension: gh-poi ${GH_POI_VERSION}"
    gh extension remove poi 2>/dev/null || true
    gh extension install seachicken/gh-poi --pin "${GH_POI_VERSION}" 2>/dev/null || true
  fi
fi

# Aliases are managed in ~/.config/gh/config.yml via chezmoi
