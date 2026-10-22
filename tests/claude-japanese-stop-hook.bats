#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PROJECT_ROOT/private_dot_local/bin/executable_claude-japanese-stop-hook"
}

stop_event() {
  jq -nc --arg message "$1" --argjson active "${2:-false}" \
    '{hook_event_name:"Stop",stop_hook_active:$active,last_assistant_message:$message}'
}

@test "settings wire the Japanese Stop hook after the Design Hook" {
  run jq -r '.hooks.Stop[1].hooks[0].command' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ "$output" = '"$HOME/.local/bin/claude-japanese-stop-hook"' ]
}

@test "English-only reply is blocked once with a Japanese rewrite request" {
  run "$HOOK" <<<"$(stop_event 'Done. All tests passed.')"
  [ "$status" -eq 0 ]
  jq -e '.decision == "block" and (.reason | test("日本語"))' <<<"$output"
}

@test "Japanese, code-only, re-entered and invalid input pass silently" {
  local event
  for event in \
    "$(stop_event 'テストは成功しました。`lefthook run test` を実行済みです。')" \
    "$(stop_event $'```bash\nbats tests/dogfood.bats\n```')" \
    "$(stop_event 'Done.' true)" \
    'not json'; do
    run "$HOOK" <<<"$event"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}
