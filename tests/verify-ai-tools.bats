#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  [ "$(uname -s)" = Linux ] || skip "write-protected verification requires Linux/WSL2"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PROBE="$PROJECT_ROOT/scripts/verify-ai-tools.py"
  SOURCE="$BATS_TEST_TMPDIR/source"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$SOURCE" "$BIN" "$BATS_TEST_TMPDIR/original-home"
  git init --quiet --initial-branch=main "$BATS_TEST_TMPDIR/original-home/base"
  (
    cd "$BATS_TEST_TMPDIR/original-home/base"
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet --allow-empty -m fixture
    git worktree add --quiet -b task "$SOURCE"
  )
  export AI_FIXTURE_BIN="$BIN"
  export AI_FIXTURE_LOG="$BATS_TEST_TMPDIR/commands.jsonl"
  cat >"$BIN/nix" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['AI_FIXTURE_LOG'], 'a') as log:
    row = {key: os.environ.get(key) for key in
        ['HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'BROWSER_OWNERSHIP_DIR', 'CODEX_HOME', 'CLAUDE_CONFIG_DIR', 'FORCE_COLOR']}
    row['argv'] = sys.argv[1:]
    log.write(json.dumps(row) + '\n')
if sys.argv[1] == 'eval':
    mode = os.environ.get('AI_FIXTURE_MODE')
    if mode == 'write-original-home':
        Path(os.environ['AI_HOST_SENTINEL']).write_text('changed')
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
elif sys.argv[1] == 'build':
    assert sys.argv[sys.argv.index('--max-jobs') + 1] == '0'
    assert sys.argv[sys.argv.index('--builders') + 1] == ''
    assert sys.argv[-1] == str(Path(os.environ['AI_FIXTURE_BIN']).parent)
    if os.environ.get('AI_FIXTURE_MODE') == 'codex-unavailable':
        print('fixture Codex output unavailable without building', file=sys.stderr)
        sys.exit(29)
    if os.environ.get('AI_FIXTURE_MODE') == 'codex-signal':
        print('fixture Codex cache signal', file=sys.stderr, flush=True)
        os.kill(os.getpid(), 15)
    print('fixture Codex output available')
else:
    if os.environ.get('AI_FIXTURE_MODE') == 'startup-signal':
        print('fixture startup signal', file=sys.stderr, flush=True)
        os.kill(os.getpid(), 15)
    if os.environ.get('AI_FIXTURE_MODE') == 'startup-hang':
        Path(os.environ['AI_FIXTURE_LOG'] + '.ready').touch()
        import time
        time.sleep(60)
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

runtime_from_output() {
  sed -n 's/^検証ログ: //p' <<<"$1" | tail -n 1
}

runtime_from_fixture_log() {
  python3 - "$AI_FIXTURE_LOG" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
print(Path(rows[-1]["HOME"]).parent)
PY
}

@test "AI candidate verification protects the original HOME before the first Nix evaluation" {
  local original="$BATS_TEST_TMPDIR/original-home"
  printf 'preserved' >"$original/sentinel"
  run env PATH="$BIN:$PATH" HOME="$original" \
    AI_FIXTURE_MODE=write-original-home AI_HOST_SENTINEL="$original/sentinel" \
    python3 "$PROBE" "$SOURCE" -- bash -c 'printf "must-not-start\n"'

  printf 'original HOME sentinel: %s\n' "$(cat "$original/sentinel")" >&3
  [ "$(cat "$original/sentinel")" = preserved ]
  [ "$status" -ne 0 ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ ! -e "$runtime/startup.log" ]
}

@test "verification entry points do not create import caches beside host launchers" {
  local original="$BATS_TEST_TMPDIR/original-home" name launcher
  for name in verify-ai-tools.py verify-claude-plugin-sync.py; do
    launcher="$original/$name-launcher"
    mkdir -p "$launcher"
    cp "$PROJECT_ROOT/scripts/$name" "$launcher/$name"
    cp "$PROJECT_ROOT/scripts/verification_env.py" "$launcher/verification_env.py"
    run env -u PYTHONDONTWRITEBYTECODE -u PYTHONPYCACHEPREFIX HOME="$original" \
      python3 "$launcher/$name" --help

    [ "$status" -eq 0 ]
    [ ! -e "$launcher/__pycache__" ]
  done
}

@test "AI candidate verification protects the original HOME in the requested command" {
  local original="$BATS_TEST_TMPDIR/original-home"
  printf preserved >"$original/sentinel"
  run env PATH="$BIN:$PATH" HOME="$original" AI_HOST_SENTINEL="$original/sentinel" \
    python3 "$PROBE" "$SOURCE" -- bash -c 'printf changed >"$AI_HOST_SENTINEL"'

  [ "$(cat "$original/sentinel")" = preserved ]
  [ "$status" -ne 0 ]
}

@test "verification commands keep the original HOME protected during shell expansion" {
  local original="$BATS_TEST_TMPDIR/original-home"
  printf preserved >"$original/sentinel"
  printf 'fixture\n' >"$SOURCE/text"
  run env HOME="$original" AI_HOST_SENTINEL="$original/sentinel" \
    python3 "$PROJECT_ROOT/scripts/verification_env.py" "$SOURCE" -- \
    bash -c 'rg -n "$(printf changed >"$AI_HOST_SENTINEL")" text'

  [ "$status" -eq 0 ]
  [ "$(cat "$original/sentinel")" = preserved ]
  [[ "$output" == *"Read-only file system"* ]]
}

@test "AI verification rejects an untrusted sandbox launcher before invoking Nix" {
  printf '#!/bin/sh\ntouch "%s"\n' "$BATS_TEST_TMPDIR/launcher-called" >"$BIN/bwrap"
  chmod +x "$BIN/bwrap"
  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE"

  [ "$status" -ne 0 ]
  [ ! -e "$AI_FIXTURE_LOG" ]
  [ ! -e "$BATS_TEST_TMPDIR/launcher-called" ]
}

@test "verification commands can edit and commit only their task worktree" {
  local original="$BATS_TEST_TMPDIR/original-home"
  printf preserved >"$original/sentinel"
  run env HOME="$original" python3 "$PROJECT_ROOT/scripts/verification_env.py" "$SOURCE" -- \
    bash -c 'printf fixture > tracked; git add tracked; git -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m "feat: fixture"'

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$SOURCE/tracked")" = fixture ]
  [ "$(cat "$original/sentinel")" = preserved ]
  [ ! -e "$original/base/tracked" ]
}

@test "AI verification rejects the primary checkout before invoking Nix" {
  run env PATH="$BIN:$PATH" python3 "$PROBE" "$BATS_TEST_TMPDIR/original-home/base"

  [ "$status" -ne 0 ]
  [ ! -e "$AI_FIXTURE_LOG" ]
  [[ "$output" == *"linked task worktree"* ]]
}

@test "AI candidate verification can require a prebuilt Codex before starting either shell" {
  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE" --no-codex-build \
    -- bash -c 'printf "verified-command\n"'

  [ "$status" -eq 0 ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  python3 - "$AI_FIXTURE_LOG" "$runtime" "$SOURCE" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert [row['argv'][0] for row in rows]==['eval', 'build', 'develop', 'develop']
home=Path(rows[1]['HOME'])
assert home.parent == Path(sys.argv[2])
assert Path(sys.argv[2]).parent == Path('/tmp/codex')
assert not (Path(sys.argv[3])/'tmp').exists()
assert rows[0]['HOME']==rows[1]['HOME']==rows[2]['HOME']
assert (home.parent/'codex-cache.log').read_text().strip()=='fixture Codex output available'
assert 'verified-command' in (home.parent/'startup.log').read_text()
PY
}

@test "AI candidate verification stops before shell hooks when Codex needs a source build" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=codex-unavailable \
    python3 "$PROBE" "$SOURCE" --no-codex-build \
    -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 29 ]
  [[ "$output" == *'Codex'*'ビルド'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ ! -e "$runtime/startup.log" ]
  [ ! -e "$runtime/home/.agents" ]
  [ "$(cat "$runtime/exit-code")" -eq 29 ]
  grep -q 'output unavailable' "$runtime/codex-cache.log"
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 2 ]
}

