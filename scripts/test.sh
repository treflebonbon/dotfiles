#!/usr/bin/env bash
set -euo pipefail

mkdir -p tmp
log_dir=$(mktemp -d tmp/test-run.XXXXXX)
active_runner_pid=
trap 'printf "%s\n" "$?" >"$log_dir/exit-code"' EXIT
stop() {
  local status=$1
  trap - INT TERM
  if [[ -n "$active_runner_pid" ]]; then
    case " $(jobs -pr) " in
    *" $active_runner_pid "*) kill -TERM "$active_runner_pid" 2>/dev/null || : ;;
    esac
    wait "$active_runner_pid" 2>/dev/null || :
  fi
  exit "$status"
}
trap 'stop 130' INT
trap 'stop 143' TERM
: >"$log_dir/tap.log"
printf 'テストログ: %s/tap.log\n' "$log_dir" >&2

run_logged() {
  local log_file=$1
  local tee_mode=$2
  shift 2
  local signal_status=

  trap 'signal_status=130' INT
  trap 'signal_status=143' TERM
  python3 -I - "$log_file" "$tee_mode" "$@" 3<&0 <<'PY' &
import os
import signal
import subprocess
import sys
import time

log_file, tee_mode, *command = sys.argv[1:]
interrupted = None

def handle_signal(signum, _frame):
    global interrupted
    interrupted = signum

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)

def process_info(pid):
    if os.path.isdir("/proc"):
        try:
            fields = open(f"/proc/{pid}/stat", encoding="ascii").read().rsplit(")", 1)[1].split()
            return fields[0], int(fields[1]), int(fields[2]), fields[19]
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError, ValueError):
            return None
    return ps_process_info(pid)

def ps_processes(pid=None):
    command = ["ps", "-ww"]
    command.extend(["-A"] if pid is None else ["-p", str(pid)])
    command.extend(["-o", "pid=", "-o", "ppid=", "-o", "pgid=", "-o", "stat=", "-o", "lstart="])
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    try:
        output = subprocess.run(command, capture_output=True, text=True, env=env, check=False).stdout
    except OSError:
        return {}
    processes = {}
    for line in output.splitlines():
        fields = line.split(None, 4)
        if len(fields) == 5:
            try:
                processes[int(fields[0])] = (fields[3], int(fields[1]), int(fields[2]), fields[4])
            except ValueError:
                continue
    return processes

def ps_process_info(pid):
    return ps_processes(pid).get(pid)

if ps_process_info(os.getpid()) is None:
    raise SystemExit("ps から runner の process 情報を取得できない")

def process_tree(root):
    # shortcut: 停止前に再親化済みの子は追跡外、その子も停止対象になったら実行中の追跡へ広げる。
    processes = ps_processes()
    tree = {root}
    while True:
        children = {pid for pid, info in processes.items() if info[1] in tree}
        if children <= tree:
            break
        tree.update(children)
    return {
        pid: (process_info(pid) or processes[pid])[3]
        for pid in tree
        if pid in processes
    }

def signal_process(pid, identity, signum):
    info = process_info(pid)
    if info is not None and info[3] == identity and not info[0].startswith("Z"):
        try:
            os.kill(pid, signum)
        except ProcessLookupError:
            pass

def stop_process_group(signum):
    known = process_tree(process.pid)

    def stop_descendants(new_only=False):
        current = process_tree(process.pid)
        for pid, identity in current.items():
            if pid != process.pid and (not new_only or known.get(pid) != identity):
                signal_process(pid, identity, signal.SIGTERM)
            known[pid] = identity

    for pid, identity in known.items():
        if pid != process.pid:
            signal_process(pid, identity, signal.SIGTERM)
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 0.25
    while time.monotonic() < deadline:
        stop_descendants(new_only=True)
        time.sleep(0.02)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    for pid, identity in known.items():
        if pid != process.pid:
            signal_process(pid, identity, signal.SIGKILL)
    process.wait()

    deadline = time.monotonic() + 0.5
    while time.monotonic() < deadline:
        survivors = []
        for pid, identity in known.items():
            info = process_info(pid) if pid != process.pid else None
            if info is not None and info[3] == identity and info[0] != "Z":
                survivors.append(pid)
        if not survivors:
            break
        for pid in survivors:
            signal_process(pid, known[pid], signal.SIGKILL)
        time.sleep(0.02)
    raise SystemExit(128 + signum)

