#!/usr/bin/env bats

setup() {
  [ "$(uname -s)" = Linux ] || skip "protected entry requires Linux/WSL2"
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SOURCE="$BATS_TEST_TMPDIR/work"
  local base="$BATS_TEST_TMPDIR/base"
  export FIXTURE_BIN="$BATS_TEST_TMPDIR/bin"
  export FIXTURE_LOG="$BATS_TEST_TMPDIR/commands.jsonl"
  export FIXTURE_PW_PACKAGE="${MANAGED_CHROME_OWNER%/bin/managed-chrome-owner}"
  mkdir -p "$base/scripts" "$FIXTURE_BIN"
  cp "$ROOT/scripts/verification_env.py" "$ROOT/scripts/verify-ai-tools.py" "$base/scripts/"
  if [ -f "$ROOT/scripts/run-canonical.py" ]; then
    cp "$ROOT/scripts/run-canonical.py" "$base/scripts/"
  fi
  cat >"$base/scripts/verify-canonical.py" <<'PY'
import json, os, sys
import time
from pathlib import Path
source = Path(__file__).resolve().parents[1]
record = source / 'tmp/canonical-run.fixture'
record.mkdir(parents=True)
if os.environ.get('FIXTURE_MODE') != 'no-receipt':
    print('検証記録: ' + ('/tmp/foreign-canonical' if os.environ.get('FIXTURE_MODE') == 'wrong-path' else str(record)), flush=True)
if os.environ.get('FIXTURE_MODE') == 'gate-hang':
    (record/'ready').touch()
    time.sleep(60)
count = 2 if os.environ.get('FIXTURE_MODE') == 'wrong-count' else 3
status = 7 if os.environ.get('FIXTURE_MODE') == 'gate-failure' else 0
(record/'result.json').write_text(json.dumps({'exit_code':status,'tap':{'plan':count}}))
(record/'runtime.json').write_text(json.dumps({key:os.environ[key] for key in
    ('IMPECCABLE_HOOK_RUNTIME','IMPECCABLE_BIN','TEST_PLAYWRIGHT_PACKAGE')}))
raise SystemExit(status)
PY
  printf 'tmp/\n' >"$base/.gitignore"
  git init --quiet --initial-branch=main "$base"
  (
    cd "$base"
    git add .
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m fixture
    git worktree add --quiet -b task "$SOURCE"
  )
  export HOME="$BATS_TEST_TMPDIR/original-home"
  mkdir -p "$HOME/.agents/skills/impeccable/scripts"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.agents/skills/impeccable/scripts/impeccable"
  chmod +x "$HOME/.agents/skills/impeccable/scripts/impeccable"
  unset IMPECCABLE_HOOK_RUNTIME
  printf preserved >"$HOME/sentinel"
  export FIXTURE_SENTINEL="$HOME/sentinel"
  cat >"$FIXTURE_BIN/nix" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['FIXTURE_LOG'], 'a') as log:
    log.write(json.dumps({'args':args,'HOME':os.environ['HOME']})+'\n')
if args[0] == 'eval':
    if os.environ.get('FIXTURE_MODE') == 'host-write':
        Path(os.environ['FIXTURE_SENTINEL']).write_text('changed')
    print(json.dumps([{'name':name,'version':'fixture',
        'path':str(Path(os.environ['FIXTURE_BIN'])/name)}
        for name in ('claude','codex','copilot','agy','apm','herdr')]))
elif args[0] == 'build':
    if os.environ.get('FIXTURE_MODE') == 'build-failure':
        sys.exit(17)
    print('invalid-output' if os.environ.get('FIXTURE_MODE') == 'bad-output'
          else os.environ['FIXTURE_PW_PACKAGE'])
    if os.environ.get('FIXTURE_MODE') == 'multi-output':
        print(os.environ['FIXTURE_PW_PACKAGE'])
else:
    command = args[args.index('--command')+1:]
    os.execvpe(command[0], command, os.environ)
PY
  cat >"$FIXTURE_BIN/bats" <<'SH'
#!/bin/sh
[ "$1" = --count ] || exit 1
if [ "${FIXTURE_MODE:-}" = bad-count ]; then
  printf 'bad\n'
else
  printf '3\n'
