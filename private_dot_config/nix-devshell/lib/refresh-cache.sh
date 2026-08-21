#!/usr/bin/env bash
# shellcheck shell=bash

refresh_nix_devshell_cache() {
  local DIR="${1:-$HOME/.config/nix-devshell}"
  local CACHE="${2:-$HOME/.cache/nix-devshell-global-env.bash}"
  local LOG="${3:-$HOME/.cache/nix-devshell-refresh.log}"
  local required="${NIX_DEVSHELL_CACHE_REQUIRED:-0}"

  if [ ! -d "$DIR" ] || ! command -v nix >/dev/null 2>&1; then
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

  local stale=0
  if [ ! -f "$CACHE" ]; then
    stale=1
  else
    local list
    if list=$(find "$DIR" -type f \( -name 'flake.nix' -o -name 'flake.lock' -o -name '*.nix' \) 2>/dev/null); then
      if [ -n "$list" ]; then
        while IFS= read -r f; do
          if [ "$f" -nt "$CACHE" ]; then
            stale=1
            break
          fi
        done <<<"$list"
      fi
    else
      stale=1
    fi
  fi

  [ "$stale" = "0" ] && return 0

  mkdir -p "$(dirname "$CACHE")" "$(dirname "$LOG")"

  # silent 化される前に予告 — 初回 binary cache fetch は数分かかる
  printf 'refresh-nix-devshell-cache: re-evaluating devshell (first run may take several minutes; downloads stream below)\n' >&2

  local tmp err
  local -a nix_output_args=()
  if [ -n "${WSL_DISTRO_NAME:-}" ] || {
    [ -r /proc/sys/kernel/osrelease ] && grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
  }; then
    nix_output_args=(".#wsl")
  fi
  tmp=$(mktemp "${CACHE}.tmp.XXXXXX")
  err=$(mktemp "${LOG}.err.XXXXXX")

  if (cd "$DIR" && nix print-dev-env "${nix_output_args[@]}" 2> >(tee -a "$err" >&2) | grep -v '^LINENO=' | grep -Ev '^(BASH|SHELL)=') >"$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$CACHE"
    tmp=""
    [ -s "$err" ] && cat "$err" >>"$LOG"
    rm -f "$err"
    printf 'refresh-nix-devshell-cache: cache refreshed\n'
    return 0
  fi

  {
    printf '\n=== %s nix print-dev-env failed ===\n' "$(date -Iseconds 2>/dev/null || date)"
    cat "$err"
  } >>"$LOG"
  rm -f "$tmp" "$err"
  printf 'refresh-nix-devshell-cache: nix print-dev-env failed (see %s)\n' "$LOG" >&2
  [ "$required" = "1" ] && return 1
  return 0
}
