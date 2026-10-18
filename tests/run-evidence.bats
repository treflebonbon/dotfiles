#!/usr/bin/env bats

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$project_root/local-skills/herdr-peer-refactor/scripts/run-evidence.py"
  PIN="$project_root/local-skills/herdr-peer-refactor/scripts/candidate-record.py"
  EVIDENCE="$(mktemp -d /tmp/codex/peer-evidence-test.XXXXXX)"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" "$EVIDENCE/peer"
  git init -q "$REPO"
  git -C "$REPO" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial --allow-empty
  SHA="$(git -C "$REPO" rev-parse HEAD)"
  COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"
  RECORD="$EVIDENCE/record.json"
  CANDIDATES="$EVIDENCE/candidates.json"
  REPORT="$EVIDENCE/report.md"
  printf '# Gateway preparation\n' >"$REPORT"
  printf '%s\n' '[{"id":"C2","title":"Gateway preparation","acceptance":["ready"],"non_goals":[],"owned_files":["gateway.py"]}]' >"$CANDIDATES"
  FINGERPRINT="$(cd "$REPO" && python3 "$PIN" pin "$REPORT" "$COMMON" "$SHA" "$CANDIDATES" "$RECORD")"
  printf 'run-1\n' >"$EVIDENCE/peer/run-id"
  printf '271\n' >"$EVIDENCE/peer/waited-s"
  printf '2\n' >"$EVIDENCE/peer/round"
  printf 'missing\n' >"$EVIDENCE/peer/REQ-1.failures"
  printf 'mutation detected\n' >"$EVIDENCE/mutation.log"
}

teardown() {
  [[ "$EVIDENCE" == /tmp/codex/peer-evidence-test.* ]] && rm -r -- "$EVIDENCE"
}

checkpoint() {
  (cd "$REPO" && python3 "$SCRIPT" checkpoint "$RECORD" "$CANDIDATES" "$FINGERPRINT" "$@")
}

save_checkpoint() {
  run checkpoint "$EVIDENCE/peer/run-id" "$EVIDENCE/peer/waited-s" "$EVIDENCE/peer/round" "$EVIDENCE/peer/REQ-1.failures" "$EVIDENCE/mutation.log"
  [ "$status" -eq 0 ]
  CHECKPOINT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["checkpoint"])' "$output")"
  ARCHIVE="$COMMON/peer-refactor-evidence/$FINGERPRINT/$CHECKPOINT.json"
  [ -f "$ARCHIVE" ]
}

restore() {
  (cd "$REPO" && python3 "$SCRIPT" restore "$FINGERPRINT" "$CHECKPOINT")
}

@test "checkpoint restores candidate bytes and all peer budgets after shared evidence disappears" {
  save_checkpoint
  local original
  original="$(sha256sum "$RECORD")"
  rm -- "$RECORD" "$CANDIDATES" "$REPORT" "$EVIDENCE/mutation.log" "$EVIDENCE/peer/"*
  git -C "$REPO" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm descendant --allow-empty
  git -C "$REPO" worktree add -qb task "$BATS_TEST_TMPDIR/linked"
  run bash -c 'cd "$1" && python3 "$2" restore "$3" "$4"' _ "$BATS_TEST_TMPDIR/linked" "$SCRIPT" "$FINGERPRINT" "$CHECKPOINT"
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$RECORD")" = "$original" ]
  [ "$(cat "$EVIDENCE/peer/waited-s")" = 271 ]
  [ "$(cat "$EVIDENCE/peer/round")" = 2 ]
  [ "$(cat "$EVIDENCE/peer/run-id")" = run-1 ]
  [ "$(cat "$EVIDENCE/peer/REQ-1.failures")" = missing ]
  [ "$(cat "$EVIDENCE/mutation.log")" = 'mutation detected' ]
  run restore
  [ "$status" -eq 0 ]
  run checkpoint "$EVIDENCE/peer/run-id" "$EVIDENCE/peer/waited-s" "$EVIDENCE/peer/round" "$EVIDENCE/peer/REQ-1.failures" "$EVIDENCE/mutation.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CHECKPOINT"* ]]
}

