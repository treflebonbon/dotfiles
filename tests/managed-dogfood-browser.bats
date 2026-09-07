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
  *'-Action Cleanup'*)
    if [[ "${DOGFOOD_PS_FAIL_CLEANUP:-0}" == "1" ]]; then
      printf '%s\n' 'cleanup failed' >&2
      exit 42
    fi
    printf '%s\n' absent >"$DOGFOOD_PS_STATE"
    if [[ "${DOGFOOD_PS_FAIL_PROFILE:-0}" == "1" ]]; then
      printf '%s\n' 'profile cleanup failed' >&2
      exit 43
    fi
    printf '%s\n' absent
    ;;
  *'-Action Resolve'*) printf '%s\n' 'C:\\Users\\test\\AppData\\Local\\Temp\\aiakos-dogfood-test' ;;
  *'-Action Start'*) printf '%s\n' managed:headless:4242 >"$DOGFOOD_PS_STATE" ;;
  *'-Action Inspect'*) if [[ -f "$DOGFOOD_PS_STATE" ]]; then cat "$DOGFOOD_PS_STATE"; else printf '%s\n' absent; fi ;;
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
  export MANAGED_CHROME_OWNER="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/managed-chrome-owner.mjs"
  export DOGFOOD_PS_STATE="$BATS_TEST_TMPDIR/chrome-state"
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
  BROWSER_OWNERSHIP_DIR="$STATE" "$MANAGED_CHROME_OWNER" reserve --role playwright \
    --id alpha --pid "$$" --mode headed --profile profile --endpoint http://127.0.0.1:9222

  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_TEST_ALLOW_CDP_ENDPOINT=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; await acquireManagedDogfoodChrome({ headed: false });"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Managed playwright Chrome is already owned by 'alpha'"* ]]
  ! grep -Fq -- '-Action Start' "$LOG"
  run env BROWSER_OWNERSHIP_DIR="$STATE" "$MANAGED_CHROME_OWNER" status
  [[ "$output" == *'"role":"playwright"'* ]]
}

@test "Managed Dogfood Chrome rejects arbitrary CDP endpoints outside tests" {
  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; await acquireManagedDogfoodChrome({});"

  [ "$status" -ne 0 ]
  [[ "$output" == *"restricted to tests"* ]]
  [ ! -e "$STATE/owner" ]
  ! grep -Fq -- '-Action Start' "$LOG"
}

@test "Managed Dogfood Chrome refuses a second dogfood owner" {
  BROWSER_OWNERSHIP_DIR="$STATE" "$MANAGED_CHROME_OWNER" reserve --role dogfood \
    --id first-run --pid "$$" --mode headless --profile profile --endpoint http://127.0.0.1:9333

  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_TEST_ALLOW_CDP_ENDPOINT=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9334 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; await acquireManagedDogfoodChrome({ runId: 'second-run' });"

  [ "$status" -ne 0 ]
  [[ "$output" == *"already owned by 'first-run'"* ]]
  run env BROWSER_OWNERSHIP_DIR="$STATE" "$MANAGED_CHROME_OWNER" status
  [[ "$output" == *'"role":"dogfood"'* ]]
  ! grep -Fq -- '-Action Start' "$LOG"
}

@test "Managed Dogfood Chrome refuses a legacy acquisition lock during cutover" {
  mkdir "$STATE/acquire.lock"
  printf '%s\n' 99999999 >"$STATE/acquire.lock/pid"

  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_TEST_ALLOW_CDP_ENDPOINT=1 \
    DOGFOOD_CDP_ENDPOINT=http://127.0.0.1:9333 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import { acquireManagedDogfoodChrome } from '$MODULE'; const b = await acquireManagedDogfoodChrome({ runId: 'stale-lock-run' }); console.log(b.endpoint); await b.close();"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Legacy acquisition lock"* ]]
  [ -e "$STATE/acquire.lock" ]
  [ ! -e "$STATE/owner" ]
}

@test "Managed Dogfood Chrome records and releases its isolated ownership" {
  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_TEST_ALLOW_CDP_ENDPOINT=1 \
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

@test "Managed Dogfood Chrome keeps ownership when cleanup cannot stop Chrome" {
  run env \
    DOGFOOD_TEST_WSL=1 \
    DOGFOOD_PS_FAIL_CLEANUP=1 \
    DOGFOOD_POWERSHELL="$BIN/powershell.exe" \
    DOGFOOD_WSLPATH="$BIN/wslpath" \
    DOGFOOD_PS_LOG="$LOG" \
    BROWSER_OWNERSHIP_DIR="$STATE" \
    node --input-type=module -e \
    "import http from 'node:http'; import { acquireManagedDogfoodChrome } from '$MODULE'; const server = http.createServer((_request, response) => response.end('ok')); await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve)); process.env.DOGFOOD_CDP_PORT = String(server.address().port); try { const browser = await acquireManagedDogfoodChrome({ runId: 'cleanup-failure' }); await browser.close(); } finally { server.close(); }"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cleanup failed"* ]]
  [ -e "$STATE/owner" ]
}

@test "Managed Dogfood Chrome releases a stopped browser despite profile cleanup failure" {
  export DOGFOOD_TEST_WSL=1 DOGFOOD_PS_FAIL_PROFILE=1
  export DOGFOOD_POWERSHELL="$BIN/powershell.exe" DOGFOOD_WSLPATH="$BIN/wslpath"
  export BROWSER_OWNERSHIP_DIR="$STATE"
  run node --input-type=module - "$MODULE" <<'JS'
import http from 'node:http';
const { acquireManagedDogfoodChrome } = await import(process.argv[2]);
const server = http.createServer((_request, response) => response.end('ok'));
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
process.env.DOGFOOD_CDP_PORT = String(server.address().port);
try {
  const browser = await acquireManagedDogfoodChrome({ runId: 'profile-failure' });
  await browser.close();
} finally {
  server.close();
}
JS
  [ "$status" -ne 0 ]
  [[ "$output" == *"profile cleanup failed"* ]]
  run "$MANAGED_CHROME_OWNER" status
  [ "$output" = null ]
}
