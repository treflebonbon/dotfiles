#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PROJECT_ROOT/private_dot_local/bin/executable_claude-japanese-stop-hook"
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
  local home="$BATS_TEST_TMPDIR/home"
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  mkdir -p "$home"
  printf '{}\n' >"$config"
  env HOME="$home" chezmoi --source "$PROJECT_ROOT" --destination "$home" --config "$config" \
    execute-template <"$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" >"$SETTINGS"
}

stop_event() {
  jq -nc --arg message "$1" --argjson active "${2:-false}" \
    '{hook_event_name:"Stop",stop_hook_active:$active,last_assistant_message:$message}'
}

@test "settings wire the Japanese Stop hook after the Design Hook" {
  run jq -r '.hooks.Stop[1].hooks[0].command' "$SETTINGS"
  [ "$output" = '"$HOME/.local/bin/claude-japanese-stop-hook"' ]
}

@test "English-only reply is blocked once with a Japanese rewrite request" {
  run "$HOOK" <<<"$(stop_event 'Done. All tests passed.')"
  [ "$status" -eq 0 ]
  jq -e '.decision == "block" and (.reason | test("日本語"))' <<<"$output"
}

@test "English reply with a few Japanese labels is blocked" {
  run "$HOOK" <<<"$(stop_event 'Updated the menu labels to 「設定」 and 「保存」. All tests passed.')"
  [ "$status" -eq 0 ]
  jq -e '.decision == "block"' <<<"$output"
}

@test "Japanese reply with many identifiers and commands passes silently" {
  local message='BATS_RUN_SKIPPED、lefthook.yml、scripts/pre-push.sh、private_dot_claude/settings.json.tmpl、tests/claude-japanese-stop-hook.bats を確認済みです。
`bunx --no-install tsc --noEmit` と `git status --short --branch` も実行済みです。
~~~bash
lefthook run test
bats --filter "English reply with a few Japanese labels" tests/claude-japanese-stop-hook.bats
~~~'
  run "$HOOK" <<<"$(stop_event "$message")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Japanese reply with an indented code fence passes silently" {
  local message='- 確認済みです。
  ~~~bash
  lefthook run test
  bats --filter "English reply with a few Japanese labels" tests/claude-japanese-stop-hook.bats
  ~~~~'
  run "$HOOK" <<<"$(stop_event "$message")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Japanese reply with a code fence ending at EOF passes silently" {
  local message='確認済みです。
~~~bash
bats --filter "English reply with a few Japanese labels" tests/claude-japanese-stop-hook.bats'
  run "$HOOK" <<<"$(stop_event "$message")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "English prose after closed code is still checked" {
  local message
  for message in \
    $'~~~text\n確認済みです。\n~~~\nDone.' \
    $'```確認済みです。```\nDone.'; do
    run "$HOOK" <<<"$(stop_event "$message")"
    [ "$status" -eq 0 ]
    jq -e '.decision == "block"' <<<"$output"
  done
}

@test "Japanese, code-only, re-entered and invalid input pass silently" {
  local event
  for event in \
    "$(stop_event 'テストは成功しました。`lefthook run test` を実行済みです。')" \
    "$(stop_event $'```bash\nbats tests/dogfood.bats\n```')" \
    "$(stop_event $'~~~bash\necho hello\n~~~')" \
    "$(stop_event '~~~bash')" \
    "$(stop_event '``echo `hello` ``')" \
    "$(stop_event 'Done.' true)" \
    'not json'; do
    run "$HOOK" <<<"$event"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}
