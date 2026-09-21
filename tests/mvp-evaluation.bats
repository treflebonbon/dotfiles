#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$ROOT/scripts/mvp-evaluation.py"
  RUN="$BATS_TEST_TMPDIR/run"
  printf '{"instructions":"Synthetic test instructions", "effective_context":"fixture; no inherited context", "runtime_notes":"synthetic worker, no model"}\n' > "$BATS_TEST_TMPDIR/conditions.json"
}

approve() {
  python3 - "$RUN" "$BATS_TEST_TMPDIR/approval.json" <<'PY'
import json,sys
from pathlib import Path
s=json.loads((Path(sys.argv[1])/'state.json').read_text())
Path(sys.argv[2]).write_text(json.dumps({'bundle_sha256':s['attempts'][-1]['bundle_sha256'],'reason':'checked assigned input'}))
PY
  python3 "$CLI" approve "$RUN" --record "$BATS_TEST_TMPDIR/approval.json"
}

audit() {
  python3 - "$RUN" "$BATS_TEST_TMPDIR/audit.json" "$1" "${2:-}" <<'PY'
import json,sys
from pathlib import Path
r=Path(sys.argv[1]);s=json.loads((r/'state.json').read_text());a=s['attempts'][-1]
Path(sys.argv[2]).write_text(json.dumps({'evidence_sha256':a['evidence_sha256'],'input':sys.argv[3],
'scores':[1]*6,'compliance':['pass']*4,'issues':[], 'reason':'fixture evidence inspected',
'failure_patterns':[sys.argv[4]] if sys.argv[4] else [],
'references':[{'path':'stdout.jsonl','locator':'fixture boundary event'}]}))
PY
  python3 "$CLI" audit "$RUN" --record "$BATS_TEST_TMPDIR/audit.json"
}

execute_next() {
  python3 "$CLI" prepare "$RUN" "$@"
  approve
  python3 "$CLI" dispatch "$RUN"
}

@test "MVP explicit replacements preserve evidence and repeated input failure stops dispatch" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  audit invalid contamination
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  execute_next --replace
  audit invalid contamination
  run python3 "$CLI" prepare "$RUN" --replace
  [ "$status" -ne 0 ]
  [[ "$output" == *"repeated failure"* ]]
  [ -f "$RUN/attempts/01/evidence.json" ]
  [ -f "$RUN/attempts/02/evidence.json" ]
  [ ! -d "$RUN/attempts/03" ]
}

@test "MVP fixture writes only named artifacts and blocks the next task until evidence is audited" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  python3 "$CLI" prepare "$RUN"
  approve
  run python3 "$CLI" dispatch "$RUN"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&3; return 1; }
  [ -s "$RUN/attempts/01/artifacts/memo.md" ]
  [ -s "$RUN/attempts/01/evidence.json" ]
  grep -q 'FIXTURE_BOUNDARY_OK' "$RUN/attempts/01/stdout.jsonl"
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent audit required"* ]]
  run python3 "$CLI" dispatch "$RUN"
  [ "$status" -ne 0 ]
}

@test "MVP evaluation freezes only the assigned task and requires approval before dispatch" {
  run python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&3; return 1; }
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -eq 0 ]
  [ -f "$RUN/attempts/01/inputs/SKILL.md" ]
  [ -f "$RUN/attempts/01/prompt.txt" ]
  ! grep -q 'display-only negative control' "$RUN/attempts/01/prompt.txt"
  ! grep -q 'held-out search UI' "$RUN/attempts/01/prompt.txt"
  run python3 "$CLI" dispatch "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"approval required"* ]]
  [ ! -f "$RUN/attempts/01/evidence.json" ]
}

@test "MVP allows at most two replacements" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  audit invalid first
  execute_next --replace
  audit unknown second
  execute_next --replace
  audit invalid third
  run python3 "$CLI" prepare "$RUN" --replace
  [ "$status" -ne 0 ]
  [[ "$output" == *"replacement limit"* ]]
}

@test "MVP functional failure is not replaceable and three nonclear groups stop without L" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  # Parent grading changes only its audit record, never the worker artifact.
  audit valid
  # Use a fresh run to submit a failing functional grade before it is immutable.
  RUN="$BATS_TEST_TMPDIR/failing-run"
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  python3 - "$RUN" "$BATS_TEST_TMPDIR/failing.json" <<'PY'
import json,sys
from pathlib import Path
s=json.loads((Path(sys.argv[1])/'state.json').read_text())
Path(sys.argv[2]).write_text(json.dumps({'evidence_sha256':s['attempts'][-1]['evidence_sha256'],
'input':'valid','scores':[1,1,1,1,1,.5],'compliance':['pass']*4,'issues':[],
'failure_patterns':['verification overclaim'],'reason':'fixture functional failure',
'references':[{'path':'stdout.jsonl','locator':'fixture'}]}))
PY
  python3 "$CLI" audit "$RUN" --record "$BATS_TEST_TMPDIR/failing.json"
  run python3 "$CLI" prepare "$RUN" --replace
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be replaced"* ]]
  for index in {2..9}; do
    execute_next
    audit valid
  done
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"three groups complete"* ]]
}

@test "MVP twelve-dispatch path retains originals and cannot start a thirteenth" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  audit invalid first
  execute_next --replace
  audit unknown second
  execute_next --replace
  audit valid
  for index in {2..9}; do
    execute_next
    audit valid
  done
  printf '{"unused":true,"reason":"synthetic history"}\n' > "$BATS_TEST_TMPDIR/unused.json"
  execute_next --unused-evidence "$BATS_TEST_TMPDIR/unused.json"
  audit valid
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  [ -f "$RUN/attempts/12/evidence.json" ]
  [ ! -d "$RUN/attempts/13" ]
}

@test "MVP changed input and concurrent controllers fail closed before starting a worker" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  python3 "$CLI" prepare "$RUN"
  approve
  run flock "$RUN/lock" python3 "$CLI" dispatch "$RUN"
  [ "$status" -ne 0 ]
  printf '\nchanged\n' >> "$RUN/attempts/01/inputs/SKILL.md"
  run python3 "$CLI" dispatch "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"input changed"* ]]
  [ ! -f "$RUN/attempts/01/evidence.json" ]
}

@test "MVP input and execution evidence mutations cannot receive approval or audit" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  execute_next
  printf '\nchanged\n' >> "$RUN/attempts/01/stdout.jsonl"
  run audit valid
  [ "$status" -ne 0 ]
  [[ "$output" == *"execution log changed"* ]]
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
}

@test "MVP admits L only after three clear groups and stops after L" {
  python3 "$CLI" init "$RUN" --conditions "$BATS_TEST_TMPDIR/conditions.json" --fixture
  for index in {1..9}; do
    execute_next
    audit valid
  done
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unused-history evidence required"* ]]
  printf '{"unused":true,"reason":"synthetic history checked"}\n' > "$BATS_TEST_TMPDIR/unused.json"
  execute_next --unused-evidence "$BATS_TEST_TMPDIR/unused.json"
  audit valid
  run python3 "$CLI" prepare "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"qualitative plateau; quantitative convergence unverified"* ]]
  [ ! -d "$RUN/attempts/11" ]
  [ ! -f "$RUN/attempts/02/artifacts/model.mjs" ]
}
