#!/usr/bin/env bash
# Reconcile the user-wide plugin registration on every chezmoi apply.
set -euo pipefail

fail() {
  printf 'setup-herdr: %s\n' "$1" >&2
  exit 1
}

LIB="$HOME/.config/nix-devshell/lib/ensure-env.sh"
[ -f "$LIB" ] || fail "required environment library is missing: $LIB"
# shellcheck source=/dev/null
. "$LIB"
ensure_nix_devshell_env
for tool in herdr jq git; do
  command -v "$tool" >/dev/null 2>&1 || fail "required command is missing: $tool"
done

source_dir=$(cd "${CHEZMOI_SOURCE_DIR:?chezmoi source directory is required}" && pwd -P)
# Only an accepted primary source may own the persistent registration.
[ -d "$source_dir/.git" ] || fail 'source must be a primary Git checkout'
root=$(git -C "$source_dir" rev-parse --show-toplevel)
[ "$(cd "$root" && pwd -P)" = "$source_dir" ] || fail 'source must be the repository root'
plugin_root="$source_dir/.herdr"
[ -f "$plugin_root/herdr-plugin.toml" ] || fail 'copy-env manifest is missing'

plugins=$(herdr plugin list --plugin dotfiles.copy-env --json)
jq -e '
  .result.plugins | type == "array"
' <<<"$plugins" >/dev/null || fail 'invalid plugin list response'
count=$(jq '.result.plugins | length' <<<"$plugins")
[ "$count" -le 1 ] || fail 'ambiguous copy-env registration'
args=()
if [ "$count" -eq 1 ]; then
  jq -e '
    .result.plugins[0] |
    .plugin_id == "dotfiles.copy-env" and
    (.plugin_root | type == "string") and
    (.enabled | type == "boolean")
  ' <<<"$plugins" >/dev/null || fail 'invalid copy-env registration'
  registered_root=$(jq -r '.result.plugins[0].plugin_root' <<<"$plugins")
  [ "$registered_root" != "$plugin_root" ] || exit 0
  if [ "$(jq -r '.result.plugins[0].enabled' <<<"$plugins")" = false ]; then
    args+=(--disabled)
  fi
fi
herdr plugin link "$plugin_root" ${args[@]+"${args[@]}"}
