#!/usr/bin/env bash
# nix-devshell グローバル環境キャッシュを chezmoi apply のたびに self-heal + 同期再生成する。
# 実体は ~/.config/nix-devshell/lib/refresh-cache.sh の refresh_nix_devshell_cache 関数。
set -euo pipefail

LIB="$HOME/.config/nix-devshell/lib/refresh-cache.sh"
if [ ! -f "$LIB" ]; then
  printf 'refresh-nix-devshell-cache: required library is missing: %s\n' "$LIB" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"
NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache
