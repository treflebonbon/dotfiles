#!/usr/bin/env bash

set -euo pipefail

pwcli_upstream="${PWCLI_UPSTREAM:-@playwrightCliUpstream@}"
pwcli_wslinfo="${PWCLI_WSLINFO:-wslinfo}"
pwcli_powershell="${PWCLI_POWERSHELL:-powershell.exe}"
pwcli_wslpath="${PWCLI_WSLPATH:-wslpath}"
pwcli_curl="${PWCLI_CURL:-@curl@/bin/curl}"
pwcli_cdp_close="${PWCLI_CDP_CLOSE:-@cdpClose@}"
pwcli_windows_script="${PWCLI_WINDOWS_SCRIPT:-@windowsScript@}"
pwcli_proc_root="${PWCLI_PROC_ROOT:-/proc}"
pwcli_flock="${PWCLI_FLOCK:-@flock@}"
pwcli_cdp_endpoint="http://127.0.0.1:9222"

fail() {
  printf 'playwright-cli: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "__pwcli-dashboard-daemon" ]]; then
  pwcli_fifo="$2"
  pwcli_launcher_file="$3"
  pwcli_inherited_lock_fd="${4:-}"
  if [[ "$pwcli_inherited_lock_fd" =~ ^[0-9]+$ ]]; then
    exec {pwcli_inherited_lock_fd}>&-
  fi
  printf '%s\n' "$$" >"$pwcli_launcher_file"
  exec 3<>"$pwcli_fifo"
  exec "$pwcli_upstream" show --host=127.0.0.1 --port=9323 <&3
fi

is_wsl() {
  if [[ -n "${PWCLI_TEST_WSL:-}" ]]; then
    [[ "$PWCLI_TEST_WSL" == "1" ]]
    return
  fi
  [[ -r /proc/sys/kernel/osrelease ]] &&
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

if ! is_wsl; then
  exec "$pwcli_upstream" "$@"
fi

pwcli_command=
pwcli_session=default
pwcli_session_value_next=0
pwcli_explicit_show_endpoint=0
pwcli_passthrough_metadata=0
pwcli_show_annotate=0
pwcli_show_kill=0
for pwcli_argument in "$@"; do
  if ((pwcli_session_value_next)); then
    pwcli_session="$pwcli_argument"
    pwcli_session_value_next=0
    continue
  fi
  case "$pwcli_argument" in
  -s | --session)
    pwcli_session_value_next=1
    ;;
  -s=* | --session=*)
    pwcli_session="${pwcli_argument#*=}"
    ;;
  --host | --host=* | --port | --port=*)
    pwcli_explicit_show_endpoint=1
    ;;
  --kill)
    pwcli_show_kill=1
    ;;
  --annotate)
    pwcli_show_annotate=1
    ;;
  --help | -h | --version | -v)
    pwcli_passthrough_metadata=1
    ;;
  -*)
    ;;
  *)
    if [[ -z "$pwcli_command" ]]; then
      pwcli_command="$pwcli_argument"
    fi
    ;;
  esac
done

if [[ "$pwcli_command" != "show" ]]; then
  pwcli_show_kill=0
  pwcli_show_annotate=0
fi

if ((pwcli_passthrough_metadata)); then
  exec "$pwcli_upstream" "$@"
fi

