#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/local-skills/orca-peer-refactor/scripts/orca-preflight.py"
  ORCA_DOC="$PROJECT_ROOT/local-skills/orca-peer-refactor/references/orca.md"
  RECEIPT="$BATS_TEST_TMPDIR/receipt.json"
}

write_coordinator_receipt() {
  cat >"$RECEIPT" <<'JSON'
{"ok":true,"result":{"run":{"id":"run-1","coordinator_handle":"term-1"}}}
JSON
}

write_worker_receipt() {
  cat >"$RECEIPT" <<'JSON'
{"ok":true,"result":{"dispatch":{"id":"dispatch-1","taskId":"task-1","assigneeHandle":"term-1","status":"dispatched"}}}
JSON
}

worktree_branch_head() {
  python3 - "$1" <<'PY'
import os, subprocess, sys
env = {key: os.environ[key] for key in os.environ if not key.startswith("GIT_")}
def git(*args):
    result = subprocess.run(["git", "-C", sys.argv[1], *args], env=env, check=True, capture_output=True, text=True)
    return result.stdout.rstrip("\n")
print(git("branch", "--show-current") + "\t" + git("rev-parse", "--verify", "HEAD"))
PY
}

worktree_common_dir() {
  python3 - "$1" <<'PY'
import os, subprocess, sys
env = {key: os.environ[key] for key in os.environ if not key.startswith("GIT_")}
result = subprocess.run(["git", "-C", sys.argv[1], "rev-parse", "--path-format=absolute", "--git-common-dir"], env=env, check=True, capture_output=True, text=True)
print(result.stdout.rstrip("\n"))
PY
}

other_linked_worktree() {
  python3 - "$1" <<'PY'
import os, subprocess, sys
root = os.path.realpath(sys.argv[1])
env = {key: os.environ[key] for key in os.environ if not key.startswith("GIT_")}
listing = subprocess.run(["git", "-C", root, "worktree", "list", "--porcelain"], env=env, check=True, capture_output=True, text=True)
for block in listing.stdout.split("\n\n"):
    path = next((line[9:] for line in block.splitlines() if line.startswith("worktree ")), "")
    if not path or os.path.realpath(path) == root or not os.path.isdir(path):
        continue
    git_dir = subprocess.run(["git", "-C", path, "rev-parse", "--absolute-git-dir"], env=env, check=True, capture_output=True, text=True).stdout.strip()
    common_dir = subprocess.run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"], env=env, check=True, capture_output=True, text=True).stdout.strip()
    if os.path.realpath(git_dir) != os.path.realpath(common_dir):
        print(os.path.realpath(path))
        break
PY
}

worker_readiness_verify() {
  python3 "$SCRIPT" worker-readiness verify "$1" --worktree "$2" --branch "$3" --head "$4" --task "$5" --dispatch "$6" --assignee "$7"
}

@test "coordinator receipt must match the expected Run and handle without changing it" {
  write_coordinator_receipt
  cp "$RECEIPT" "$BATS_TEST_TMPDIR/original.json"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-1
  [ "$status" -eq 0 ]
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-other --handle term-1
  [ "$status" -ne 0 ]
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-other
  [ "$status" -ne 0 ]
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run '' --handle term-1
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/original.json" "$RECEIPT"
  python3 - "$RECEIPT" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["result"]["run"]["id"] = ""
json.dump(doc, open(path, "w", encoding="utf-8"))
PY
  cp "$RECEIPT" "$BATS_TEST_TMPDIR/empty.json"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run '' --handle term-1
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/empty.json" "$RECEIPT"
}

