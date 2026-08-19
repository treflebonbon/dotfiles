#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  UPSTREAM_LOG="$BATS_TEST_TMPDIR/upstream.log"
  POWERSHELL_LOG="$BATS_TEST_TMPDIR/powershell.log"
  export UPSTREAM_LOG POWERSHELL_LOG
  mkdir -p "$TEST_BIN"
  : >"$UPSTREAM_LOG"
  : >"$POWERSHELL_LOG"

  cat >"$TEST_BIN/upstream-xdg-open" <<'STUB'
#!/usr/bin/env bash
printf 'argc=%s\n' "$#" >>"$UPSTREAM_LOG"
printf '<%s>\n' "$@" >>"$UPSTREAM_LOG"
STUB
  chmod +x "$TEST_BIN/upstream-xdg-open"

  cat >"$TEST_BIN/powershell.exe" <<'STUB'
#!/usr/bin/env bash
printf 'argc=%s\n' "$#" >>"$POWERSHELL_LOG"
printf '<%s>\n' "$@" >>"$POWERSHELL_LOG"
STUB
  chmod +x "$TEST_BIN/powershell.exe"

  cat >"$TEST_BIN/wslpath" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' 'C:\converted\open-url.ps1'
STUB
  chmod +x "$TEST_BIN/wslpath"
  export WSL_XDG_OPEN_WSLPATH="$TEST_BIN/wslpath"
}

write_osrelease() {
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/osrelease"
}

@test "WSL HTTP(S) URL is handed to Windows default handler" {
  run env \
    WSL_XDG_OPEN_TEST_WSL=1 \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/powershell.exe" \
    WSL_XDG_OPEN_SCRIPT="$BATS_TEST_TMPDIR/open-url.ps1" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'https://example.test/search?q=one&sort=desc'

  [ "$status" -eq 0 ]
  [ ! -s "$UPSTREAM_LOG" ]
  grep -Fq '<https://example.test/search?q=one&sort=desc>' "$POWERSHELL_LOG"
  grep -Fq '<C:\converted\open-url.ps1>' "$POWERSHELL_LOG"
  grep -Fq -- '-File' "$POWERSHELL_LOG"
  [ "$(grep -c '^argc=' "$POWERSHELL_LOG")" -eq 1 ]
}

@test "WSL osrelease probe routes HTTP(S) without the distro environment marker" {
  write_osrelease '6.18.33.2-microsoft-standard-WSL2'

  run env \
    -u WSL_DISTRO_NAME \
    -u WSL_XDG_OPEN_TEST_WSL \
    WSL_XDG_OPEN_OSRELEASE="$BATS_TEST_TMPDIR/osrelease" \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/powershell.exe" \
    WSL_XDG_OPEN_SCRIPT="$BATS_TEST_TMPDIR/open-url.ps1" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'https://example.test/osrelease-probe'

  [ "$status" -eq 0 ]
  [ ! -s "$UPSTREAM_LOG" ]
  grep -Fq '<https://example.test/osrelease-probe>' "$POWERSHELL_LOG"
}

@test "WSL non-web target keeps the native xdg-open path" {
  run env \
    WSL_XDG_OPEN_TEST_WSL=1 \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/powershell.exe" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'file:///tmp/report.html'

  [ "$status" -eq 0 ]
  grep -Fq '<file:///tmp/report.html>' "$UPSTREAM_LOG"
  [ ! -s "$POWERSHELL_LOG" ]
}

@test "non-WSL HTTP(S) URL keeps the native xdg-open path" {
  run env \
    WSL_XDG_OPEN_TEST_WSL=0 \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/powershell.exe" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'https://example.test/'

  [ "$status" -eq 0 ]
  grep -Fq '<https://example.test/>' "$UPSTREAM_LOG"
  [ ! -s "$POWERSHELL_LOG" ]
}

@test "WSL routing reports missing PowerShell with remediation and no fallback" {
  run -127 env \
    WSL_XDG_OPEN_TEST_WSL=1 \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/missing-powershell.exe" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'https://example.test/missing-interop'

  [ "$status" -eq 127 ]
  [[ "$output" == *"Enable WSL Windows interop"* ]]
  [ ! -s "$UPSTREAM_LOG" ]
}

@test "WSL routing reports interop failure without falling back" {
  cat >"$TEST_BIN/failing-powershell.exe" <<'STUB'
#!/usr/bin/env bash
printf 'called\n' >>"$POWERSHELL_LOG"
exit 23
STUB
  chmod +x "$TEST_BIN/failing-powershell.exe"

  run env \
    WSL_XDG_OPEN_TEST_WSL=1 \
    WSL_XDG_OPEN_UPSTREAM="$TEST_BIN/upstream-xdg-open" \
    WSL_XDG_OPEN_POWERSHELL="$TEST_BIN/failing-powershell.exe" \
    WSL_XDG_OPEN_SCRIPT="$BATS_TEST_TMPDIR/open-url.ps1" \
    "$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh" \
    'http://example.test/'

  [ "$status" -eq 23 ]
  [[ "$output" == *"Windows browser routing failed"* ]]
  [ ! -s "$UPSTREAM_LOG" ]
}
