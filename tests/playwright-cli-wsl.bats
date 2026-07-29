#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WRAPPER="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-wrapper.sh"
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  UPSTREAM_LOG="$BATS_TEST_TMPDIR/upstream.log"
  POWERSHELL_LOG="$BATS_TEST_TMPDIR/powershell.log"
  POWERSHELL_STATE="$BATS_TEST_TMPDIR/powershell.state"
  RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  DASHBOARD_CALL_LOG="$BATS_TEST_TMPDIR/dashboard-call.log"
  DASHBOARD_READY="$BATS_TEST_TMPDIR/dashboard-ready"
  mkdir -p "$FAKE_BIN"

  cat >"$FAKE_BIN/playwright-cli-upstream" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"show"* && "$*" == *"--port=9323"* ]]; then
  printf '%s\n' "$@" >>"$DASHBOARD_CALL_LOG"
  if [[ "${PWCLI_FAKE_DASHBOARD_FAIL:-0}" == "1" ]]; then
    exit 44
  fi
  touch "$DASHBOARD_READY"
  trap 'rm -f "$DASHBOARD_READY"' EXIT
  while :; do
    sleep 0.1
  done
fi
if [[ "$*" == *"show"* && "$*" == *"--kill"* ]]; then
  dashboard_pid_file="$PWCLI_RUNTIME_DIR/playwright-cli/dashboard.pid"
  if [[ -f "$dashboard_pid_file" ]]; then
    kill "$(cat "$dashboard_pid_file")" 2>/dev/null || true
  fi
fi
if [[ "$*" == *"show"* && "$*" == *"--annotate"* && ! -f "$DASHBOARD_READY" ]]; then
  exit 42
fi
printf '%s\n' "$@" >"$UPSTREAM_LOG"
if [[ "${PWCLI_FAKE_UPSTREAM_FAIL:-0}" == "1" && "$*" == *"open"* ]]; then
  exit 23
fi
EOF
  chmod +x "$FAKE_BIN/playwright-cli-upstream"

  cat >"$FAKE_BIN/wslinfo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${PWCLI_FAKE_NETWORK_MODE:-mirrored}"
EOF
  chmod +x "$FAKE_BIN/wslinfo"

  cat >"$FAKE_BIN/powershell.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POWERSHELL_LOG"
action=
previous=
for argument in "$@"; do
  if [[ "$previous" == "-Action" ]]; then
    action="$argument"
    break
  fi
  previous="$argument"
done
case "$action" in
  Inspect)
    if [[ -f "$POWERSHELL_STATE" ]]; then
      cat "$POWERSHELL_STATE"
    else
      printf '%s\n' absent
    fi
    ;;
  Start)
    printf '%s\n' 'managed:4242' >"$POWERSHELL_STATE"
    printf '%s\n' started
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/powershell.exe"

  cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_LOG"
case "$*" in
  *127.0.0.1:9222/json/version*)
    if [[ "${PWCLI_FAKE_CDP_DOWN:-0}" == "1" ]]; then
      exit 1
    fi
    grep -q '^managed:' "$POWERSHELL_STATE"
    printf '%s\n' '{"Browser":"Chrome/150.0.0.0"}'
    ;;
  *127.0.0.1:9222/json/new*)
    printf '%s\n' '{"id":"dashboard"}'
    ;;
  *127.0.0.1:9323*)
    [[ -f "$DASHBOARD_READY" ]]
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/curl"

  cat >"$FAKE_BIN/cdp-close" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CDP_CLOSE_LOG"
printf '%s\n' absent >"$POWERSHELL_STATE"
EOF
  chmod +x "$FAKE_BIN/cdp-close"

  export CDP_CLOSE_LOG="$BATS_TEST_TMPDIR/cdp-close.log"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  export DASHBOARD_CALL_LOG DASHBOARD_READY
  export POWERSHELL_LOG POWERSHELL_STATE UPSTREAM_LOG
  export PWCLI_UPSTREAM="$FAKE_BIN/playwright-cli-upstream"
  export PWCLI_WSLINFO="$FAKE_BIN/wslinfo"
  export PWCLI_POWERSHELL="$FAKE_BIN/powershell.exe"
  export PWCLI_WINDOWS_SCRIPT="C:\\fake\\playwright-cli-windows.ps1"
  export PWCLI_CURL="$FAKE_BIN/curl"
  export PWCLI_CDP_CLOSE="$FAKE_BIN/cdp-close"
  export PWCLI_RUNTIME_DIR="$RUNTIME_DIR"
  export PWCLI_CDP_TIMEOUT=1
}

teardown() {
  local dashboard_pid_file="$RUNTIME_DIR/playwright-cli/dashboard.pid"
  if [[ -f "$dashboard_pid_file" ]]; then
    kill "$(cat "$dashboard_pid_file")" 2>/dev/null || true
  fi
}

