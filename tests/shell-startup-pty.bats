#!/usr/bin/env bats

setup() {
  HELPER="$BATS_TEST_DIRNAME/helpers/shell-startup-pty.py"
}

teardown() {
  local pid_file pid comm
  for pid_file in "$BATS_TEST_TMPDIR"/*.pid; do
    [ -f "$pid_file" ] || continue
    pid=$(cat "$pid_file")
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    [ "$comm" != sleep ] || kill -KILL "$pid" 2>/dev/null || true
  done
}

@test "PTY helper allows shell startup longer than five seconds" {
  local shell_script="$BATS_TEST_TMPDIR/slow-startup.sh"
  cat >"$shell_script" <<'SH'
#!/bin/sh
/bin/sleep 6
printf 'startup completed\n'
SH

  run python3 "$HELPER" /bin/sh "$shell_script"

  [ "$status" -eq 0 ]
  [[ "$output" == *"startup completed"* ]]
}

@test "PTY helper kills its session after reparenting and bounds pipe-holder drainage" {
  local fixture="$BATS_TEST_TMPDIR/hold-output.py"
  cat >"$fixture" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
print("partial startup output", flush=True)
for name, detach in (("same-session", False), ("other-session", True)):
    pid = os.fork()
    if pid == 0:
        if detach:
            os.setsid()
        (root / f"{name}.pid").write_text(str(os.getpid()))
        os.execl("/bin/sleep", "sleep", "90")
    (root / f"{name}.pid").write_text(str(pid))
PY

  /bin/sleep 90 >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$BATS_TEST_TMPDIR/unrelated.pid"
  run timeout --foreground --kill-after=2 36 \
    python3 "$HELPER" python3 "$fixture" "$BATS_TEST_TMPDIR"

  [ "$status" -eq 1 ]
  local same_pid other_pid same_state other_state
  same_pid=$(cat "$BATS_TEST_TMPDIR/same-session.pid")
  other_pid=$(cat "$BATS_TEST_TMPDIR/other-session.pid")
  same_state=$(ps -o stat= -p "$same_pid" 2>/dev/null | tr -d '[:space:]')
  other_state=$(ps -o stat= -p "$other_pid" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$same_state" || "$same_state" == Z* ]]
  [[ "$other_state" != Z* && -n "$other_state" ]]
  [[ "$output" == *"30秒以内"* ]]
  [ "$(grep -Fo 'partial startup output' <<<"$output" | wc -l)" -eq 1 ]
  kill -0 "$(cat "$BATS_TEST_TMPDIR/unrelated.pid")"
}
