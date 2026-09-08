#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="${IMPECCABLE_HOOK_RUNTIME:-$HOME/.agents/skills/impeccable/scripts/impeccable}"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  export CODEX_HOME="$HOME/.codex"
  unset IMPECCABLE_CACHE_ROOT IMPECCABLE_SKILL_DIR IMPECCABLE_SELF IMPECCABLE_HOOK_HARNESS
  PROVIDER=claude
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$CODEX_HOME"
  ln -s "${RUNTIME%/scripts/impeccable}" "$HOME/.agents/skills/impeccable"
  ln -s "${RUNTIME%/scripts/impeccable}" "$HOME/.claude/skills/impeccable"
  cp "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" "$HOME/.claude/settings.json"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" "$CODEX_HOME/hooks.json"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT"
  printf '{}\n' >"$PROJECT/package.json"

  # gradient-text is in the runtime's immediate tier, so the per-edit pass reports
  # it at the edit site.
  IMMEDIATE_CSS='.card { background: linear-gradient(90deg, #a855f7, #ec4899); -webkit-background-clip: text; color: transparent; }'
  # A second, distinct gradient-text occurrence: a finding the per-edit pass has
  # not seen before in this session.
  IMMEDIATE_CSS_ALT='.hero { background: linear-gradient(90deg, #0ea5e9, #22d3ee); -webkit-background-clip: text; color: transparent; }'
  # side-tab sits outside the immediate tier, so the per-edit pass defers it
  # and only the Stop deep pass surfaces it.
  DEFERRED_CSS='.card { border-left: 4px solid #6366f1; border-radius: 8px; }'
  # One declaration block carrying both tiers, composed from the two above so a
  # future pin's tier reshuffle is still a one-line edit up here.
  BOTH_TIERS_CSS="$IMMEDIATE_CSS $DEFERRED_CSS"
}

require_runtime() {
  if [ ! -f "$RUNTIME" ] || [ ! -x "${IMPECCABLE_BIN:-}" ]; then
    # Explicit migration runs must fail when either required artifact is absent.
    [ -z "${IMPECCABLE_HOOK_RUNTIME:-}" ] || return 1
    skip "materialize Impeccable first or set IMPECCABLE_HOOK_RUNTIME"
  fi
}

run_managed_hook() {
  local event="$1"
  local manifest="$HOME/.claude/settings.json"
  [ "$PROVIDER" != codex ] || manifest="$CODEX_HOME/hooks.json"
  local command budget
  command="$(jq -r --arg event "$event" '.hooks[$event][0].hooks[0].command' "$manifest")"
  budget="$(jq -r --arg event "$event" '.hooks[$event][0].hooks[0].timeout' "$manifest")"
  timeout "${budget}s" bash -c "$command"
}

run_post_tool_use_hook() {
  local session_id="$1"
  local file_path="$2"
  local tool_name="${3:-Write}"

  jq -nc --arg session "$session_id" --arg cwd "$PROJECT" --arg tool "$tool_name" \
    --arg file "$file_path" --arg provider "$PROVIDER" \
    '{session_id:$session,cwd:$cwd,hook_event_name:"PostToolUse",tool_name:$tool,tool_input:{file_path:$file}} + (if $provider == "codex" then {turn_id:"turn-1"} else {} end)' |
    run_managed_hook PostToolUse
}

run_stop_hook() {
  local session_id="$1"
  local stop_hook_active="${2:-false}"
  local turn_id="${3:-}"
  if [ "$PROVIDER" = codex ] && [ -z "$turn_id" ]; then turn_id=turn-1; fi
  if [ -n "$turn_id" ]; then PROVIDER=codex; fi

  if [ -n "$turn_id" ]; then
    printf '{"session_id":"%s","turn_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}\n' \
      "$session_id" "$turn_id" "$PROJECT" "$stop_hook_active"
  else
    printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}\n' \
      "$session_id" "$PROJECT" "$stop_hook_active"
  fi |
    run_managed_hook Stop
}

@test "materialized quiet Design Hook reports an immediate-tier finding on the edit" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$IMMEDIATE_CSS" >"$file"

  run run_post_tool_use_hook "immediate" "$file"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
  [[ "$output" == *'[gradient-text]'* ]]
}