@test "AI candidate verification records a signal while checking the Codex cache" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=codex-signal \
    python3 "$PROBE" "$SOURCE" --no-codex-build

  [ "$status" -eq 143 ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ ! -e "$runtime/startup.log" ]
  [ "$(cat "$runtime/exit-code")" -eq 143 ]
  grep -q 'fixture Codex cache signal' "$runtime/codex-cache.log"
}

@test "AI candidate verification isolates shell hooks and runs the requested command after output checks" {
  run env PATH="$BIN:$PATH" HOME="$BATS_TEST_TMPDIR/original-home" \
    CODEX_HOME=ambient CLAUDE_CONFIG_DIR=ambient FORCE_COLOR=1 \
    XDG_CACHE_HOME=ambient XDG_STATE_HOME=ambient \
    python3 "$PROBE" "$SOURCE" --shell wsl -- bash -c 'printf "verified-command/%s\n" "$(cat "$HOME/.agents/hook")"'

  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS: 6 CLI'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/original-home/.agents" ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  python3 - "$AI_FIXTURE_LOG" "$runtime" "$SOURCE" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert len(rows)==3
assert len({row['HOME'] for row in rows})==1
home=Path(rows[0]['HOME'])
assert home.parent == Path(sys.argv[2])
assert Path(sys.argv[2]).parent == Path('/tmp/codex')
assert not (Path(sys.argv[3])/'tmp').exists()
assert 'verified-command/isolated' in (home.parent/'startup.log').read_text()
# 隔離 HOME と XDG の root は終了後にだけ削除され、source tree には作られない。
for name in ['home', 'config', 'data', 'runtime', 'cache', 'state']:
    assert not (home.parent/name).exists(), name
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
    case_source="$SOURCE"
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
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  grep -q 'codex のoutput不一致' "$runtime/startup.log"
}