@test "worker readiness must match the assigned checkout, including another worktree of the same repo" {
  local other_root primary_root observation="$BATS_TEST_TMPDIR/worker-readiness.json" primary_observation="$BATS_TEST_TMPDIR/primary-readiness.json" branch head other_branch other_head primary_branch primary_head
  other_root="$(other_linked_worktree "$PROJECT_ROOT")"
  [ -n "$other_root" ] || skip "requires another registered linked worktree"
  IFS=$'\t' read -r branch head <<<"$(worktree_branch_head "$PROJECT_ROOT")"
  IFS=$'\t' read -r other_branch other_head <<<"$(worktree_branch_head "$other_root")"

  cd "$PROJECT_ROOT"
  run python3 "$SCRIPT" worker-readiness record "$observation" --task task-1 --dispatch dispatch-1 --assignee term-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"observation saved"* ]]
  cp "$observation" "$BATS_TEST_TMPDIR/worker-readiness.original.json"

  run worker_readiness_verify "$observation" "$PROJECT_ROOT" "$branch" "$head" task-1 dispatch-1 term-1
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/worker-readiness.original.json" "$observation"

  run worker_readiness_verify "$observation" "$other_root" "$other_branch" "$other_head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/worker-readiness.original.json" "$observation"

  primary_root="$(dirname "$(worktree_common_dir "$PROJECT_ROOT")")"
  [ "$primary_root" != "$PROJECT_ROOT" ] || skip "requires a linked task worktree and its primary checkout"
  IFS=$'\t' read -r primary_branch primary_head <<<"$(worktree_branch_head "$primary_root")"
  (cd "$primary_root" && python3 "$SCRIPT" worker-readiness record "$primary_observation" --task task-1 --dispatch dispatch-1 --assignee term-1)
  run worker_readiness_verify "$primary_observation" "$primary_root" "$primary_branch" "$primary_head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]
}

@test "worker readiness rejects every changed checkout and native assignment field" {
  local observation="$BATS_TEST_TMPDIR/worker-readiness.json" variant="$BATS_TEST_TMPDIR/variant.json" field branch head wrong_head
  cd "$PROJECT_ROOT"
  run python3 "$SCRIPT" worker-readiness record "$observation" --task task-1 --dispatch dispatch-1 --assignee term-1
  [ "$status" -eq 0 ]
  cp "$observation" "$BATS_TEST_TMPDIR/worker-readiness.original.json"
  IFS=$'\t' read -r branch head <<<"$(worktree_branch_head "$PROJECT_ROOT")"
  wrong_head="f${head:1}"

  run worker_readiness_verify "$observation" "$PROJECT_ROOT" "${branch}-different" "$head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]
  run worker_readiness_verify "$observation" "$PROJECT_ROOT" "$branch" "$wrong_head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]

  for field in cwd physical_root branch head git_dir common_dir task_id dispatch_id assignee_handle; do
    python3 - "$observation" "$variant" "$field" <<'PY'
import json, sys
source, target, field = sys.argv[1:]
doc = json.load(open(source, encoding="utf-8"))
doc[field] = "f" * 40 if field == "head" else doc[field] + "-different"
json.dump(doc, open(target, "w", encoding="utf-8"))
PY
    cp "$variant" "$BATS_TEST_TMPDIR/variant.original.json"
    run worker_readiness_verify "$variant" "$PROJECT_ROOT" "$branch" "$head" task-1 dispatch-1 term-1
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/variant.original.json" "$variant"
  done
  cmp "$BATS_TEST_TMPDIR/worker-readiness.original.json" "$observation"
}

@test "worker readiness rejects malformed, missing, empty, and non-string observation values" {
  local observation="$BATS_TEST_TMPDIR/worker-readiness.json" invalid="$BATS_TEST_TMPDIR/invalid.json" branch head
  cd "$PROJECT_ROOT"
  run python3 "$SCRIPT" worker-readiness record "$observation" --task task-1 --dispatch dispatch-1 --assignee term-1
  [ "$status" -eq 0 ]
  IFS=$'\t' read -r branch head <<<"$(worktree_branch_head "$PROJECT_ROOT")"
  printf '{not-json\n' >"$invalid"
  cp "$invalid" "$BATS_TEST_TMPDIR/invalid.original.json"
  run worker_readiness_verify "$invalid" "$PROJECT_ROOT" "$branch" "$head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/invalid.original.json" "$invalid"

  for field in missing empty non-string duplicate; do
    python3 - "$observation" "$invalid" "$field" <<'PY'
import json, sys
source, target, mutation = sys.argv[1:]
doc = json.load(open(source, encoding="utf-8"))
if mutation == "missing":
    del doc["head"]
elif mutation == "empty":
    doc["head"] = ""
elif mutation == "non-string":
    doc["branch"] = 42
else:
    with open(target, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(doc)[:-1] + ', "branch": "duplicate"}\n')
        raise SystemExit(0)
with open(target, "w", encoding="utf-8") as stream:
    json.dump(doc, stream)
PY
    cp "$invalid" "$BATS_TEST_TMPDIR/invalid.original.json"
    run worker_readiness_verify "$invalid" "$PROJECT_ROOT" "$branch" "$head" task-1 dispatch-1 term-1
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/invalid.original.json" "$invalid"
  done
  run python3 "$SCRIPT" worker-readiness record "$BATS_TEST_TMPDIR/empty.json" --task task-1 --dispatch dispatch-1 --assignee ''
  [ "$status" -ne 0 ]
}

