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
    IFS=' ' read -r digest rest && printf '%s\n' "$digest"
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
  exec 9>&-
  set -o pipefail
  export LC_ALL=C
  # caller の glob option が入力の列挙に影響しないようにする (bash 3.2 対応)。
  set +f
  unset GLOBIGNORE GLOBSORT
  shopt -u dotglob failglob nullglob
  cd "$1" || exit 1
  { printf '%s\0' "$2" && _nix_devshell_source_entries .; } | _nix_devshell_hash
)

_nix_devshell_selected_output() {
  if [ -n "${WSL_DISTRO_NAME:-}" ] || {
    [ -r /proc/sys/kernel/osrelease ] && grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
  }; then
    printf 'wsl\n'
  else
    printf 'default\n'
  fi
}

_nix_devshell_discard_temps() (
  exec 9>&-
  set +f
  unset GLOBIGNORE
  shopt -u failglob
  shopt -s nullglob
  # 終了した更新の出力だけを回収する。生存する評価子は開いた旧 inode へ出力する。
  rm -f -- "$1".tmp.* "$1".err.*
)

_nix_devshell_refresh_locked() {
  local DIR="${1:-$HOME/.config/nix-devshell}"
  local CACHE="${2:-$HOME/.cache/nix-devshell-global-env.bash}"
  local LOG="${3:-$HOME/.cache/nix-devshell-refresh.log}"
  local required="${NIX_DEVSHELL_CACHE_REQUIRED:-0}"

  if [ ! -f "$DIR/flake.nix" ] || ! command -v nix >/dev/null 2>&1; then
    [ "$required" = "1" ] && return 1
    return 0
  fi

  local lock_status=0
  perl -MConfig -MFcntl=:flock -e '
    $Config{d_flock} eq "define" or die "native flock is required\n";
    flock(STDIN, LOCK_EX | ($ARGV[0] eq "1" ? 0 : LOCK_NB)) or do {
      exit 75 if $!{EWOULDBLOCK} || $!{EAGAIN};
      die "cannot lock user environment cache: $!\n";
    };
  ' "$required" <&9 || lock_status=$?
  [ "$lock_status" != 75 ] || return 0
  [ "$lock_status" = 0 ] || return 1
  _nix_devshell_discard_temps "$CACHE" || return 1

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

  local tmp="" err="" input_id cached_id selected_output post_id post_output
  local attempt candidate_ok
  for attempt in 1 2; do
    selected_output=$(
      exec 9>&-
      _nix_devshell_selected_output
    )
    if ! input_id=$(
      exec 9>&-
      _nix_devshell_input_id "$DIR" "$selected_output"
    ); then
      printf 'refresh-nix-devshell-cache: cannot fingerprint devshell inputs\n' >&2
      break
    fi
    if [ -f "$CACHE" ]; then
      cached_id=$(tail -n 1 "$CACHE") || cached_id=""
      [ "$cached_id" != "# nix-devshell-input-v1: $input_id" ] || return 0
    fi

    printf 'refresh-nix-devshell-cache: re-evaluating devshell (first run may take several minutes; downloads stream below)\n' >&2
    if ! { mkdir -p "$(dirname "$LOG")" &&
      tmp=$(mktemp "${CACHE}.tmp.XXXXXX") && err=$(mktemp "${CACHE}.err.XXXXXX"); }; then
      break
    fi

    candidate_ok=0
    if (
      exec 9>&-
      set -o pipefail
      cd "$DIR" && nix print-dev-env ".#$selected_output" 2> >(tee -a "$err" >&2) | grep -v '^LINENO=' | grep -Ev '^(BASH|SHELL)='
    ) >"$tmp" &&
      [ -s "$tmp" ] && "$BASH" -n "$tmp" 9>&- 2>>"$err"; then
      candidate_ok=1
    fi

    post_output=$(
      exec 9>&-
      _nix_devshell_selected_output
    )
    post_id=$(
      exec 9>&-
      _nix_devshell_input_id "$DIR" "$post_output"
    ) || break
    if [ "$input_id" != "$post_id" ]; then
      printf 'refresh-nix-devshell-cache: inputs changed during evaluation (attempt %s/2)\n' "$attempt" >&2
      if [ "$attempt" = 1 ]; then
        if [ -s "$err" ]; then cat "$err" >>"$LOG" || true; fi
        rm -f "$tmp" "$err" || break
        tmp="" err=""
        continue
      fi
      break
    fi

    if [ "$candidate_ok" = 1 ] &&
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
    break
  done

  {
    printf '\n=== %s cache refresh failed ===\n' "$(date -Iseconds 2>/dev/null || date)"
    if [ -s "$err" ]; then cat "$err"; fi
  } >>"$LOG" || true
  rm -f "$tmp" "$err" || true
  printf 'refresh-nix-devshell-cache: cache refresh failed (see %s)\n' "$LOG" >&2
  [ "$required" = "1" ] && return 1
  return 0
}

refresh_nix_devshell_cache() {
  local DIR="${1:-$HOME/.config/nix-devshell}"
  local CACHE="${2:-$HOME/.cache/nix-devshell-global-env.bash}"
  local LOG="${3:-$HOME/.cache/nix-devshell-refresh.log}"
  local required="${NIX_DEVSHELL_CACHE_REQUIRED:-0}"

  if [ ! -f "$DIR/flake.nix" ] || ! command -v nix >/dev/null 2>&1; then
    [ "$required" != 1 ]
    return
  fi
  if ! command -v perl >/dev/null 2>&1; then
    printf 'refresh-nix-devshell-cache: system perl is required for cache locking\n' >&2
    [ "$required" != 1 ]
    return
  fi

  # lock file は置換・削除しない。待機者と次の呼出しが同じ inode を使う。
  # function redirection で FD を呼出し元へ残さず、更新 process の終了でも解放する。
  if mkdir -p "$(dirname "$CACHE")" &&
    _nix_devshell_refresh_locked "$DIR" "$CACHE" "$LOG" 9>>"${CACHE}.lock"; then
    return 0
  fi
  [ "$required" != 1 ]
}
