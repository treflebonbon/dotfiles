#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  BUN_BIN="$(command -v bun)"
  export RUN_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$RUN_ROOT/scripts"
  cp "$BATS_TEST_DIRNAME/../package.json" "$RUN_ROOT/"
  if [ -f "$BATS_TEST_DIRNAME/../scripts/test.sh" ]; then
    cp "$BATS_TEST_DIRNAME/../scripts/test.sh" "$RUN_ROOT/scripts/"
  fi
  ln -s "$(command -v python3)" "$TEST_BIN_DIR/python3"
  ln -s "$(command -v with-env)" "$TEST_BIN_DIR/with-env"
  stub_cmd bun
  cat >"$TEST_BIN_DIR/bats" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
printf '%s\n' "${BATS_STUB_TAP-$'1..1\nok 1 fixture'}"
exit "${BATS_STUB_STATUS:-0}"
STUB_EOF
  chmod +x "$TEST_BIN_DIR/bats"
  cd "$RUN_ROOT"
}

run_entry() {
  run /usr/bin/env PATH="$TEST_BIN_DIR:$PATH" "$BUN_BIN" run test
}

write_stalling_stub() {
  local name=$1
  cat >"$TEST_BIN_DIR/$name" <<'STUB_EOF'
#!/bin/bash
trap '' TERM
printf '%s\n' "$0 $*" >> "$TEST_LOG"
printf '%s\n' "$FIXTURE_OUTPUT"
printf '%s\n' "$$" > "$FIXTURE_CHILD_PID"
python3 -c 'import os, signal, sys, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)' "$FIXTURE_GRANDCHILD_MARKER" &
printf '%s\n' "$!" > "$FIXTURE_GRANDCHILD_PID"
wait
STUB_EOF
  chmod +x "$TEST_BIN_DIR/$name"
}

run_entry_after_signal() {
  run python3 -I - "$RUN_ROOT/scripts/test.sh" "$RUN_ROOT" "$TEST_BIN_DIR" "$1" <<'PY'
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

script, root, bin_dir = map(Path, sys.argv[1:4])
signal_name = sys.argv[4]
root = root.resolve()
child_pid_file = Path(os.environ["FIXTURE_CHILD_PID"])
grandchild_pid_file = Path(os.environ["FIXTURE_GRANDCHILD_PID"])
grandchild_ready_file = Path(os.environ["FIXTURE_GRANDCHILD_MARKER"])
child_marker = os.environ["FIXTURE_TARGET"].encode()
grandchild_marker = os.environ["FIXTURE_GRANDCHILD_MARKER"].encode()
signal_number = getattr(signal, f"SIG{signal_name}")
env = os.environ.copy()
env["PATH"] = f"{bin_dir}:{env['PATH']}"

def fixture_running(pid_file, marker):
    try:
        pid = int(pid_file.read_text())
        result = subprocess.run(
            ["ps", "-ww", "-p", str(pid), "-o", "stat=", "-o", "args="],
            capture_output=True, text=True, check=False,
        )
        fields = result.stdout.split(None, 1)
    except (OSError, ValueError):
        return False
    return len(fields) == 2 and marker.decode() in fields[1] and not fields[0].startswith("Z")

def stop_fixture(pid_file, marker):
    if fixture_running(pid_file, marker):
        os.kill(int(pid_file.read_text()), signal.SIGKILL)

output = (root / "entry-output.log").open("wb")
entry = subprocess.Popen(
    ["/bin/bash", str(script)], cwd=root, env=env,
    stdout=output, stderr=subprocess.STDOUT,
)
ready_deadline = time.monotonic() + 2
while time.monotonic() < ready_deadline:
    if child_pid_file.exists() and grandchild_pid_file.exists() and grandchild_ready_file.exists():
        break
    if entry.poll() is not None:
        break
    time.sleep(0.01)

if not (fixture_running(child_pid_file, child_marker) and fixture_running(grandchild_pid_file, grandchild_marker)):
    entry.kill()
    entry.wait()
    stop_fixture(child_pid_file, child_marker)
    stop_fixture(grandchild_pid_file, grandchild_marker)
    raise SystemExit("signal fixture did not start its child and grandchild")

started = time.monotonic()
os.kill(entry.pid, signal_number)
try:
    status = entry.wait(timeout=3)
except subprocess.TimeoutExpired:
    stop_fixture(child_pid_file, child_marker)
    stop_fixture(grandchild_pid_file, grandchild_marker)
    try:
        entry.wait(timeout=1)
    except subprocess.TimeoutExpired:
        entry.kill()
        entry.wait()
    output.close()
    raise SystemExit(f"{signal_name} did not stop test.sh within 3 seconds")
elapsed = time.monotonic() - started
output.close()

deadline = time.monotonic() + 1
while time.monotonic() < deadline and (
    fixture_running(child_pid_file, child_marker)
    or fixture_running(grandchild_pid_file, grandchild_marker)
):
    time.sleep(0.01)
if fixture_running(child_pid_file, child_marker) or fixture_running(grandchild_pid_file, grandchild_marker):
    entry_output = (root / "entry-output.log").read_text(errors="replace")
    stop_fixture(child_pid_file, child_marker)
    stop_fixture(grandchild_pid_file, grandchild_marker)
    raise SystemExit(f"signal left a fixture process running; test.sh output={entry_output!r}")
expected_status = 128 + signal_number
if status != expected_status:
    raise SystemExit(f"expected status {expected_status}, got {status}")
print(f"entry_status={status} elapsed={elapsed:.3f}s")
PY
}