process = subprocess.Popen(
    [
        "bash", "-o", "pipefail", "-c",
        'log_file=$1; tee_mode=$2; shift 2; if [[ "$tee_mode" == append ]]; then "$@" 2>&1 | tee -a "$log_file"; else "$@" 2>&1 | tee "$log_file"; fi',
        "test.sh", log_file, tee_mode, *command,
    ],
    stdin=3,
    start_new_session=True,
)

while True:
    if interrupted is not None:
        stop_process_group(interrupted)
    result = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    if result is not None and result.si_pid:
        if interrupted is not None:
            stop_process_group(interrupted)
        signal_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
        if interrupted is not None:
            signal.pthread_sigmask(signal.SIG_SETMASK, signal_mask)
            stop_process_group(interrupted)
        status = process.wait()
        signal.pthread_sigmask(signal.SIG_SETMASK, signal_mask)
        if interrupted is not None:
            raise SystemExit(128 + interrupted)
        raise SystemExit(status if status >= 0 else 128 - status)
    time.sleep(0.02)
PY
  active_runner_pid=$!
  trap 'stop 130' INT
  trap 'stop 143' TERM
  if [[ -n "$signal_status" ]]; then
    stop "$signal_status"
  fi

  trap 'if [[ -z "$signal_status" ]]; then signal_status=130; fi' INT
  trap 'if [[ -z "$signal_status" ]]; then signal_status=143; fi' TERM
  local status
  while :; do
    if [[ -n "$signal_status" ]]; then
      case " $(jobs -pr) " in
      *" $active_runner_pid "*) kill -TERM "$active_runner_pid" 2>/dev/null || : ;;
      *) break ;;
      esac
    fi
    if wait "$active_runner_pid"; then
      status=0
    else
      status=$?
    fi
    [[ -n "$signal_status" ]] || break
  done
  active_runner_pid=
  trap 'stop 130' INT
  trap 'stop 143' TERM
  if [[ -n "$signal_status" ]]; then
    status=$signal_status
  fi
  return "$status"
}

if ! python3 -I - >"$log_dir/environment" 2>"$log_dir/setup.log" <<'PY'
import shutil
import sys
from pathlib import Path

with_env = shutil.which("with-env")
print(f"python3: {Path(sys.executable).resolve()}")
print(f"with-env: {Path(with_env).resolve() if with_env else '未検出'}")
try:
    import dotenv.parser
except ImportError as error:
    raise SystemExit(f"python3 -I: {error}") from None
if not with_env or not Path(with_env).resolve().is_relative_to("/nix/store"):
    raise SystemExit("with-env が Nix store の実行ファイルに解決されない")
PY
then
  cat "$log_dir/setup.log" >&2
  printf '%s\n' 'テスト環境が不完全です。docs/conventions.md の devShell 手順で再実行してください。' | tee -a "$log_dir/setup.log" >&2
  exit 1
fi

run_logged "$log_dir/setup.log" append bun install --frozen-lockfile
run_logged "$log_dir/tap.log" truncate bats --tap --print-output-on-failure tests/ "$@"
python3 -I - "$log_dir/tap.log" <<'PY'
import re
import sys

plans = []
results = 0
invalid = False
with open(sys.argv[1], encoding="utf-8") as log:
    for line in log:
        if plan := re.fullmatch(r"1\.\.([0-9]+)\s*", line):
            plans.append(int(plan[1]))
        elif result := re.match(r"(not ok|ok) ([0-9]+)(?:\s|$)", line):
            results += 1
            invalid |= int(result[2]) != results or result[1] == "not ok"
        elif line.startswith("Bail out!"):
            invalid = True
if plans != [results] or invalid:
    raise SystemExit(f"TAP が未完了または不正です: 計画 {plans}, 結果 {results} ({sys.argv[1]})")
PY