@test "materialized quiet Design Hook emits the full self-serve policy once per session" {
  require_runtime
  local first="$PROJECT/Card.css"
  local second="$PROJECT/Hero.css"
  printf '%s\n' "$IMMEDIATE_CSS" >"$first"
  printf '%s\n' "$IMMEDIATE_CSS_ALT" >"$second"

  run run_post_tool_use_hook "policy-footer" "$first"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Triage each finding'* ]]
  [[ "$output" == *'hooks ignore-value'* ]]
  [[ "$output" == *'ignore-value <rule>'* ]]
  [[ "$output" == *'--reason \"<who decided: evidence>\"'* ]]
  [[ "$output" == *'state in your reply what you fixed, what you suppressed, and what you left standing'* ]]
  [[ "$output" == *'\"user confirmed\" in a reason only when the user did'* ]]
  [[ "$output" == *'`ignore-file` and `ignore-rule` need the user'*'explicit approval'* ]]

  run run_post_tool_use_hook "policy-footer" "$second"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Triage per the session policy'* ]]
  [[ "$output" == *'persist confident false-positive or sanctioned-exception ignores'* ]]
  [[ "$output" == *'disclose them in your reply'* ]]
  [[ "$output" != *'Triage each finding'* ]]
}

@test "materialized Design Hook self-serve ignore persists only a reasoned detector value" {
  require_runtime

  run bash -c 'cd "$1" && sh "$2" hooks ignore-value overused-font Inter --reason "agent: documented fixture"' _ "$PROJECT" "$RUNTIME"

  [ "$status" -eq 0 ]
  [[ "$output" == *'detector.ignoreValues'* ]]

  run node -e '
    const fs = require("node:fs");
    const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const values = config.detector?.ignoreValues;
    if (!Array.isArray(values) || values.length !== 1) process.exit(1);
    const [entry] = values;
    if (entry.rule !== "overused-font" || entry.value !== "inter") process.exit(2);
    if (entry.reason !== "agent: documented fixture" || !entry.createdAt) process.exit(3);
    if (config.hook?.ignoreValues || config.detector.ignoreRules?.length || config.detector.ignoreFiles?.length) process.exit(4);
  ' "$PROJECT/.impeccable/config.json"

  [ "$status" -eq 0 ]
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
    run run_post_tool_use_hook "silent-$(basename "$file")" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "materialized quiet Design Hook defers non-immediate findings to the Stop deep pass and surfaces them once" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$DEFERRED_CSS" >"$file"

  # The per-edit pass carries only the immediate tier, so this edit says nothing.
  run run_post_tool_use_hook "deferred" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # The deep pass re-scans the session's touched files with the full rule set.
  run run_stop_hook "deferred"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"hookEventName":"Stop"'* ]]
  [[ "$output" == *'[side-tab]'* ]]

  # Once, not on every stop. This holds because the fixture carries findings in
  # only one tier; see the both-tiers test below for where it breaks down.
  run run_stop_hook "deferred"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "materialized quiet Design Hook emits native Codex Stop output for a turn-scoped deep-pass finding" {
  require_runtime
  PROVIDER=codex
  local file="$PROJECT/Card.css"
  printf '%s\n' "$DEFERRED_CSS" >"$file"

  run run_post_tool_use_hook "codex-deferred" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_stop_hook "codex-deferred" false "turn-1"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'"reason":"'* ]]
  [[ "$output" == *'[side-tab]'* ]]
  [[ "$output" != *'"hookSpecificOutput"'* ]]

  printf '.card { color: #123456; }\n' >"$file"
  run run_post_tool_use_hook "codex-deferred" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_stop_hook "codex-deferred" false "turn-2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "global materialized hooks check new projects without opt-in for both providers" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$BOTH_TIERS_CSS" >"$file"
  for PROVIDER in claude codex; do
    [ ! -e "$PROJECT/.impeccable/config.json" ]
    [ ! -e "$PROJECT/.impeccable/config.local.json" ]
    [ ! -e "$PROJECT/.claude" ]
    [ ! -e "$PROJECT/.codex" ]
    run run_post_tool_use_hook "$PROVIDER-global" "$file"
    [ "$status" -eq 0 ]
    jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | contains("[gradient-text]"))' <<<"$output"
    run run_stop_hook "$PROVIDER-global"
    [ "$status" -eq 0 ]
    [[ "$output" == *'[side-tab]'* ]]
    if [ "$PROVIDER" = codex ]; then
      jq -e '.decision == "block" and (.reason | contains("[side-tab]")) and (has("hookSpecificOutput") | not)' <<<"$output"
    else
      jq -e '.hookSpecificOutput.hookEventName == "Stop"' <<<"$output"
    fi
    run run_stop_hook "$PROVIDER-global"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ ! -e "$PROJECT/.impeccable/config.json" ]
}

