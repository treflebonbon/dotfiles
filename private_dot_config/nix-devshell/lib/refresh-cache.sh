#!/usr/bin/env bash
# shellcheck shell=bash

# stdin を使い、GNU sha256sum / macOS shasum のファイル名表示差を除く。
_nix_devshell_hash() (
  set -o pipefail
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  else
    shasum -a 256
  fi | {
    local digest rest
    read -r digest rest && printf '%s\n' "$digest"
  }
)

_nix_devshell_source_entries() {
  local path kind
  [ -r "$1" ] && [ -x "$1" ] || return 1
  for path in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    if [ "$1" = . ]; then
      case "$path" in
      ./.git | ./.direnv) continue ;;
      ./result | ./result-*) [ -L "$path" ] && continue ;;
      esac
    fi
    if [ -L "$path" ]; then
      printf 'link\0%s\0' "$path" && readlink "$path" && printf '\0' || return 1
    elif [ -d "$path" ]; then
      printf 'directory\0%s\0' "$path" && _nix_devshell_source_entries "$path" || return 1
    elif [ -f "$path" ]; then
      kind="file"
      [ ! -x "$path" ] || kind=executable
      printf '%s\0%s\0' "$kind" "$path" && _nix_devshell_hash <"$path" || return 1
    else
      return 1
    fi
  done
}

_nix_devshell_input_id() (
  set -o pipefail
  export LC_ALL=C
  # caller の glob option が入力の列挙に影響しないようにする (bash 3.2 対応)。
  set +f
  unset GLOBIGNORE
  shopt -u dotglob failglob nullglob
  cd "$1" || exit 1
  { printf '%s\0' "$2" && _nix_devshell_source_entries .; } | _nix_devshell_hash
)

refresh_nix_devshell_cache() {
  local DIR="${1:-$HOME/.config/nix-devshell}"
  local CACHE="${2:-$HOME/.cache/nix-devshell-global-env.bash}"
  local LOG="${3:-$HOME/.cache/nix-devshell-refresh.log}"
  local required="${NIX_DEVSHELL_CACHE_REQUIRED:-0}"

  if [ ! -f "$DIR/flake.nix" ] || ! command -v nix >/dev/null 2>&1; then
    [ "$required" = "1" ] && return 1
    return 0
  fi

  export NIX_CONFIG="${NIX_CONFIG:-extra-experimental-features = nix-command flakes}"

  if [ -d "$DIR/.git" ] && command -v git >/dev/null 2>&1; then
    if git -C "$DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
      printf 'refresh-nix-devshell-cache: %s/.git has user commits; skipping recovery (manual cleanup needed)\n' "$DIR" >&2
      [ "$required" = "1" ] && return 1
      return 0
    fi
    rm -rf "$DIR/.git"
    printf 'refresh-nix-devshell-cache: removed untracked .git/ in %s\n' "$DIR"
  fi

  local tmp="" err="" input_id="" cached_id="" selected_output=default
  local -a nix_output_args=()
  if [ -n "${WSL_DISTRO_NAME:-}" ] || {
    [ -r /proc/sys/kernel/osrelease ] && grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
  }; then
    selected_output=wsl
    nix_output_args=(".#wsl")
  fi

  if input_id=$(_nix_devshell_input_id "$DIR" "$selected_output"); then
    if [ -f "$CACHE" ]; then
      cached_id=$(tail -n 1 "$CACHE") || cached_id=""
      [ "$cached_id" != "# nix-devshell-input-v1: $input_id" ] || return 0
    fi
  else
    printf 'refresh-nix-devshell-cache: cannot fingerprint devshell inputs\n' >&2
    [ "$required" = "1" ] && return 1
    return 0
  fi

  # silent 化される前に予告 — 初回 binary cache fetch は数分かかる
  printf 'refresh-nix-devshell-cache: re-evaluating devshell (first run may take several minutes; downloads stream below)\n' >&2

  if mkdir -p "$(dirname "$CACHE")" "$(dirname "$LOG")" &&
    tmp=$(mktemp "${CACHE}.tmp.XXXXXX") && err=$(mktemp "${LOG}.err.XXXXXX") &&
    (
      set -o pipefail
      cd "$DIR" && nix print-dev-env "${nix_output_args[@]}" 2> >(tee -a "$err" >&2) | grep -v '^LINENO=' | grep -Ev '^(BASH|SHELL)='
    ) >"$tmp" &&
    [ -s "$tmp" ] && "$BASH" -n "$tmp" 2>>"$err" &&
    # 入力情報も同じファイルに含め、読込み可能な結果を一度の rename で採用する。
    printf '\n# nix-devshell-input-v1: %s\n' "$input_id" >>"$tmp" &&
    # mv はディレクトリへの移動も成功とするが、キャッシュとしては読めない。
    [ ! -d "$CACHE" ] && mv "$tmp" "$CACHE" 2>>"$err"; then
    tmp=""
    if [ -s "$err" ]; then cat "$err" >>"$LOG" || true; fi
    rm -f "$err" || true
    printf 'refresh-nix-devshell-cache: cache refreshed\n'
    return 0
  fi

  {
    printf '\n=== %s cache refresh failed ===\n' "$(date -Iseconds 2>/dev/null || date)"
    if [ -s "$err" ]; then cat "$err"; fi
  } >>"$LOG" || true
  rm -f "$tmp" "$err" || true
  printf 'refresh-nix-devshell-cache: cache refresh failed (see %s)\n' "$LOG" >&2
  [ "$required" = "1" ] && return 1
  return 0
}