@test "worker readiness ignores ambient Git overrides and never executes shell-looking JSON" {
  local observation="$BATS_TEST_TMPDIR/worker-readiness.json" marker="$BATS_TEST_TMPDIR/should-not-exist" variant="$BATS_TEST_TMPDIR/variant.json" branch head
  IFS=$'\t' read -r branch head <<<"$(worktree_branch_head "$PROJECT_ROOT")"
  cd "$PROJECT_ROOT"
  run env GIT_DIR="$BATS_TEST_TMPDIR/not-a-git-dir" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$BATS_TEST_TMPDIR/not-a-worktree" python3 "$SCRIPT" worker-readiness record "$observation" --task task-1 --dispatch dispatch-1 --assignee term-1
  [ "$status" -eq 0 ]
  [[ "$output" != *"not-a-worktree"* ]]
  ! grep -Fq "not-a-worktree" "$observation"
  run env GIT_DIR="$BATS_TEST_TMPDIR/not-a-git-dir" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$BATS_TEST_TMPDIR/not-a-worktree" python3 "$SCRIPT" worker-readiness verify "$observation" --worktree "$PROJECT_ROOT" --branch "$branch" --head "$head" --task task-1 --dispatch dispatch-1 --assignee term-1
  [ "$status" -eq 0 ]
  [[ "$output" != *"not-a-worktree"* ]]

  python3 - "$observation" "$variant" "$marker" <<'PY'
import json, sys
source, target, marker = sys.argv[1:]
doc = json.load(open(source, encoding="utf-8"))
doc["branch"] = f"$(touch {marker})"
with open(target, "w", encoding="utf-8") as stream:
    json.dump(doc, stream)
PY
  cp "$variant" "$BATS_TEST_TMPDIR/variant.original.json"
  run worker_readiness_verify "$variant" "$PROJECT_ROOT" "$branch" "$head" task-1 dispatch-1 term-1
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
  cmp "$BATS_TEST_TMPDIR/variant.original.json" "$variant"
}

@test "coordinator rejects errors, malformed envelopes, and missing Run identity" {
  printf '{"ok":false,"error":{"code":"failed"}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-1
  [ "$status" -ne 0 ]
  printf '{not-json\n' >"$RECEIPT"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-1
  [ "$status" -ne 0 ]
  printf '{"ok":true,"result":{}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-1
  [ "$status" -ne 0 ]
  printf '{"ok":true,"error":{"code":"failed"},"result":{"run":{"id":"run-1","coordinator_handle":"term-1"}}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" coordinator "$RECEIPT" --run run-1 --handle term-1
  [ "$status" -ne 0 ]
}

@test "worker-show receipt must match the dispatched Task, Dispatch, and assignee" {
  write_worker_receipt
  cp "$RECEIPT" "$BATS_TEST_TMPDIR/original.json"
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-1
  [ "$status" -eq 0 ]
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-other --task task-1 --assignee term-1
  [ "$status" -ne 0 ]
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-other --assignee term-1
  [ "$status" -ne 0 ]
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-other
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/original.json" "$RECEIPT"
}

