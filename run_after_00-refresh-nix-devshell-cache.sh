#!/usr/bin/env bash
# nix-devshell グローバル環境キャッシュを chezmoi apply のたびに self-heal + 同期再生成する。
# 実体は ~/.config/nix-devshell/lib/refresh-cache.sh の refresh_nix_devshell_cache 関数。
set -euo pipefail

LIB="$HOME/.config/nix-devshell/lib/refresh-cache.sh"
[ -f "$LIB" ] || exit 0

# shellcheck source=/dev/null
. "$LIB"
refresh_nix_devshell_cache
