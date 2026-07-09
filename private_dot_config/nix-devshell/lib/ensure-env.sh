#!/usr/bin/env bash
# shellcheck shell=bash
# nix-devshell の global env cache を best-effort で source する。
# direnv 未起動 or 親シェルが nix-devshell 環境を継承していない場合 (例: chezmoi apply
# が devpod 起動直後に走るケース) で、apm / claude などの devShell 由来 CLI を
# PATH に乗せるために使う。
#
# cache が存在しなければ何もせずに return 0。呼び出し側はその後の command -v X で
# graceful skip を判定する想定。

ensure_nix_devshell_env() {
  local CACHE="${1:-$HOME/.cache/nix-devshell-global-env.bash}"
  [ -f "$CACHE" ] || return 0

  local prev_shell="${SHELL:-}"
  local prev_bash="${BASH:-}"

  # cache は `nix print-dev-env` の出力で bash として source 可能。
  # set -u 環境で源 / 一部の未定義参照 (e.g. PS1, BASH_VERSION) で落ちうるため一時退避。
  local prev_u=""
  case $- in *u*) prev_u=1 ;; esac
  set +u
  # shellcheck disable=SC1090
  . "$CACHE" 2>/dev/null || true

  # nix print-dev-env は stdenv の bash を SHELL/BASH として出力することがある。
  # その bash は readline なしのため、chezmoi cd 等の対話シェル選択に漏らさない。
  case "$prev_shell" in /nix/store/*/bin/bash) prev_shell="" ;; esac
  if [ -z "$prev_shell" ] && [ -n "$prev_bash" ] && [ -x "$prev_bash" ]; then
    prev_shell="$prev_bash"
  fi
  if [ -n "$prev_shell" ]; then
    export SHELL="$prev_shell"
  fi
  if [ -n "$prev_bash" ]; then
    BASH="$prev_bash"
  fi

  [ -n "$prev_u" ] && set -u
  return 0
}
