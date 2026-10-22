#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HERDR_ASK="$PROJECT_ROOT/private_dot_local/bin/executable_herdr-ask"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # Fake herdr: records each call's argv as one JSON line and exits per subcommand.
  cat >"$BATS_TEST_TMPDIR/bin/herdr" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["HERDR_CALLS"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps(sys.argv[1:], ensure_ascii=False) + "\n")
if sys.argv[2] == "read":
    print("recent output")
sys.exit(int(os.environ.get(f"HERDR_{sys.argv[2].upper()}_EXIT", "0")))
PY
  chmod +x "$BATS_TEST_TMPDIR/bin/herdr"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" HERDR_CALLS="$BATS_TEST_TMPDIR/calls.jsonl"
}

@test "herdr-ask sends the body literally, then reads recent output with defaults" {
  local body_file="$BATS_TEST_TMPDIR/body.md" marker="$BATS_TEST_TMPDIR/marker"
  python3 - "$body_file" "$marker" <<'PY'
from pathlib import Path
import sys
body_file, marker = sys.argv[1:]
Path(body_file).write_bytes(f'相談🙂\r\n$HOME $(touch "{marker}") `touch "{marker}"` "二重" \'一重\'\n'.encode("utf-8"))
PY
  run "$HERDR_ASK" peer --body-file "$body_file"
  [ "$status" -eq 0 ]
  [ "$output" = "recent output" ]
  [ ! -e "$marker" ]
  python3 - "$HERDR_CALLS" "$body_file" <<'PY'
import json, sys
calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
body = open(sys.argv[2], "rb").read().decode("utf-8")
assert calls == [
    ["agent", "prompt", "peer", body, "--wait", "--timeout", "600000"],
    ["agent", "read", "peer", "--source", "recent-unwrapped", "--lines", "120"],
], calls
PY
}

@test "herdr-ask passes explicit timeout and lines" {
  printf '本文\n' >"$BATS_TEST_TMPDIR/body.md"
  run "$HERDR_ASK" w1:p2 --body-file "$BATS_TEST_TMPDIR/body.md" --timeout 1000 --lines 5
  [ "$status" -eq 0 ]
  grep -Fq '"--timeout", "1000"' "$HERDR_CALLS"
  grep -Fq '"--lines", "5"' "$HERDR_CALLS"
}

@test "herdr-ask still reads after a failed prompt and returns the prompt exit code" {
  printf '本文\n' >"$BATS_TEST_TMPDIR/body.md"
  HERDR_PROMPT_EXIT=1 run "$HERDR_ASK" peer --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"recent output"* ]]
  [ "$(wc -l <"$HERDR_CALLS")" -eq 2 ]
}

@test "herdr-ask reports a failed read" {
  printf '本文\n' >"$BATS_TEST_TMPDIR/body.md"
  HERDR_READ_EXIT=3 run "$HERDR_ASK" peer --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 3 ]
  [[ "$output" == *"agent read が終了コード 3 で失敗しました"* ]]
}

@test "herdr-ask rejects empty, whitespace, NUL, oversized, unreadable, and invalid UTF-8 bodies before calling herdr" {
  local dir="$BATS_TEST_TMPDIR"
  : >"$dir/empty.md"
  printf ' \n\t\n' >"$dir/space.md"
  printf 'a\0b' >"$dir/nul.md"
  printf '\377' >"$dir/invalid.md"
  head -c 8193 /dev/zero | tr '\0' 'a' >"$dir/large.md"
  for file in empty space nul invalid large missing; do
    run "$HERDR_ASK" peer --body-file "$dir/$file.md"
    [ "$status" -eq 2 ]
    [ ! -e "$HERDR_CALLS" ]
  done
}