fi
SH
  local tool
  for tool in claude codex copilot agy apm herdr; do
    printf '#!/bin/sh\nprintf "fixture\\n"\n' >"$FIXTURE_BIN/$tool"
  done
  chmod +x "$FIXTURE_BIN"/*
  export PATH="$FIXTURE_BIN:$PATH"
}

entry() {
  run python3 "$SOURCE/scripts/run-canonical.py" --shell wsl
  RECORD="$(sed -n 's/^環境準備の記録: //p' <<<"$output")"
}

@test "canonical entry resolves installed runtime and calls the existing gate once" {
  entry
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/sentinel")" = preserved ]
  python3 - "$SOURCE" "$RECORD" "$HOME" <<'PY'
import json, os, sys
from pathlib import Path
source, root, home = map(Path, sys.argv[1:])
result = json.loads((root/'result.json').read_text())
assert result['exit_code'] == 0
assert Path((root/'canonical-path').read_text().strip()) == source/'tmp/canonical-run.fixture'
runtime = json.loads((source/'tmp/canonical-run.fixture/runtime.json').read_text())
assert runtime['IMPECCABLE_HOOK_RUNTIME'] == str(home/'.agents/skills/impeccable/scripts/impeccable')
assert runtime['TEST_PLAYWRIGHT_PACKAGE'] == os.environ['FIXTURE_PW_PACKAGE']
rows = [json.loads(line) for line in Path(os.environ['FIXTURE_LOG']).read_text().splitlines()]
assert all(row['HOME'] != str(home) for row in rows)
assert sum('--file' in row['args'] for row in rows) == 1
PY
}

@test "canonical entry stops before Nix when the installed runtime is missing" {
  export IMPECCABLE_HOOK_RUNTIME="$BATS_TEST_TMPDIR/missing"
  entry
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE_LOG" ]
}

@test "canonical entry protects the original HOME during the first Nix evaluation" {
  export FIXTURE_MODE=host-write
  entry
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/sentinel")" = preserved ]
  [ ! -e "$SOURCE/tmp/canonical-run.fixture" ]
}

@test "canonical entry suppresses the gate when package preparation fails" {
  export FIXTURE_MODE=build-failure
  entry
  [ "$status" -ne 0 ]
  [ ! -e "$SOURCE/tmp/canonical-run.fixture" ]
}

@test "canonical entry rejects malformed preparation output" {
  export FIXTURE_MODE=bad-output
  entry
  [ "$status" -ne 0 ]
  [ ! -e "$SOURCE/tmp/canonical-run.fixture" ]
}

@test "canonical entry preserves the gate failure without rerunning it" {
  export FIXTURE_MODE=gate-failure
  entry
  [ "$status" -eq 7 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 7 ]
  [ -f "$SOURCE/tmp/canonical-run.fixture/result.json" ]
}

@test "canonical entry rejects a gate result that does not cover the source test count" {
  export FIXTURE_MODE=wrong-count
  entry
  [ "$status" -ne 0 ]
  [ -f "$SOURCE/tmp/canonical-run.fixture/result.json" ]
}

@test "canonical preparation records a count timeout and suppresses the gate" {
  python3 - "$SOURCE" "$BATS_TEST_TMPDIR/count-timeout" <<'PY'
import importlib.util, json, os, subprocess, sys
from pathlib import Path
from unittest.mock import patch
source, record = map(Path, sys.argv[1:])
record.mkdir()
sys.path.insert(0, str(source/'scripts'))
spec = importlib.util.spec_from_file_location('preparation', source/'scripts/run-canonical.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def command(argv, **kwargs):
    if argv[0] == 'nix':
        return os.environ['FIXTURE_PW_PACKAGE']+'\n'
    assert argv == ['bats', '--count', 'tests/']
    assert kwargs.get('timeout') == 300
    raise subprocess.TimeoutExpired(argv, kwargs['timeout'])

with patch.object(module.subprocess, 'check_output', side_effect=command), \
     patch.object(module.subprocess, 'Popen') as gate:
    status = module.prepare(source, record, Path.home()/'.agents/skills/impeccable/scripts/impeccable')
    assert status == 1
    gate.assert_not_called()
result = json.loads((record/'result.json').read_text())
assert result['phase'] == 'preparation'
assert result['status'] == 'failed' and result['exit_code'] == 1
assert result['canonical'] is None
assert 'timed out' in result['error']
assert not (record/'canonical-path').exists()
PY
}

@test "canonical entry rejects a gate receipt from a different source directory" {
  export FIXTURE_MODE=wrong-path
  entry
  [ "$status" -ne 0 ]
  [ ! -f "$RECORD/canonical-path" ]
}

@test "canonical entry records interruption and stops its protected child" {
  export FIXTURE_MODE=gate-hang
  python3 "$SOURCE/scripts/run-canonical.py" --shell wsl >"$BATS_TEST_TMPDIR/entry.log" 2>&1 &
  local child=$! iteration
  for ((iteration = 0; iteration < 1200; iteration++)); do
    [ -f "$SOURCE/tmp/canonical-run.fixture/ready" ] && break
    sleep 0.1
  done
  if [ ! -f "$SOURCE/tmp/canonical-run.fixture/ready" ]; then
    kill -TERM "$child" 2>/dev/null || :
    wait "$child" || :
    return 1
  fi
  kill -TERM "$child"
  local result=0
  wait "$child" || result=$?
  [ "$result" -eq 143 ]
  RECORD="$(sed -n 's/^環境準備の記録: //p' "$BATS_TEST_TMPDIR/entry.log")"
  python3 - "$RECORD/result.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
assert result['status'] == 'interrupted'
assert result['exit_code'] == 143
PY
}

@test "canonical entry rejects incomplete runtime, count, and receipt inputs" {
  local mode selected_binary="$IMPECCABLE_BIN"
  for mode in no-binary multi-output bad-count no-receipt; do
    export FIXTURE_MODE="$mode"
    export IMPECCABLE_BIN="$selected_binary"
    if [ "$mode" = no-binary ]; then
      export IMPECCABLE_BIN="$BATS_TEST_TMPDIR/missing-binary"
    fi
    entry
    [ "$status" -ne 0 ] || printf '%s: %s\n' "$mode" "$output" >&3
    [ "$status" -ne 0 ]
    python3 - "$RECORD/result.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
assert result['status'] == 'failed'
assert result['exit_code'] != 0
PY
  done
}