@test "テスト入口は隔離 Python の dotenv 不足を install より前に拒否する" {
  # symlink 先の Python を変更せず、fixture の PATH だけ差し替える。
  mv "$TEST_BIN_DIR/python3" "$TEST_BIN_DIR/python3-real"
  stub_cmd python3 1
  run_entry
  assert_failure
  assert_output --partial "テスト環境が不完全"
  assert_log_contains "python3 -I -"
  refute_log_contains "bun install"
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 1 ]
  [ -s "${logs[0]%/tap.log}/setup.log" ]
}

@test "テスト入口は Nix store 外の with-env を install より前に拒否する" {
  mv "$TEST_BIN_DIR/with-env" "$TEST_BIN_DIR/with-env-real"
  stub_cmd with-env
  run_entry
  assert_failure
  assert_output --partial "with-env"
  refute_log_contains "bun install"
  refute_log_contains "/bats "
}

@test "テスト入口は TAP ログと終了コードを保存する" {
  run_entry
  assert_success
  assert_log_contains "bun install --frozen-lockfile"
  assert_log_contains "bats --tap --print-output-on-failure tests/"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "${#logs[@]}" -eq 1 ]
  [ "$(cat "${logs[0]}")" = $'1..1\nok 1 fixture' ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 0 ]
}

@test "テスト入口は Bats の失敗をログ保存で成功に変えない" {
  export BATS_STUB_STATUS=9
  run_entry
  assert_failure 9
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 9 ]
}

@test "テスト入口は Bats が正常終了しても未完了の TAP を拒否する" {
  export BATS_STUB_TAP=$'1..2\nok 1 fixture'
  run_entry
  assert_failure 1
  assert_output --partial "TAP が未完了または不正"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]}")" = "$BATS_STUB_TAP" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 1 ]
}

@test "テスト入口は計画と結果番号が不整合な TAP を拒否する" {
  local tap
  for tap in \
    '' \
    $'ok 1 fixture' \
    $'1..1\n1..1\nok 1 fixture' \
    $'1..1\nok 1 fixture\nok 2 extra' \
    $'1..2\nok 1 fixture\nok 1 duplicate' \
    $'1..2\nok 1 fixture\nok 3 gap' \
    $'1..2\nok 2 reordered\nok 1 fixture'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_failure 1
    assert_output --partial "TAP が未完了または不正"
  done
}

@test "テスト入口は正常終了でも TAP の失敗と中断宣言を拒否する" {
  local tap
  for tap in $'1..1\nnot ok 1 failed' $'1..1\nok 1 fixture\nBail out! interrupted'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_failure 1
    assert_output --partial "TAP が未完了または不正"
  done
}

@test "テスト入口はスキップと診断を含む完了 TAP と対象ゼロ件を受け入れる" {
  local tap
  for tap in $'1..2\nok 1 fixture\n# ok 999 diagnostic\nok 2 optional # skip 未設定' '1..0'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_success
  done
}

@test "テスト入口は frozen install の失敗後に Bats を実行しない" {
  stub_cmd bun 7
  run_entry
  assert_failure 7
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 7 ]
  [ -s "${logs[0]%/tap.log}/environment" ]
}

@test "テスト入口は tee 失敗コードを保持する" {
  stub_cmd tee 8
  run_entry
  assert_failure 8
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 8 ]
}

@test "テスト入口は install に標準入力を渡す" {
  cat >"$TEST_BIN_DIR/bun" <<'STUB_EOF'
#!/bin/bash
printf '%s\n' "$0 $*" >> "$TEST_LOG"
if read -r input; then
  printf 'stdin=%s\n' "$input" >> "$TEST_LOG"
fi
STUB_EOF
  chmod +x "$TEST_BIN_DIR/bun"
  run_entry <<< 'stdin-preserved'
  assert_success
  assert_log_contains "stdin=stdin-preserved"
}