@test "materialized Codex apply_patch checks a symlinked monorepo target and converges" {
  require_runtime
  PROVIDER=codex
  mkdir -p "$PROJECT/packages/web/src"
  printf '{}\n' >"$PROJECT/packages/web/package.json"
  printf '%s\n' "$BOTH_TIERS_CSS" >"$PROJECT/packages/web/src/Card.css"
  ln -s packages/web "$PROJECT/web"
  local payload
  payload="$(jq -nc --arg cwd "$PROJECT" '{session_id:"monorepo",turn_id:"turn-1",cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: web/src/Card.css\n@@\n-old\n+new\n*** End Patch"}}')"
  run run_managed_hook PostToolUse <<<"$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]
  run run_post_tool_use_hook monorepo "$PROJECT/web/src/Card.css" Edit
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_stop_hook monorepo
  [ "$status" -eq 0 ]
  [[ "$output" == *'[side-tab]'* ]]
  run run_stop_hook monorepo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "materialized hooks preserve project config and disposable cache ownership" {
  require_runtime
  mkdir -p "$PROJECT/.impeccable"
  printf '{"hook":{"enabled":false}}\n' >"$PROJECT/.impeccable/config.local.json"
  printf '%s\n' "$IMMEDIATE_CSS" >"$PROJECT/Card.css"
  for PROVIDER in claude codex; do
    run run_post_tool_use_hook "$PROVIDER-disabled" "$PROJECT/Card.css"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run run_stop_hook "$PROVIDER-disabled"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  jq -e '.hook.enabled == false' "$PROJECT/.impeccable/config.local.json"
  printf '{}\n' >"$PROJECT/.impeccable/config.local.json"
  run run_post_tool_use_hook cache-owner "$PROJECT/Card.css"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]
  [ -f "$PROJECT/.impeccable/hook.cache.json" ]
  [ ! -e "$HOME/.impeccable/hook.cache.json" ]
  jq -e '. == {}' "$PROJECT/.impeccable/config.local.json"
  [ ! -e "$HOME/.impeccable/config.json" ]
  [ ! -e "$PROJECT/.impeccable/config.json" ]
}

@test "materialized quiet Design Hook Stop pass converges silently on a file with findings in both tiers" {
  require_runtime
  local file="$PROJECT/Card.css"
  printf '%s\n' "$BOTH_TIERS_CSS" >"$file"

  run run_post_tool_use_hook "both-tiers" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]
  [[ "$output" != *'[side-tab]'* ]]

  run run_stop_hook "both-tiers"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[side-tab]'* ]]
  [[ "$output" != *'[gradient-text]'* ]]

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
  run run_post_tool_use_hook "reentry" "$file"
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

  run run_post_tool_use_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[gradient-text]'* ]]

  run run_post_tool_use_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  local edit
  for edit in 3 4 5 6; do
    run run_post_tool_use_hook "dedupe" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  printf '%s\n' "$IMMEDIATE_CSS_ALT" >"$file"
  run run_post_tool_use_hook "dedupe" "$file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Design Hook remains unwired for Antigravity, Cursor, and GitHub Copilot" {
  [ ! -e "$PROJECT_ROOT/private_dot_config/antigravity/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_config/cursor/hooks.json" ]
  [ ! -e "$PROJECT_ROOT/private_dot_github/hooks/impeccable.json" ]
}