if [[ "$pwcli_command" == "open" ]]; then
  pwcli_bypass_managed=0
  for pwcli_argument in "$@"; do
    case "$pwcli_argument" in
    --config | --config=* | --browser | --browser=* | --profile | --profile=* | --persistent | --device | --device=* | --mobile | --headed)
      pwcli_bypass_managed=1
      ;;
    esac
  done

  pwcli_browser_env=(
    PLAYWRIGHT_MCP_CONFIG
    PLAYWRIGHT_MCP_BROWSER
    PLAYWRIGHT_MCP_BLOCK_SERVICE_WORKERS
    PLAYWRIGHT_MCP_CDP_ENDPOINT
    PLAYWRIGHT_MCP_CDP_HEADERS
    PLAYWRIGHT_MCP_CDP_TIMEOUT
    PLAYWRIGHT_MCP_DEVICE
    PLAYWRIGHT_MCP_EXECUTABLE_PATH
    PLAYWRIGHT_MCP_EXTENSION
    PLAYWRIGHT_MCP_GRANT_PERMISSIONS
    PLAYWRIGHT_MCP_HEADLESS
    PLAYWRIGHT_MCP_IGNORE_HTTPS_ERRORS
    PLAYWRIGHT_MCP_INIT_PAGE
    PLAYWRIGHT_MCP_INIT_SCRIPT
    PLAYWRIGHT_MCP_ISOLATED
    PLAYWRIGHT_MCP_MOBILE
    PLAYWRIGHT_MCP_PROXY_BYPASS
    PLAYWRIGHT_MCP_PROXY_SERVER
    PLAYWRIGHT_MCP_SANDBOX
    PLAYWRIGHT_MCP_STORAGE_STATE
    PLAYWRIGHT_MCP_USER_AGENT
    PLAYWRIGHT_MCP_USER_DATA_DIR
    PLAYWRIGHT_MCP_VIEWPORT_SIZE
    PWTEST_CLI_GLOBAL_CONFIG
  )
  for pwcli_env_name in "${pwcli_browser_env[@]}"; do
    if [[ -n "${!pwcli_env_name:-}" ]]; then
      pwcli_bypass_managed=1
      break
    fi
  done

  if [[ -f .playwright/cli.config.json ]]; then
    pwcli_bypass_managed=1
  fi
  if ((pwcli_bypass_managed)); then
    exec "$pwcli_upstream" "$@"
  fi
elif [[ "$pwcli_command" == "show" ]]; then
  if ((pwcli_explicit_show_endpoint)); then
    exec "$pwcli_upstream" "$@"
  fi
elif [[ "$pwcli_command" != "close" && "$pwcli_command" != "delete-data" && "$pwcli_command" != "close-all" && "$pwcli_command" != "kill-all" ]]; then
  exec "$pwcli_upstream" "$@"
fi

if [[ -n "${PWCLI_RUNTIME_DIR:-}" ]]; then
  pwcli_state_dir="$PWCLI_RUNTIME_DIR/playwright-cli"
elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  pwcli_state_dir="$XDG_RUNTIME_DIR/playwright-cli"
else
  pwcli_state_dir="${PWCLI_TMPDIR:-/tmp}/playwright-cli-$UID"
fi
umask 077
mkdir -p "$pwcli_state_dir"
chmod 700 "$pwcli_state_dir"

pwcli_lock_file="$pwcli_state_dir/runtime.lock"
exec {pwcli_lock_fd}>"$pwcli_lock_file"
if ! "$pwcli_flock" --exclusive --wait 5 "$pwcli_lock_fd"; then
  fail "timed out waiting for the Managed Playwright Chrome runtime lock at $pwcli_lock_file"
fi
release_lock() {
  exec {pwcli_lock_fd}>&-
}
trap release_lock EXIT

pwcli_lease="$pwcli_state_dir/lease"
pwcli_dashboard_pid_file="$pwcli_state_dir/dashboard.pid"
pwcli_dashboard_start_time_file="$pwcli_state_dir/dashboard.starttime"
pwcli_dashboard_launcher_file="$pwcli_state_dir/dashboard.launcher"
pwcli_dashboard_log="$pwcli_state_dir/dashboard.log"
pwcli_dashboard_fifo="$pwcli_state_dir/dashboard.stdin"
pwcli_workspace="$(pwd -P)"
pwcli_powershell_ready=0

prepare_powershell() {
  if ((pwcli_powershell_ready)); then
    return
  fi
  if ! command -v "$pwcli_powershell" >/dev/null 2>&1; then
    fail "powershell.exe is unavailable. Enable Windows interoperability for this WSL distribution, restart WSL, and verify with: powershell.exe -NoProfile -Command '\$PSVersionTable.PSVersion'"
  fi
  if [[ "$pwcli_windows_script" != *\\* && "$pwcli_windows_script" != [A-Za-z]:* ]]; then
    pwcli_windows_script="$("$pwcli_wslpath" -w "$pwcli_windows_script")"
  fi
  pwcli_powershell_ready=1
}

powershell_action() {
  prepare_powershell
  "$pwcli_powershell" \
    -NoProfile \
    -NonInteractive \
    -ExecutionPolicy Bypass \
    -File "$pwcli_windows_script" \
    -Action "$1" | tr -d '\r'
}

inspect_chrome() {
  powershell_action Inspect | tail -n 1
}

dashboard_port_ready() {
  "$pwcli_curl" \
    --fail \
    --silent \
    --max-time "${PWCLI_DASHBOARD_PROBE_TIMEOUT:-0.25}" \
    "http://127.0.0.1:9323/" >/dev/null
}

