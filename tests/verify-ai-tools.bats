#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PROBE="$PROJECT_ROOT/scripts/verify-ai-tools.py"
  SOURCE="$BATS_TEST_TMPDIR/source"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$SOURCE" "$BIN" "$BATS_TEST_TMPDIR/original-home"
  export AI_FIXTURE_BIN="$BIN"
  export AI_FIXTURE_LOG="$BATS_TEST_TMPDIR/commands.jsonl"
  cat >"$BIN/nix" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['AI_FIXTURE_LOG'], 'a') as log:
    log.write(json.dumps({key: os.environ.get(key) for key in
        ['HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'BROWSER_OWNERSHIP_DIR', 'CODEX_HOME', 'CLAUDE_CONFIG_DIR', 'FORCE_COLOR']}) + '\n')
if sys.argv[1] == 'eval':
    mode = os.environ.get('AI_FIXTURE_MODE')
    if mode == 'eval-failure':
        print('fixture evaluation failed', file=sys.stderr)
        sys.exit(17)
    if mode == 'eval-signal':
        print('fixture evaluation signal', file=sys.stderr, flush=True)
        os.kill(os.getpid(), 15)
    if mode == 'invalid-json':
        print('invalid-json')
        sys.exit(0)
    metadata = [{'name': name, 'path': os.environ['AI_FIXTURE_BIN'] + '/' + name, 'version': '0.162.1'}
        for name in ['claude', 'codex', 'copilot', 'agy', 'apm', 'herdr']]
    if mode == 'missing': metadata.pop()
    if mode == 'duplicate': metadata[-1] = metadata[0]
    if mode == 'wrong-type': metadata = None
    if mode == 'missing-path': del metadata[0]['path']
    print(json.dumps(metadata))
else:
    if os.environ.get('AI_FIXTURE_MODE') == 'startup-signal':
        print('fixture startup signal', file=sys.stderr, flush=True)
        os.kill(os.getpid(), 15)
    Path(os.environ['HOME'], '.agents').mkdir(exist_ok=True)
    Path(os.environ['HOME'], '.agents', 'hook').write_text('isolated')
    command = sys.argv[sys.argv.index('--command') + 1:]
    os.execvpe(command[0], command, os.environ)
PY
  local tool
  for tool in claude codex copilot agy apm herdr; do
    printf '#!/usr/bin/env bash\nprintf "fixture 0.162.1\\n"\n' >"$BIN/$tool"
  done
  chmod +x "$BIN"/*
}

@test "AI candidate verification isolates shell hooks and runs the requested command after output checks" {
  run env PATH="$BIN:$PATH" HOME="$BATS_TEST_TMPDIR/original-home" \
    CODEX_HOME=ambient CLAUDE_CONFIG_DIR=ambient FORCE_COLOR=1 \
    XDG_CACHE_HOME=ambient XDG_STATE_HOME=ambient \
    python3 "$PROBE" "$SOURCE" --shell wsl -- bash -c 'printf "verified-command\n"'

  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS: 6 CLI'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/original-home/.agents" ]
  python3 - "$AI_FIXTURE_LOG" "$SOURCE" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert len(rows)==3
assert len({row['HOME'] for row in rows})==1
home=Path(rows[0]['HOME'])
assert home.is_relative_to(Path(sys.argv[2])/'tmp')
assert (home/'.agents/hook').read_text()=='isolated'
assert 'verified-command' in (home.parent/'startup.log').read_text()
for row in rows:
    assert row['CODEX_HOME'] is row['CLAUDE_CONFIG_DIR'] is row['FORCE_COLOR'] is None
    assert row['XDG_CONFIG_HOME']==str(home.parent/'config')
    assert row['XDG_DATA_HOME']==str(home.parent/'data')
    assert row['XDG_CACHE_HOME']==str(home.parent/'cache')
    assert row['XDG_STATE_HOME']==str(home.parent/'state')
    assert row['XDG_RUNTIME_DIR']==str(home.parent/'runtime')
PY
}

@test "AI candidate verification keeps the shared browser ownership root before isolating XDG" {
  local shared="$BATS_TEST_TMPDIR/shared-ownership"
  run env PATH="$BIN:$PATH" BROWSER_OWNERSHIP_DIR="$shared" \
    XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/original-runtime" \
    python3 "$PROBE" "$SOURCE" -- bash -c 'test "$BROWSER_OWNERSHIP_DIR" = "$1"' -- "$shared"

  [ "$status" -eq 0 ]
  python3 - "$AI_FIXTURE_LOG" "$shared" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert len(rows)==3
assert all(row['BROWSER_OWNERSHIP_DIR']==sys.argv[2] for row in rows)
assert all(row['XDG_RUNTIME_DIR']!=str(Path(sys.argv[2]).parent/'original-runtime') for row in rows)
PY
}

@test "AI candidate verification resolves browser ownership from the original runtime fallback" {
  local mode expected case_source
  for mode in xdg tmp default; do
    case_source="$SOURCE/$mode"
    mkdir -p "$case_source"
    case "$mode" in
    xdg)
      expected="$BATS_TEST_TMPDIR/original-runtime/browser-ownership"
      run env -u BROWSER_OWNERSHIP_DIR PATH="$BIN:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/original-runtime" \
        python3 "$PROBE" "$case_source" -- bash -c 'test "$BROWSER_OWNERSHIP_DIR" = "$1"' -- "$expected"
      ;;
    tmp)
      expected="$BATS_TEST_TMPDIR/browser-ownership"
      run env -u BROWSER_OWNERSHIP_DIR -u XDG_RUNTIME_DIR PATH="$BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
        python3 "$PROBE" "$case_source" -- bash -c 'test "$BROWSER_OWNERSHIP_DIR" = "$1"' -- "$expected"
      ;;
    default)
      expected=/tmp/browser-ownership
      run env -u BROWSER_OWNERSHIP_DIR -u XDG_RUNTIME_DIR -u TMPDIR PATH="$BIN:$PATH" \
        python3 "$PROBE" "$case_source" -- bash -c 'test "$BROWSER_OWNERSHIP_DIR" = "$1"' -- "$expected"
      ;;
    esac
    [ "$status" -eq 0 ]
  done
  python3 - "$AI_FIXTURE_LOG" "$BATS_TEST_TMPDIR" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert len(rows)==9
expected=[str(Path(sys.argv[2])/'original-runtime/browser-ownership'),
          str(Path(sys.argv[2])/'browser-ownership'), '/tmp/browser-ownership']
for start, value in zip((0,3,6), expected):
    assert all(row['BROWSER_OWNERSHIP_DIR']==value for row in rows[start:start+3])
PY
}

@test "AI candidate verification rejects an older output even when its version is identical" {
  mkdir -p "$BATS_TEST_TMPDIR/old-bin"
  cp "$BIN/codex" "$BATS_TEST_TMPDIR/old-bin/codex"

  run env PATH="$BATS_TEST_TMPDIR/old-bin:$BIN:$PATH" python3 "$PROBE" "$SOURCE" \
    -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  grep -q 'codex のoutput不一致' "$SOURCE"/tmp/ai-tools-*/startup.log
}

@test "AI candidate verification preserves the requested command failure in its evidence" {
  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE" -- bash -c 'exit 23'

  [ "$status" -eq 23 ]
  [ "$(cat "$SOURCE"/tmp/ai-tools-*/exit-code)" -eq 23 ]
}

@test "AI candidate verification records invalid metadata and suppresses the requested command" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=invalid-json \
    python3 "$PROBE" "$SOURCE" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  [ "$(cat "$SOURCE"/tmp/ai-tools-*/exit-code)" -eq 1 ]
  grep -q 'invalid-json' "$SOURCE"/tmp/ai-tools-*/metadata.json
  grep -q 'metadata' "$SOURCE"/tmp/ai-tools-*/evaluation.log
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 1 ]
}

@test "AI candidate verification rejects incomplete or malformed metadata before shell startup" {
  local mode case_source
  for mode in missing duplicate wrong-type missing-path; do
    case_source="$SOURCE/$mode"
    mkdir -p "$case_source"
    run env PATH="$BIN:$PATH" AI_FIXTURE_MODE="$mode" \
      python3 "$PROBE" "$case_source" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

    [ "$status" -eq 1 ]
    [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
    [ ! -e "$case_source"/tmp/ai-tools-*/startup.log ]
    [ "$(cat "$case_source"/tmp/ai-tools-*/exit-code)" -eq 1 ]
    grep -q 'metadata不正' "$case_source"/tmp/ai-tools-*/evaluation.log
  done
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 4 ]
}

@test "AI candidate verification preserves evaluation failure evidence without starting shells" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=eval-failure \
    python3 "$PROBE" "$SOURCE" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 17 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  [ ! -e "$SOURCE"/tmp/ai-tools-*/startup.log ]
  [ "$(cat "$SOURCE"/tmp/ai-tools-*/exit-code)" -eq 17 ]
  grep -q 'fixture evaluation failed' "$SOURCE"/tmp/ai-tools-*/evaluation.log
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 1 ]
}

@test "AI candidate verification preserves version failure evidence and suppresses the requested command" {
  printf '#!/usr/bin/env bash\nprintf "fixture version failed\\n" >&2\nexit 19\n' >"$BIN/codex"

  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE" \
    -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 19 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  [ "$(cat "$SOURCE"/tmp/ai-tools-*/exit-code)" -eq 19 ]
  grep -q 'fixture version failed' "$SOURCE"/tmp/ai-tools-*/startup.log
}

@test "AI candidate verification reports signal termination consistently in its exit status and evidence" {
  local mode case_source
  for mode in eval-signal startup-signal; do
    case_source="$SOURCE/$mode"
    mkdir -p "$case_source"
    run env PATH="$BIN:$PATH" AI_FIXTURE_MODE="$mode" \
      python3 "$PROBE" "$case_source" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

    [ "$status" -eq 143 ]
    [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
    [ "$(cat "$case_source"/tmp/ai-tools-*/exit-code)" -eq 143 ]
    grep -q 'fixture .* signal' "$case_source"/tmp/ai-tools-*/*.log
  done
}
