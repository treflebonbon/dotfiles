#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="${IMPECCABLE_HOOK_RUNTIME:-$HOME/.agents/skills/impeccable/scripts/hook.mjs}"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT"

  # gradient-text is in the runtime's immediate tier, so the per-edit pass reports
  # it at the edit site.
  IMMEDIATE_CSS='.card { background: linear-gradient(90deg, #a855f7, #ec4899); -webkit-background-clip: text; color: transparent; }'
  # A second, distinct gradient-text occurrence: a finding the per-edit pass has
  # not seen before in this session.
  IMMEDIATE_CSS_ALT='.hero { background: linear-gradient(90deg, #0ea5e9, #22d3ee); -webkit-background-clip: text; color: transparent; }'
  # overused-font sits outside the immediate tier, so the per-edit pass defers it
  # and only the Stop deep pass surfaces it.
  DEFERRED_CSS='.card { font-family: Inter, sans-serif; }'
  # One declaration block carrying both tiers, composed from the two above so a
  # future pin's tier reshuffle is still a one-line edit up here.
  BOTH_TIERS_CSS="${IMMEDIATE_CSS%\}} font-family: Inter, sans-serif; }"
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

run_stop_hook() {
  local session_id="$1"
  local stop_hook_active="${2:-false}"

  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}\n' \
    "$session_id" "$PROJECT" "$stop_hook_active" |
    env IMPECCABLE_HOOK_QUIET=1 node "$RUNTIME"
}

@test "materialized quiet Design Hook reports an immediate-tier finding on the edit" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$IMMEDIATE_CSS" >"$file"

  run run_hook "immediate" "$file"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
  [[ "$output" == *'[gradient-text]'* ]]
}

@test "materialized quiet Design Hook stays silent for clean, non-UI, sensitive, and generated files" {
  require_runtime
  local clean="$PROJECT/Card.css"
  local non_ui="$PROJECT/notes.md"
  local sensitive="$PROJECT/.env.css"
  local generated="$PROJECT/bundle.min.css"
  printf '.card { color: #123456; }\n' >"$clean"
  printf '# notes\n' >"$non_ui"
  # The sensitive and generated fixtures carry an immediate-tier finding on
  # purpose: were their path guards to regress, these two would report instead of
  # staying silent.
  printf '%s\n' "$IMMEDIATE_CSS" >"$sensitive"
  printf '%s\n' "$IMMEDIATE_CSS" >"$generated"

  local file
  for file in "$clean" "$non_ui" "$sensitive" "$generated"; do
    run run_hook "silent-$(basename "$file")" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "materialized quiet Design Hook defers non-immediate findings to the Stop deep pass and surfaces them once" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$DEFERRED_CSS" >"$file"

  # The per-edit pass carries only the immediate tier, so this edit says nothing.
  run run_hook "deferred" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # The deep pass re-scans the session's touched files with the full rule set.
  run run_stop_hook "deferred"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"hookEventName":"Stop"'* ]]
  [[ "$output" == *'[overused-font]'* ]]

  # Once, not on every stop. This holds because the fixture carries findings in
  # only one tier; see the both-tiers test below for where it breaks down.
  run run_stop_hook "deferred"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "materialized quiet Design Hook Stop pass alternates on a file with findings in both tiers (known upstream defect)" {
  require_runtime
  # rememberFindings() REPLACES a file's remembered finding keys, and the Stop
  # pass hands it only the fresh subset. So a Stop that reports the deferred
  # finding evicts the immediate one the per-edit pass had remembered, which then
  # reads as fresh on the next Stop, and so on: the two alternate on every turn
  # end for as long as both remain unfixed. Upstream intends the opposite ("the
  # next Stop fire is silent unless new issues appear" — hook-lib.mjs).
  #
  # This test pins the defect rather than the intent, so the suite tells us when
  # a future pin fixes it instead of quietly passing either way. If it starts
  # failing because both later Stops fall silent, upstream fixed the eviction:
  # replace this test with a plain "surfaces once" assertion.
  local file="$PROJECT/Card.css"
  printf '%s\n' "$BOTH_TIERS_CSS" >"$file"

  run run_hook "both-tiers" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]

  run run_stop_hook "both-tiers"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[overused-font]'* ]]

  run run_stop_hook "both-tiers"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]

  # Fixing the immediate-tier finding leaves one tier, and the pass converges.
  printf '%s\n' "$DEFERRED_CSS" >"$file"
  run run_hook "both-tiers" "$file"
  [ "$status" -eq 0 ]

  run run_stop_hook "both-tiers"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[overused-font]'* ]]

  run run_stop_hook "both-tiers"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "materialized quiet Design Hook Stop pass stays silent for an untouched session and when re-entered" {
  require_runtime

  run run_stop_hook "never-touched"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  local file="$PROJECT/Card.css"
  printf '%s\n' "$DEFERRED_CSS" >"$file"
  run run_hook "reentry" "$file"
  [ "$status" -eq 0 ]

  # stop_hook_active marks a Stop that fired only because a previous one kept the
  # turn alive. Re-scanning there would loop until the harness force-ends the turn.
  run run_stop_hook "reentry" true
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "materialized quiet Design Hook dedupes repeated findings and suppresses a new finding after the edit threshold" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$IMMEDIATE_CSS" >"$file"

  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]

  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  local edit
  for edit in 3 4 5 6; do
    run run_hook "dedupe" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  printf '%s\n' "$IMMEDIATE_CSS_ALT" >"$file"
  run run_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Design Hook remains unwired for Antigravity, Cursor, and GitHub Copilot" {
  [ ! -e "$PROJECT_ROOT/private_dot_config/antigravity/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_config/cursor/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_github/hooks/impeccable.json" ]
}
