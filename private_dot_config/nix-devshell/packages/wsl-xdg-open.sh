#!/usr/bin/env bash
# WSL2 の人間向け Web URL だけを Windows の通常の既定 handler へ渡す。
# 非 Web target / 非 WSL は、Nix が提供する本来の xdg-open に委譲する。

set -u

upstream="${WSL_XDG_OPEN_UPSTREAM:-@xdgOpen@}"
powershell="${WSL_XDG_OPEN_POWERSHELL:-@powershell@}"
windows_script="${WSL_XDG_OPEN_SCRIPT:-@windowsScript@}"
osrelease="${WSL_XDG_OPEN_OSRELEASE:-/proc/sys/kernel/osrelease}"

is_wsl() {
  case "${WSL_XDG_OPEN_TEST_WSL:-}" in
  1 | true | yes) return 0 ;;
  0 | false | no) return 1 ;;
  esac

  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  [ -r "$osrelease" ] || return 1
  grep -Eqi '(microsoft|wsl)' "$osrelease"
}

if ! is_wsl || [ "$#" -ne 1 ]; then
  exec "$upstream" "$@"
fi

target="$1"
case "$target" in
[Hh][Tt][Tt][Pp]://* | [Hh][Tt][Tt][Pp][Ss]://*) ;;
*) exec "$upstream" "$@" ;;
esac

if [ ! -x "$powershell" ] && ! command -v "$powershell" >/dev/null 2>&1; then
  printf '%s\n' \
    'Windows browser routing failed: powershell.exe is unavailable in WSL.' \
    'Enable WSL Windows interop and retry (see /etc/wsl.conf [interop]).' >&2
  exit 127
fi

"$powershell" \
  -NoProfile \
  -NonInteractive \
  -ExecutionPolicy Bypass \
  -File "$windows_script" \
  "$target"
status=$?
if [ "$status" -ne 0 ]; then
  printf 'Windows browser routing failed for URL: %s. Verify WSL interop and the Windows default handler, then retry.\n' "$target" >&2
  exit "$status"
fi