dashboard_listener_inodes() {
  awk '$2 == "0100007F:246B" && $4 == "0A" { print $10 }' "$pwcli_proc_root/net/tcp"
}

process_owns_socket_inode() {
  local pid="$1"
  local inode="$2"
  local fd target
  [[ "$pid" =~ ^[0-9]+$ && -d "$pwcli_proc_root/$pid/fd" ]] || return 1
  for fd in "$pwcli_proc_root/$pid/fd/"*; do
    [[ -L "$fd" ]] || continue
    target="$(readlink "$fd" 2>/dev/null || true)"
    if [[ "$target" == "socket:[$inode]" ]]; then
      return 0
    fi
  done
  return 1
}

find_dashboard_listener_pid() {
  local inode process_fd_dir pid
  while read -r inode; do
    [[ -n "$inode" ]] || continue
    for process_fd_dir in "$pwcli_proc_root"/[0-9]*/fd; do
      pid="${process_fd_dir#"$pwcli_proc_root"/}"
      pid="${pid%/fd}"
      if process_owns_socket_inode "$pid" "$inode"; then
        printf '%s\n' "$pid"
        return 0
      fi
    done
  done < <(dashboard_listener_inodes)
  return 1
}

process_session_id() {
  local pid="$1"
  local stat_data stat_tail session_id
  [[ -r "$pwcli_proc_root/$pid/stat" ]] || return 1
  stat_data="$(<"$pwcli_proc_root/$pid/stat")"
  stat_tail="${stat_data##*) }"
  read -r _ _ _ session_id _ <<<"$stat_tail"
  printf '%s\n' "$session_id"
}

process_start_time() {
  local pid="$1"
  local stat_data stat_tail
  local -a stat_fields
  [[ -r "$pwcli_proc_root/$pid/stat" ]] || return 1
  stat_data="$(<"$pwcli_proc_root/$pid/stat")"
  stat_tail="${stat_data##*) }"
  read -r -a stat_fields <<<"$stat_tail"
  [[ -n "${stat_fields[19]:-}" ]] || return 1
  printf '%s\n' "${stat_fields[19]}"
}

dashboard_pid_owns_port() {
  local pid="$1"
  local inode
  while read -r inode; do
    if process_owns_socket_inode "$pid" "$inode"; then
      return 0
    fi
  done < <(dashboard_listener_inodes)
  return 1
}

dashboard_listener_for_launcher() {
  local launcher_pid="$1"
  local listener_pid listener_session_id
  listener_pid="$(find_dashboard_listener_pid)" || return 1
  listener_session_id="$(process_session_id "$listener_pid")" || return 1
  [[ "$listener_session_id" == "$launcher_pid" ]] || return 1
  printf '%s\n' "$listener_pid"
}