@test "AI candidate verification preserves the requested command failure in its evidence" {
  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE" -- bash -c 'exit 23'

  [ "$status" -eq 23 ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ "$(cat "$runtime/exit-code")" -eq 23 ]
}

@test "AI candidate verification records invalid metadata and suppresses the requested command" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=invalid-json \
    python3 "$PROBE" "$SOURCE" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ "$(cat "$runtime/exit-code")" -eq 1 ]
  grep -q 'invalid-json' "$runtime/metadata.json"
  grep -q 'metadata' "$runtime/evaluation.log"
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 1 ]
}

@test "AI candidate verification rejects incomplete or malformed metadata before shell startup" {
  local mode case_source runtime
  for mode in missing duplicate wrong-type missing-path; do
    case_source="$SOURCE"
    run env PATH="$BIN:$PATH" AI_FIXTURE_MODE="$mode" \
      python3 "$PROBE" "$case_source" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

    [ "$status" -eq 1 ]
    [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
    runtime="$(runtime_from_output "$output")"
    [ -n "$runtime" ]
    [ ! -e "$runtime/startup.log" ]
    [ "$(cat "$runtime/exit-code")" -eq 1 ]
    grep -q 'metadata不正' "$runtime/evaluation.log"
  done
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 4 ]
}

@test "AI candidate verification preserves evaluation failure evidence without starting shells" {
  run env PATH="$BIN:$PATH" AI_FIXTURE_MODE=eval-failure \
    python3 "$PROBE" "$SOURCE" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 17 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ ! -e "$runtime/startup.log" ]
  [ "$(cat "$runtime/exit-code")" -eq 17 ]
  grep -q 'fixture evaluation failed' "$runtime/evaluation.log"
  [ "$(wc -l <"$AI_FIXTURE_LOG")" -eq 1 ]
}

@test "AI candidate verification preserves version failure evidence and suppresses the requested command" {
  printf '#!/usr/bin/env bash\nprintf "fixture version failed\\n" >&2\nexit 19\n' >"$BIN/codex"

  run env PATH="$BIN:$PATH" python3 "$PROBE" "$SOURCE" \
    -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

  [ "$status" -eq 19 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
  local runtime
  runtime="$(runtime_from_output "$output")"
  [ -n "$runtime" ]
  [ "$(cat "$runtime/exit-code")" -eq 19 ]
  grep -q 'fixture version failed' "$runtime/startup.log"
}

@test "AI candidate verification reports signal termination consistently in its exit status and evidence" {
  local mode case_source runtime
  for mode in eval-signal startup-signal; do
    case_source="$SOURCE"
    run env PATH="$BIN:$PATH" AI_FIXTURE_MODE="$mode" \
      python3 "$PROBE" "$case_source" -- bash -c 'touch "$1"' -- "$BATS_TEST_TMPDIR/should-not-run"

    [ "$status" -eq 143 ]
    [ ! -e "$BATS_TEST_TMPDIR/should-not-run" ]
    runtime="$(runtime_from_output "$output")"
    [ -n "$runtime" ]
    [ "$(cat "$runtime/exit-code")" -eq 143 ]
    grep -q 'fixture .* signal' "$runtime"/*.log
  done
}

@test "AI candidate verification removes isolated directories when terminated mid-run" {
  AI_FIXTURE_MODE=startup-hang PATH="$BIN:$PATH" HOME="$BATS_TEST_TMPDIR/original-home" \
    python3 "$PROBE" "$SOURCE" >/dev/null 2>&1 &
  local pid=$!
  local waited=0
  while [ ! -e "$AI_FIXTURE_LOG.ready" ]; do
    sleep 0.1
    waited=$((waited + 1))
    [ "$waited" -lt 100 ]
  done
  kill -TERM "$pid"
  local status=0
  wait "$pid" || status=$?

  [ "$status" -eq 143 ]
  local runtime
  runtime="$(runtime_from_fixture_log)"
  [ -n "$runtime" ]
  local name
  for name in home config data runtime cache state tmp; do
    [ ! -e "$runtime/$name" ]
  done
  [ ! -e "$SOURCE/tmp" ]
}