@test "worker-show rejects settled or errored Dispatches" {
  write_worker_receipt
  python3 - "$RECEIPT" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["result"]["dispatch"]["status"] = "completed"
json.dump(doc, open(path, "w", encoding="utf-8"))
PY
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-1
  [ "$status" -ne 0 ]
  printf '{"ok":false,"error":{"code":"failed"},"result":{"dispatch":{"id":"dispatch-1","taskId":"task-1","assigneeHandle":"term-1","status":"dispatched"}}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-1
  [ "$status" -ne 0 ]
}

@test "worker-show rejects missing and malformed dispatch identities" {
  printf '{"ok":true,"result":{}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-1
  [ "$status" -ne 0 ]
  printf '{"ok":true,"result":{"dispatch":{"id":"dispatch-1","taskId":"task-1","status":"dispatched"}}}\n' >"$RECEIPT"
  run python3 "$SCRIPT" worker-show "$RECEIPT" --dispatch dispatch-1 --task task-1 --assignee term-1
  [ "$status" -ne 0 ]
}

@test "the documented Python send example preserves shell-looking body text in one argv" {
  local example="$BATS_TEST_TMPDIR/example.py" fake_cli="$BATS_TEST_TMPDIR/orca-ide"
  awk '
    $0 == "<!-- literal-safe-example:start -->" { example = 1; next }
    example && $0 == "```python" { code = 1; next }
    code && $0 == "```" { exit }
    code { print }
  ' "$ORCA_DOC" >"$example"
  [ -s "$example" ]
  cat >"$fake_cli" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["ARGV_CAPTURE"], "w", encoding="utf-8") as stream:
    json.dump(sys.argv[1:], stream)
PY
  chmod +x "$fake_cli"
  ARGV_CAPTURE="$BATS_TEST_TMPDIR/argv.json" PATH="$BATS_TEST_TMPDIR:$PATH" python3 "$example"
  python3 - "$BATS_TEST_TMPDIR/argv.json" <<'PY'
import json, sys
argv = json.load(open(sys.argv[1], encoding="utf-8"))
expected_body = "\n".join((
    "レビューの要点:",
    'literal $HOME、$(printf test)、`バッククォート`、"二重引用符"、\'一重引用符\' を含む。',
))
assert argv == [
    "orchestration", "send", "--to", "run:<run-id>", "--run", "<run-id>",
    "--from", "<sender-handle>", "--subject", "レビュー依頼", "--body", expected_body,
    "--type", "status", "--json",
], argv
PY
}

@test "Orca guidance separates worker, coordinator, nested inbox, and report evidence" {
  section() {
    awk -v heading="$1" '
      BEGIN { match(heading, /^#+/); level = RLENGTH }
      $0 == heading { found = 1; in_section = 1; next }
      in_section && /^#+[[:space:]]/ {
        match($0, /^#+/)
        if (RLENGTH <= level) exit
      }
      in_section { print }
      END { if (!found) exit 1 }
    ' "$ORCA_DOC"
  }

  ordinary_worker="$(section '### 普通の dispatched worker')"
  nested_coordinator="$(section '### nested coordinator')"
  inbox_settlement="$(section '## inbox / settlement')"
  verification_record="$(section '## 検証記録')"
  worktree_readiness="$(section '## Worktree readiness')"

  [[ "$ordinary_worker" == *'通常の dispatched worker は `--run` を付けず'* ]]
  [[ "$nested_coordinator" == *'上位 coordinator から自分の Dispatch 宛てに届く follow-up'* ]]
  [[ "$inbox_settlement" == *'`consumer_fenced` を受けたら停止し'* ]]
  [[ "$verification_record" == *'全採点と native receipt が確定し、一つにまとまった evidence packet'* ]]
  [[ "$verification_record" == *'usage が取得できない場合は `null`'* ]]
  [[ "$worktree_readiness" == *'Orca で Task / Dispatch を監督する全 task'* ]]
  [[ "$worktree_readiness" == *'成功した場合だけ親が着手を伝える'* ]]
  [[ "$worktree_readiness" == *'--branch <assigned-branch> --head <assigned-start-head>'* ]]
}