terminate_dashboard_session() {
  local session_id="$1"
  local process_dir pid
  for process_dir in "$pwcli_proc_root"/[0-9]*; do
    pid="${process_dir#"$pwcli_proc_root"/}"
    if [[ "$(process_session_id "$pid" 2>/dev/null || true)" == "$session_id" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

cdp_ready() {
  "$pwcli_curl" \
    --fail \
    --silent \
    --max-time "${PWCLI_CDP_PROBE_TIMEOUT:-0.5}" \
    "$pwcli_cdp_endpoint/json/version" >/dev/null
}

dashboard_status() {
  if [[ -f "$pwcli_dashboard_pid_file" ]]; then
    local pid recorded_start_time actual_start_time
    pid="$(cat "$pwcli_dashboard_pid_file")"
    recorded_start_time="$(cat "$pwcli_dashboard_start_time_file" 2>/dev/null || true)"
    actual_start_time="$(process_start_time "$pid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] &&
      [[ -n "$recorded_start_time" && "$actual_start_time" == "$recorded_start_time" ]] &&
      kill -0 "$pid" 2>/dev/null; then
      if ! dashboard_port_ready; then
        return 3
      fi
      if dashboard_pid_owns_port "$pid"; then
        return 0
      fi
    fi
    rm -f \
      "$pwcli_dashboard_pid_file" \
      "$pwcli_dashboard_start_time_file" \
      "$pwcli_dashboard_launcher_file" \
      "$pwcli_dashboard_fifo"
  elif [[ -f "$pwcli_dashboard_start_time_file" || -f "$pwcli_dashboard_launcher_file" ]]; then
    rm -f "$pwcli_dashboard_start_time_file" "$pwcli_dashboard_launcher_file"
  fi
  if dashboard_port_ready; then
    return 2
  fi
  return 1
}

pwcli_dashboard_running=0
if dashboard_status; then
  pwcli_dashboard_running=1
else
  pwcli_dashboard_result=$?
  if ((pwcli_dashboard_result == 2)); then
    fail "127.0.0.1:9323 is already in use without matching Managed Playwright Dashboard state. Stop that process, then retry."
  fi
  if ((pwcli_dashboard_result == 3)); then
    fail "Managed Playwright Dashboard is still stopping. Wait for the recorded process to exit, then retry."
  fi
fi

pwcli_had_consumer=$pwcli_dashboard_running
pwcli_managed_owner=0
pwcli_owner_session=
pwcli_owner_workspace=
if [[ -f "$pwcli_lease" ]]; then
  pwcli_owner_session="$(sed -n '1p' "$pwcli_lease")"
  pwcli_owner_workspace="$(sed -n '2p' "$pwcli_lease")"
  if [[ "$pwcli_owner_session" == "$pwcli_session" && "$pwcli_owner_workspace" == "$pwcli_workspace" ]]; then
    pwcli_managed_owner=1
  fi
  if [[ "$pwcli_command" == "open" && ("$pwcli_owner_session" != "$pwcli_session" || "$pwcli_owner_workspace" != "$pwcli_workspace") ]]; then
    fail "Managed Playwright Chrome is owned by session '$pwcli_owner_session' in '$pwcli_owner_workspace'. Close that session before opening '$pwcli_session'."
  fi
  pwcli_had_consumer=1
fi

close_chrome_if_unused() {
  if [[ -f "$pwcli_lease" ]]; then
    return
  fi
  local dashboard_result=0
  if dashboard_status; then
    return
  else
    dashboard_result=$?
  fi
  if ((dashboard_result == 2)); then
    fail "refusing to close Chrome while 127.0.0.1:9323 is in use without matching Dashboard state."
  fi
  if ((dashboard_result == 3)); then
    return
  fi
  if [[ ! -f "$pwcli_state_dir/chrome.pid" ]]; then
    return
  fi
  local recorded_pid chrome_status
  recorded_pid="$(cat "$pwcli_state_dir/chrome.pid")"
  chrome_status="$(inspect_chrome || true)"
  if [[ "$chrome_status" == "absent" ]]; then
    rm -f "$pwcli_state_dir/chrome.pid"
    return
  fi
  if [[ ! "$recorded_pid" =~ ^[0-9]+$ || "$chrome_status" != "managed:$recorded_pid" ]]; then
    fail "refusing to close Chrome because recorded Managed Playwright Chrome PID '$recorded_pid' does not match Windows ownership status '${chrome_status:-empty}'. Close the dedicated Chrome manually, then retry."
  fi
  if ! "$pwcli_cdp_close" "$pwcli_cdp_endpoint"; then
    fail "could not close Managed Playwright Chrome through CDP. Close the dedicated Chrome manually; the profile was preserved."
  fi
  local deadline=$((SECONDS + ${PWCLI_CDP_TIMEOUT:-10}))
  while ((SECONDS <= deadline)); do
    if ! chrome_status="$(inspect_chrome)"; then
      fail "could not inspect Managed Playwright Chrome after Browser.close. Close the dedicated Chrome manually; ownership state was preserved."
    fi
    if [[ "$chrome_status" == "absent" ]]; then
      rm -f "$pwcli_state_dir/chrome.pid"
      return
    fi
    if [[ "$chrome_status" != "managed:$recorded_pid" ]]; then
      fail "Managed Playwright Chrome ownership changed while closing (status: ${chrome_status:-empty}). Close the dedicated Chrome manually; ownership state was preserved."
    fi
    sleep 0.2
  done
  fail "Managed Playwright Chrome did not exit before the timeout (status: ${chrome_status:-empty}). Close the dedicated Chrome manually; ownership state was preserved."
}

if [[ "$pwcli_command" == "delete-data" ]]; then
  if ((pwcli_managed_owner)); then
    fail "will not delete Managed Playwright Chrome data automatically. First close the session and Dashboard, then manually remove %LOCALAPPDATA%\\aiakos\\playwright-cli\\chrome-profile if a full reset is intended."
  fi
  exec "$pwcli_upstream" "$@"
fi

if [[ "$pwcli_command" == "close" ]]; then
  "$pwcli_upstream" "$@"
  if ((pwcli_managed_owner)); then
    rm -f "$pwcli_lease"
    close_chrome_if_unused
  fi
  exit 0
fi

if [[ "$pwcli_command" == "close-all" || "$pwcli_command" == "kill-all" ]]; then
  "$pwcli_upstream" "$@"
  if [[ "$pwcli_command" == "kill-all" ]]; then
    rm -f "$pwcli_lease"
  elif [[ -f "$pwcli_lease" && "$pwcli_owner_workspace" == "$pwcli_workspace" ]]; then
    rm -f "$pwcli_lease"
  fi
  close_chrome_if_unused
  exit 0
fi

if ((pwcli_show_kill)); then
  pwcli_dashboard_pid=
  if [[ -f "$pwcli_dashboard_pid_file" ]]; then
    pwcli_dashboard_pid="$(cat "$pwcli_dashboard_pid_file")"
  fi
  "$pwcli_upstream" "$@"
  pwcli_kill_deadline=$((SECONDS + ${PWCLI_DASHBOARD_STOP_TIMEOUT:-5}))
  while [[ "$pwcli_dashboard_pid" =~ ^[0-9]+$ ]] &&
    kill -0 "$pwcli_dashboard_pid" 2>/dev/null &&
    ((SECONDS <= pwcli_kill_deadline)); do
    sleep 0.1
  done
  if [[ "$pwcli_dashboard_pid" =~ ^[0-9]+$ ]] &&
    kill -0 "$pwcli_dashboard_pid" 2>/dev/null; then
    fail "Managed Playwright Dashboard did not exit before the timeout. Its process identity and Chrome ownership state were preserved."
  fi
  rm -f \
    "$pwcli_dashboard_pid_file" \
    "$pwcli_dashboard_start_time_file" \
    "$pwcli_dashboard_launcher_file" \
    "$pwcli_dashboard_fifo"
  close_chrome_if_unused
  exit 0
fi

if ((pwcli_show_annotate)) && ((pwcli_managed_owner == 0)); then
  if [[ -f "$pwcli_lease" ]]; then
    fail "annotation requires the lease-owning session '$pwcli_owner_session' in '$pwcli_owner_workspace'."
  fi
  fail "annotation requires an open Managed Playwright Chrome session."
fi

pwcli_network_mode="$("$pwcli_wslinfo" --networking-mode 2>/dev/null || true)"
if [[ "$pwcli_network_mode" != "mirrored" ]]; then
  fail "Managed Playwright Chrome requires WSL2 mirrored networking. Set [wsl2] networkingMode=mirrored in %UserProfile%\\.wslconfig, run wsl.exe --shutdown, restart WSL, and verify with: wslinfo --networking-mode"
fi

prepare_powershell

ensure_chrome() {
  local status
  status="$(inspect_chrome || true)"
  case "$status" in
  managed:*)
    if ((pwcli_had_consumer == 0)); then
      fail "an exact Managed Playwright Chrome process is already running without matching state in this WSL runtime. Close that dedicated Chrome manually, then retry."
    fi
    ;;
  absent)
    powershell_action Start >/dev/null
    ;;
  chrome-missing)
    fail "Windows Google Chrome was not found. Install the stable Windows Chrome release, then retry."
    ;;
  port-conflict:*)
    fail "127.0.0.1:9222 is owned by a process that is not Managed Playwright Chrome. Stop that process or free the port; it will not be replaced automatically."
    ;;
  profile-conflict:*)
    fail "the Managed Playwright Chrome profile is open with different launch arguments. Close that dedicated Chrome manually, then retry."
    ;;
  *)
    fail "could not inspect Windows Chrome ownership (status: ${status:-empty}). Verify PowerShell and retry."
    ;;
  esac

  local deadline=$((SECONDS + ${PWCLI_CDP_TIMEOUT:-10}))
  while ((SECONDS <= deadline)); do
    status="$(inspect_chrome || true)"
    if [[ "$status" == managed:* ]] && cdp_ready; then
      printf '%s\n' "${status#managed:}" >"$pwcli_state_dir/chrome.pid"
      return
    fi
    sleep 0.2
  done
  fail "Managed Playwright Chrome did not expose CDP at $pwcli_cdp_endpoint before the timeout. Close the dedicated Chrome, verify port 9222 is free, and retry."
}

