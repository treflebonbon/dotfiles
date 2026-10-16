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

  [[ "$ordinary_worker" == *'通常の dispatched worker は `--run` を付けず'* ]]
  [[ "$nested_coordinator" == *'上位 coordinator から自分の Dispatch 宛てに届く follow-up'* ]]
  [[ "$inbox_settlement" == *'`consumer_fenced` を受けたら停止し'* ]]
  [[ "$verification_record" == *'全採点と native receipt が確定し、一つにまとまった evidence packet'* ]]
  [[ "$verification_record" == *'usage が取得できない場合は `null`'* ]]
}
