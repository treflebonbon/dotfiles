#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MODULE="$PROJECT_ROOT/local-skills/dogfood-to-issues/references/managed-dogfood-browser.mjs"
  BIN="$BATS_TEST_TMPDIR/bin"
  STATE="$BATS_TEST_TMPDIR/ownership"
  LOG="$BATS_TEST_TMPDIR/powershell.log"
  mkdir -p "$BIN" "$STATE"
  : >"$LOG"

  cat >"$BIN/powershell.exe" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOGFOOD_PS_LOG"
case "$*" in
  *'-Action Resolve'*) printf '%s\n' 'C:\\Users\\test\\AppData\\Local\\Temp\\aiakos-dogfood-test' ;;
  *) printf '%s\n' absent ;;
esac
STUB
  chmod +x "$BIN/powershell.exe"

  cat >"$BIN/wslpath" <<'STUB'
#!/usr/bin/env bash
printf 'C:\\Users\\test\\extension'
STUB
  chmod +x "$BIN/wslpath"
  export DOGFOOD_PS_LOG="$LOG"
  export DOGFOOD_WINDOWS_SCRIPT="$BATS_TEST_TMPDIR/dogfood-windows.ps1"
}

@test "non-WSL dogfood leaves browser ownership untouched" {
  run env \
    DOGFOOD_TEST_WSL=0 \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; console.log(await acquireManagedDogfoodChrome({}));"

  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [ ! -e "$STATE/owner" ]
}

@test "Managed Dogfood Chrome refuses an existing Managed Playwright owner" {
  printf '%s\n' \
    playwright alpha 4242 headed /tmp/playwright-profile http://127.0.0.1:9222 /workspace \
    >"$STATE/owner"

  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; await acquireManagedDogfoodChrome({ headed: false });"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Managed playwright Chrome is owned by 'alpha'"* ]]
  ! grep -Fq -- '-Action Start' "$LOG"
  [ "$(head -n 1 "$STATE/owner")" = "playwright" ]
}

@test "Managed Dogfood Chrome rejects arbitrary CDP endpoints outside tests" {
  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    env -u DOGFOOD_TEST_WSL node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; await acquireManagedDogfoodChrome({});"

  [ "$status" -ne 0 ]
  [[ "$output" == *"restricted to tests"* ]]
  [ ! -e "$STATE/owner" ]
  ! grep -Fq -- '-Action Start' "$LOG"
}

@test "Managed Dogfood Chrome records and releases its isolated ownership" {
  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; const b = await acquireManagedDogfoodChrome({ headed: true }); console.log(b.endpoint, b.mode); await b.close();"

  [ "$status" -eq 0 ]
  [[ "$output" == *"http://127.0.0.1:9333 headed"* ]]
  [ ! -e "$STATE/owner" ]
  [ "$(grep -c -- '-Action Resolve' "$LOG")" -eq 1 ]
  ! grep -Fq -- '-Action Start' "$LOG"
}