ensure_chrome

if [[ "$pwcli_command" == "open" ]]; then
  pwcli_created_lease=0
  if ((pwcli_managed_owner == 0)); then
    printf '%s\n%s\n' "$pwcli_session" "$pwcli_workspace" >"$pwcli_lease"
    pwcli_created_lease=1
  fi
  pwcli_config="$pwcli_state_dir/managed-cli-config.json"
  printf '%s\n' \
    '{' \
    '  "browser": {' \
    '    "browserName": "chromium",' \
    '    "cdpEndpoint": "http://127.0.0.1:9222",' \
    '    "cdpTimeout": 10000' \
    '  }' \
    '}' >"$pwcli_config"

  if PWTEST_CLI_MANAGED_CHROME=1 "$pwcli_upstream" "$@" "--config=$pwcli_config"; then
    exit 0
  else
    pwcli_upstream_status=$?
    if ((pwcli_created_lease)); then
      rm -f "$pwcli_lease"
      close_chrome_if_unused
    fi
    exit "$pwcli_upstream_status"
  fi
fi

if ((pwcli_dashboard_running == 0)); then
  if ! command -v setsid >/dev/null 2>&1; then
    fail "setsid is required to keep the Managed Playwright Dashboard in the background."
  fi
  rm -f "$pwcli_dashboard_fifo" "$pwcli_dashboard_launcher_file"
  mkfifo "$pwcli_dashboard_fifo"
  setsid "${BASH:-bash}" "$0" \
    __pwcli-dashboard-daemon \
    "$pwcli_dashboard_fifo" \
    "$pwcli_dashboard_launcher_file" \
    "$pwcli_lock_fd" \
    >>"$pwcli_dashboard_log" 2>&1 &
  pwcli_dashboard_bootstrap_pid=$!
  pwcli_dashboard_launcher_pid=
  pwcli_dashboard_pid=

  pwcli_dashboard_deadline=$((SECONDS + ${PWCLI_DASHBOARD_TIMEOUT:-10}))
  while ((SECONDS <= pwcli_dashboard_deadline)); do
    if [[ -z "$pwcli_dashboard_launcher_pid" && -f "$pwcli_dashboard_launcher_file" ]]; then
      pwcli_dashboard_launcher_pid="$(cat "$pwcli_dashboard_launcher_file")"
    fi
    if [[ "$pwcli_dashboard_launcher_pid" =~ ^[0-9]+$ ]] && dashboard_port_ready; then
      pwcli_dashboard_pid="$(
        dashboard_listener_for_launcher "$pwcli_dashboard_launcher_pid" || true
      )"
      if [[ -n "$pwcli_dashboard_pid" ]]; then
        pwcli_dashboard_start_time="$(process_start_time "$pwcli_dashboard_pid")"
        printf '%s\n' "$pwcli_dashboard_pid" >"$pwcli_dashboard_pid_file"
        printf '%s\n' "$pwcli_dashboard_start_time" >"$pwcli_dashboard_start_time_file"
        rm -f "$pwcli_dashboard_launcher_file"
        pwcli_dashboard_running=1
        break
      fi
    fi
    sleep 0.2
  done
  if ((pwcli_dashboard_running == 0)); then
    if [[ "$pwcli_dashboard_launcher_pid" =~ ^[0-9]+$ ]]; then
      terminate_dashboard_session "$pwcli_dashboard_launcher_pid"
    else
      kill "$pwcli_dashboard_bootstrap_pid" 2>/dev/null || true
    fi
    rm -f \
      "$pwcli_dashboard_pid_file" \
      "$pwcli_dashboard_start_time_file" \
      "$pwcli_dashboard_launcher_file" \
      "$pwcli_dashboard_fifo"
    close_chrome_if_unused
    fail "Managed Playwright Dashboard did not start on http://127.0.0.1:9323/. Inspect $pwcli_dashboard_log and verify port 9323 is free."
  fi
fi

"$pwcli_curl" \
  --fail \
  --silent \
  --show-error \
  --max-time 5 \
  --request PUT \
  "$pwcli_cdp_endpoint/json/new?http%3A%2F%2Flocalhost%3A9323%2F" >/dev/null

release_lock
trap - EXIT
"$pwcli_upstream" "$@"