@test "テスト入口は controlling TTY の標準入力を子へ渡す" {
  cat >"$TEST_BIN_DIR/bun" <<'STUB_EOF'
#!/bin/bash
printf '%s\n' "$0 $*" >> "$TEST_LOG"
if read -r input; then
  printf 'stdin=%s\n' "$input" >> "$TEST_LOG"
fi
STUB_EOF
  chmod +x "$TEST_BIN_DIR/bun"
  run python3 -I - "$RUN_ROOT/scripts/test.sh" "$RUN_ROOT" "$TEST_BIN_DIR" <<'PY'
import os
import pty
import select
import signal
import sys
import time
from pathlib import Path

script, root, bin_dir = map(Path, sys.argv[1:4])
env = os.environ.copy()
env["PATH"] = f"{bin_dir}:{env['PATH']}"
pid, terminal = pty.fork()
if pid == 0:
    os.chdir(root)
    os.execve("/bin/bash", ["/bin/bash", str(script)], env)

os.write(terminal, b"tty-preserved\n")
output = bytearray()
deadline = time.monotonic() + 4
status = None
while time.monotonic() < deadline:
    ready, _, _ = select.select([terminal], [], [], 0.05)
    if ready:
        try:
            output.extend(os.read(terminal, 4096))
        except OSError:
            pass
    waited, child_status = os.waitpid(pid, os.WNOHANG)
    if waited:
        status = child_status
        break

if status is None:
    os.kill(pid, signal.SIGTERM)
    try:
        _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        status = None
    raise SystemExit(f"TTY test timed out; output={output.decode(errors='replace')!r}")

try:
    while True:
        ready, _, _ = select.select([terminal], [], [], 0.05)
        if not ready:
            break
        output.extend(os.read(terminal, 4096))
except OSError:
    pass

if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit(f"test.sh exited with status {status}; output={output.decode(errors='replace')!r}")
print(output.decode(errors="replace"), end="")
PY
  assert_success
  assert_log_contains "stdin=tty-preserved"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]}")" = $'1..1\nok 1 fixture' ]
}

@test "テスト入口は停止シグナルを成功として記録しない" {
  cat >"$TEST_BIN_DIR/bats" <<'STUB_EOF'
#!/bin/bash
printf '1..1\n'
kill -TERM "$PPID"
STUB_EOF
  run_entry
  assert_failure 143
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 143 ]
}

@test "テスト入口は TERM 時に install の子孫を停止して終了を待つ" {
  export FIXTURE_CHILD_PID="$RUN_ROOT/term-install-child.pid"
  export FIXTURE_GRANDCHILD_PID="$RUN_ROOT/term-install-grandchild.pid"
  export FIXTURE_GRANDCHILD_MARKER="$RUN_ROOT/term-install-grandchild"
  export FIXTURE_TARGET="$TEST_BIN_DIR/bun"
  export FIXTURE_OUTPUT='install started'
  write_stalling_stub bun
  python3 -I - "$RUN_ROOT/scripts/test.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1])
source = script.read_text()
condition = 'if os.path.isdir("/proc"):'
if source.count(condition) != 1:
    raise SystemExit("expected exactly one Linux process-info branch")
script.write_text(source.replace(condition, "if False:", 1))
PY
  run_entry_after_signal TERM
  assert_success
  assert_output --partial "entry_status=143"
  assert_log_contains "bun install --frozen-lockfile"
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 143 ]
  [ "$(cat "${logs[0]%/tap.log}/setup.log")" = 'install started' ]
}

@test "テスト入口は TERM 時に Bats の子孫を停止して終了を待つ" {
  export FIXTURE_CHILD_PID="$RUN_ROOT/term-bats-child.pid"
  export FIXTURE_GRANDCHILD_PID="$RUN_ROOT/term-bats-grandchild.pid"
  export FIXTURE_GRANDCHILD_MARKER="$RUN_ROOT/term-bats-grandchild"
  export FIXTURE_TARGET="$TEST_BIN_DIR/bats"
  export FIXTURE_OUTPUT='1..1'
  write_stalling_stub bats
  run_entry_after_signal TERM
  assert_success
  assert_output --partial "entry_status=143"
  assert_log_contains "bats --tap --print-output-on-failure tests/"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]}")" = '1..1' ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 143 ]
}

@test "テスト入口は INT を 130 として保存する" {
  export FIXTURE_CHILD_PID="$RUN_ROOT/int-install-child.pid"
  export FIXTURE_GRANDCHILD_PID="$RUN_ROOT/int-install-grandchild.pid"
  export FIXTURE_GRANDCHILD_MARKER="$RUN_ROOT/int-install-grandchild"
  export FIXTURE_TARGET="$TEST_BIN_DIR/bun"
  export FIXTURE_OUTPUT='install started'
  write_stalling_stub bun
  run_entry_after_signal INT
  assert_success
  assert_output --partial "entry_status=130"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 130 ]
}
