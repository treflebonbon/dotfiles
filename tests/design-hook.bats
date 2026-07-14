#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="${IMPECCABLE_HOOK_RUNTIME:-$HOME/.agents/skills/impeccable/scripts/hook.mjs}"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT"
}

require_runtime() {
  if [ ! -f "$RUNTIME" ]; then
    skip "materialize Impeccable first or set IMPECCABLE_HOOK_RUNTIME"
  fi
}

run_hook() {
  local session_id="$1"
  local file_path="$2"
  local tool_name="${3:-Write}"

  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}\n' \
    "$session_id" "$PROJECT" "$tool_name" "$file_path" |
    env IMPECCABLE_HOOK_QUIET=1 node "$RUNTIME"
}

@test "materialized quiet Design Hook reports a deterministic UI finding and succeeds" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '.card { font-family: Inter, sans-serif; }\n' >"$file"

  run run_hook "finding" "$file"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
  [[ "$output" == *'[overused-font]'* ]]
}

@test "materialized quiet Design Hook stays silent for clean, non-UI, sensitive, and generated files" {
  require_runtime
  local clean="$PROJECT/Card.css"
  local non_ui="$PROJECT/notes.md"
  local sensitive="$PROJECT/.env.css"
  local generated="$PROJECT/bundle.min.css"
  printf '.card { color: #123456; }\n' >"$clean"
  printf '# notes\n' >"$non_ui"
  printf '.secret { font-family: Inter; }\n' >"$sensitive"
  printf '.generated { font-family: Inter; }\n' >"$generated"

  local file
  for file in "$clean" "$non_ui" "$sensitive" "$generated"; do
    run run_hook "silent-$(basename "$file")" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "materialized quiet Design Hook dedupes repeated findings and suppresses a new finding after the edit threshold" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '.card { font-family: Inter, sans-serif; }\n' >"$file"

  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[overused-font]'* ]]

  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  local edit
  for edit in 3 4 5 6; do
    run run_hook "dedupe" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  printf '.card { font-family: Roboto, sans-serif; }\n' >"$file"
  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Design Hook remains unwired for Antigravity, Cursor, and GitHub Copilot" {
  [ ! -e "$PROJECT_ROOT/private_dot_config/antigravity/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_config/cursor/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_github/hooks/impeccable.json" ]
}