@test "non-WSL environments pass every argument through to upstream" {
  export PWCLI_TEST_WSL=0

  run bash "$WRAPPER" -s=alpha --json open "https://example.com/?a=1&b=2"

  [ "$status" -eq 0 ]
  mapfile -t actual <"$UPSTREAM_LOG"
  expected=(
    "-s=alpha"
    "--json"
    "open"
    "https://example.com/?a=1&b=2"
  )
  [ "${actual[*]}" = "${expected[*]}" ]
}

@test "help and version flags retain upstream behavior on WSL2" {
  export PWCLI_TEST_WSL=1

  run bash "$WRAPPER" --help show
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  grep -Fxq -- "--help" "$UPSTREAM_LOG"
  grep -Fxq -- "show" "$UPSTREAM_LOG"

  run bash "$WRAPPER" --version
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  grep -Fxq -- "--version" "$UPSTREAM_LOG"
}

@test "mirrored WSL2 starts managed Chrome and opens through the CDP config" {
  export PWCLI_TEST_WSL=1

  run bash "$WRAPPER" -s=alpha --raw open "https://example.com/?a=1&b=2"

  [ "$status" -eq 0 ]
  grep -Fq -- "-Action Inspect" "$POWERSHELL_LOG"
  grep -Fq -- "-Action Start" "$POWERSHELL_LOG"
  grep -Fq -- "-s=alpha" "$UPSTREAM_LOG"
  grep -Fq -- "--raw" "$UPSTREAM_LOG"
  grep -Fq -- "https://example.com/?a=1&b=2" "$UPSTREAM_LOG"
  grep -Eq -- "--config=.*/managed-cli-config.json" "$UPSTREAM_LOG"
  grep -Fq '"cdpEndpoint": "http://127.0.0.1:9222"' \
    "$RUNTIME_DIR/playwright-cli/managed-cli-config.json"
  [ "$(sed -n '1p' "$RUNTIME_DIR/playwright-cli/lease")" = "alpha" ]
  [ "$(sed -n '2p' "$RUNTIME_DIR/playwright-cli/lease")" = "$PWD" ]
}

@test "runtime state falls back to a user-only tmp directory" {
  export PWCLI_TEST_WSL=1
  unset PWCLI_RUNTIME_DIR XDG_RUNTIME_DIR
  export PWCLI_TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$PWCLI_TMPDIR"

  run bash "$WRAPPER" -s=alpha open https://example.com

  [ "$status" -eq 0 ]
  local fallback="$PWCLI_TMPDIR/playwright-cli-$UID"
  [ -f "$fallback/lease" ]
  [ "$(stat -c '%a' "$fallback")" = "700" ]
}

@test "the same managed session reuses Chrome while another session is refused" {
  export PWCLI_TEST_WSL=1

  run bash "$WRAPPER" -s=alpha open https://example.com/first
  [ "$status" -eq 0 ]
  run bash "$WRAPPER" -s=alpha open https://example.com/second
  [ "$status" -eq 0 ]
  [ "$(grep -Fc -- "-Action Start" "$POWERSHELL_LOG")" -eq 1 ]

  run bash "$WRAPPER" -s=beta open https://example.com/beta
  [ "$status" -ne 0 ]
  [[ "$output" == *"owned by session 'alpha'"* ]]
  [[ "$output" == *"Close that session"* ]]
}

@test "explicit open browser options bypass the managed WSL2 path" {
  export PWCLI_TEST_WSL=1
  local option
  for option in \
    "--config=custom.json" \
    "--browser=firefox" \
    "--profile=/tmp/profile" \
    "--persistent" \
    "--device=iPhone 15" \
    "--mobile" \
    "--headed"; do
    rm -f "$POWERSHELL_LOG"
    run bash "$WRAPPER" open "$option" https://example.com
    [ "$status" -eq 0 ]
    [ ! -e "$POWERSHELL_LOG" ]
    grep -Fq -- "$option" "$UPSTREAM_LOG"
    ! grep -Fq -- "--config=$RUNTIME_DIR/playwright-cli/managed-cli-config.json" \
      "$UPSTREAM_LOG"
  done
}

@test "project config and browser-shaping environment bypass the managed WSL2 path" {
  export PWCLI_TEST_WSL=1
  local project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project/.playwright"
  printf '%s\n' '{}' >"$project/.playwright/cli.config.json"

  cd "$project"
  run bash "$WRAPPER" open https://example.com
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]

  rm -f "$project/.playwright/cli.config.json" "$POWERSHELL_LOG"
  export PLAYWRIGHT_MCP_DEVICE="Pixel 10"
  run bash "$WRAPPER" open https://example.com
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  unset PLAYWRIGHT_MCP_DEVICE

  rm -f "$POWERSHELL_LOG"
  export PWTEST_CLI_GLOBAL_CONFIG="$project/global-config"
  run bash "$WRAPPER" open https://example.com
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  unset PWTEST_CLI_GLOBAL_CONFIG
}