@test "restore rejects altered checkpoint bytes before writing any evidence" {
  save_checkpoint
  printf ' ' >>"$ARCHIVE"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'hash が一致しません'* ]]
  [ ! -e "$REPORT" ]
}

@test "restore refuses newer local ledger values without partially restoring missing files" {
  save_checkpoint
  printf '400\n' >"$EVIDENCE/peer/waited-s"
  printf '3\n' >"$EVIDENCE/peer/round"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'上書きしません'* ]]
  [ "$(cat "$EVIDENCE/peer/waited-s")" = 400 ]
  [ "$(cat "$EVIDENCE/peer/round")" = 3 ]
  [ ! -e "$REPORT" ]
}

@test "checkpoint validates the original fingerprint and artifact before archiving" {
  local good="$FINGERPRINT"
  FINGERPRINT="$(printf '%064d' 0)"
  run checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint が一致しません'* ]]
  FINGERPRINT="$good"
  printf 'changed\n' >>"$REPORT"
  run checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *'変更または移動'* ]]
  [ ! -e "$COMMON/peer-refactor-evidence" ]
}

@test "checkpoint refuses sensitive names symlinks directories and paths outside shared evidence" {
  local path
  for path in .env private.key credentials.json auth.json secret.json secrets.json service-account-test.json; do
    printf 'synthetic\n' >"$EVIDENCE/$path"
    run checkpoint "$EVIDENCE/$path"
    [ "$status" -ne 0 ]
    [[ "$output" == *'機密ファイル名'* ]]
  done
  ln -s "$REPORT" "$EVIDENCE/link.md"
  run checkpoint "$EVIDENCE/link.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *'symlink'* ]]
  run checkpoint "$EVIDENCE/peer"
  [ "$status" -ne 0 ]
  run checkpoint "$BATS_TEST_TMPDIR/outside.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *'/tmp/codex'* ]]
  [ ! -e "$COMMON/peer-refactor-evidence" ]
}

@test "restore refuses symlink destinations and leaves their target unchanged" {
  save_checkpoint
  local target="$BATS_TEST_TMPDIR/target"
  printf 'unchanged\n' >"$target"
  rm -- "$REPORT"
  ln -s "$target" "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'symlink'* ]]
  [ "$(cat "$target")" = unchanged ]
}

@test "restore checks all parent paths before writing any missing evidence" {
  save_checkpoint
  rm -- "$EVIDENCE/peer/"*
  rmdir "$EVIDENCE/peer"
  printf 'unchanged\n' >"$EVIDENCE/peer"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'親パス'* ]]
  [ "$(cat "$EVIDENCE/peer")" = unchanged ]
  [ ! -e "$REPORT" ]
}

@test "restore rejects the same checkpoint copied into another repository" {
  save_checkpoint
  local other="$BATS_TEST_TMPDIR/other"
  git clone -q "$REPO" "$other"
  mkdir -p "$other/.git/peer-refactor-evidence/$FINGERPRINT"
  cp "$ARCHIVE" "$other/.git/peer-refactor-evidence/$FINGERPRINT/"
  rm -- "$REPORT"
  run bash -c 'cd "$1" && python3 "$2" restore "$3" "$4"' _ "$other" "$SCRIPT" "$FINGERPRINT" "$CHECKPOINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'別の Git リポジトリ'* ]]
  [ ! -e "$REPORT" ]
}

@test "restore validates candidate provenance even for an internally consistent checkpoint" {
  save_checkpoint
  CHECKPOINT="$(
    python3 - "$ARCHIVE" <<'PY'
import base64, hashlib, json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_bytes())
record_path = data['record_path']
record = json.loads(base64.b64decode(data['files'][record_path]))
record['candidates'][0]['acceptance'] = ['changed intent']
data['files'][record_path] = base64.b64encode(json.dumps(record).encode()).decode()
raw = json.dumps(data).encode()
digest = hashlib.sha256(raw).hexdigest()
p.with_name(digest + '.json').write_bytes(raw)
print(digest)
PY
  )"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint が一致しません'* ]]
  [ ! -e "$REPORT" ]
}