@test "managed open fails with mirrored networking remediation" {
  export PWCLI_TEST_WSL=1
  export PWCLI_FAKE_NETWORK_MODE=nat

  run bash "$WRAPPER" open https://example.com

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires WSL2 mirrored networking"* ]]
  [[ "$output" == *"networkingMode=mirrored"* ]]
  [[ "$output" == *"wsl.exe --shutdown"* ]]
  [[ "$output" == *"wslinfo --networking-mode"* ]]
  [ ! -e "$POWERSHELL_LOG" ]
}

@test "managed open fails with PowerShell remediation" {
  export PWCLI_TEST_WSL=1
  export PWCLI_POWERSHELL="$FAKE_BIN/missing-powershell.exe"

  run bash "$WRAPPER" open https://example.com

  [ "$status" -ne 0 ]
  [[ "$output" == *"powershell.exe is unavailable"* ]]
  [[ "$output" == *"Windows interoperability"* ]]
}

@test "managed open fails when Windows Chrome is missing" {
  export PWCLI_TEST_WSL=1
  printf '%s\n' chrome-missing >"$POWERSHELL_STATE"

  run bash "$WRAPPER" open https://example.com

  [ "$status" -ne 0 ]
  [[ "$output" == *"Windows Google Chrome was not found"* ]]
  [[ "$output" == *"Install the stable Windows Chrome release"* ]]
}

@test "managed open fails when the CDP endpoint times out" {
  export PWCLI_TEST_WSL=1
  export PWCLI_FAKE_CDP_DOWN=1

  run bash "$WRAPPER" open https://example.com

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not expose CDP at http://127.0.0.1:9222"* ]]
  [[ "$output" == *"verify port 9222 is free"* ]]
}

@test "a failed upstream open releases the lease and closes unused Chrome" {
  export PWCLI_TEST_WSL=1
  export PWCLI_FAKE_UPSTREAM_FAIL=1

  run bash "$WRAPPER" -s=alpha open https://example.com

  [ "$status" -eq 23 ]
  [ ! -e "$RUNTIME_DIR/playwright-cli/lease" ]
  [ -s "$CDP_CLOSE_LOG" ]
}

@test "show starts one loopback dashboard and reopens it in managed Chrome" {
  export PWCLI_TEST_WSL=1

  run bash "$WRAPPER" show
  [ "$status" -eq 0 ]
  [ -s "$RUNTIME_DIR/playwright-cli/dashboard.pid" ]
  [ -f "$RUNTIME_DIR/playwright-cli/dashboard.log" ]
  local first_pid
  first_pid="$(cat "$RUNTIME_DIR/playwright-cli/dashboard.pid")"
  kill -0 "$first_pid"
  grep -Fq -- "--host=127.0.0.1" "$DASHBOARD_CALL_LOG"
  grep -Fq -- "--port=9323" "$DASHBOARD_CALL_LOG"
  grep -Fq "127.0.0.1:9222/json/new?http%3A%2F%2Flocalhost%3A9323%2F" \
    "$CURL_LOG"

  run bash "$WRAPPER" show
  [ "$status" -eq 0 ]
  [ "$(cat "$RUNTIME_DIR/playwright-cli/dashboard.pid")" = "$first_pid" ]
  [ "$(grep -Fc -- "--port=9323" "$DASHBOARD_CALL_LOG")" -eq 1 ]
}

@test "show annotate waits for the dashboard and only accepts the lease owner" {
  export PWCLI_TEST_WSL=1
  run bash "$WRAPPER" -s=alpha open https://example.com
  [ "$status" -eq 0 ]

  run bash "$WRAPPER" -s=alpha show --annotate
  [ "$status" -eq 0 ]
  grep -Fxq -- "--annotate" "$UPSTREAM_LOG"
  [ -f "$DASHBOARD_READY" ]

  run bash "$WRAPPER" -s=beta show --annotate
  [ "$status" -ne 0 ]
  [[ "$output" == *"annotation requires the lease-owning session 'alpha'"* ]]
}

@test "stale dashboard PID is replaced before show returns" {
  export PWCLI_TEST_WSL=1
  mkdir -p "$RUNTIME_DIR/playwright-cli"
  printf '%s\n' 999999 >"$RUNTIME_DIR/playwright-cli/dashboard.pid"

  run bash "$WRAPPER" show

  [ "$status" -eq 0 ]
  [ "$(cat "$RUNTIME_DIR/playwright-cli/dashboard.pid")" != "999999" ]
  kill -0 "$(cat "$RUNTIME_DIR/playwright-cli/dashboard.pid")"
}

@test "a failed Dashboard start removes stale state and closes unused Chrome" {
  export PWCLI_TEST_WSL=1
  export PWCLI_FAKE_DASHBOARD_FAIL=1
  export PWCLI_DASHBOARD_TIMEOUT=1

  run bash "$WRAPPER" show

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not start on http://127.0.0.1:9323/"* ]]
  [ ! -e "$RUNTIME_DIR/playwright-cli/dashboard.pid" ]
  [ -s "$CDP_CLOSE_LOG" ]
}

@test "Chrome closes only after the last managed CLI or dashboard consumer exits" {
  export PWCLI_TEST_WSL=1
  run bash "$WRAPPER" -s=alpha open https://example.com
  [ "$status" -eq 0 ]
  run bash "$WRAPPER" show
  [ "$status" -eq 0 ]

  run bash "$WRAPPER" -s=alpha close
  [ "$status" -eq 0 ]
  [ ! -e "$RUNTIME_DIR/playwright-cli/lease" ]
  [ ! -e "$CDP_CLOSE_LOG" ]

  local dashboard_pid
  dashboard_pid="$(cat "$RUNTIME_DIR/playwright-cli/dashboard.pid")"
  run bash "$WRAPPER" show --kill
  [ "$status" -eq 0 ]
  run kill -0 "$dashboard_pid"
  [ "$status" -ne 0 ]
  [ -s "$CDP_CLOSE_LOG" ]
  [ ! -e "$RUNTIME_DIR/playwright-cli/dashboard.pid" ]
}

@test "managed delete-data refuses to remove the dedicated profile" {
  export PWCLI_TEST_WSL=1
  run bash "$WRAPPER" -s=alpha open https://example.com
  [ "$status" -eq 0 ]

  run bash "$WRAPPER" -s=alpha delete-data

  [ "$status" -ne 0 ]
  [[ "$output" == *"will not delete Managed Playwright Chrome data"* ]]
  [[ "$output" == *"%LOCALAPPDATA%\\aiakos\\playwright-cli\\chrome-profile"* ]]
  [[ "$output" == *"close the session and Dashboard"* ]]
}

@test "attach and explicit Dashboard endpoints retain upstream behavior on WSL2" {
  export PWCLI_TEST_WSL=1

  run bash "$WRAPPER" -s=external attach --cdp=http://localhost:9333
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  grep -Fxq -- "attach" "$UPSTREAM_LOG"

  run bash "$WRAPPER" show --host=0.0.0.0 --port=7777
  [ "$status" -eq 0 ]
  [ ! -e "$POWERSHELL_LOG" ]
  grep -Fxq -- "--host=0.0.0.0" "$UPSTREAM_LOG"
  grep -Fxq -- "--port=7777" "$UPSTREAM_LOG"
}

@test "managed open refuses orphan Chrome and a conflicting CDP port" {
  export PWCLI_TEST_WSL=1
  printf '%s\n' 'managed:4242' >"$POWERSHELL_STATE"

  run bash "$WRAPPER" open https://example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"already running without matching state"* ]]
  [[ "$output" == *"Close that dedicated Chrome manually"* ]]

  printf '%s\n' 'port-conflict:5150' >"$POWERSHELL_STATE"
  run bash "$WRAPPER" open https://example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"127.0.0.1:9222 is owned by a process that is not"* ]]
  [[ "$output" == *"will not be replaced automatically"* ]]
}

@test "close-all reconciles the managed lease and closes Chrome gracefully" {
  export PWCLI_TEST_WSL=1
  run bash "$WRAPPER" -s=alpha open https://example.com
  [ "$status" -eq 0 ]

  run bash "$WRAPPER" close-all

  [ "$status" -eq 0 ]
  grep -Fxq -- "close-all" "$UPSTREAM_LOG"
  [ ! -e "$RUNTIME_DIR/playwright-cli/lease" ]
  [ -s "$CDP_CLOSE_LOG" ]
}

@test "kill-all never force-kills managed Chrome and uses graceful CDP close" {
  export PWCLI_TEST_WSL=1
  run bash "$WRAPPER" -s=alpha open https://example.com
  [ "$status" -eq 0 ]

  run bash "$WRAPPER" kill-all

  [ "$status" -eq 0 ]
  grep -Fxq -- "kill-all" "$UPSTREAM_LOG"
  [ ! -e "$RUNTIME_DIR/playwright-cli/lease" ]
  [ -s "$CDP_CLOSE_LOG" ]
  ! grep -Fq -- "-Action Stop" "$POWERSHELL_LOG"
}
