#!/usr/bin/env bats

load 'test_helper'

readonly TEMPLATE="$BATS_TEST_DIRNAME/../.chezmoi.toml.tmpl"

@test "chezmoi cd uses system bash instead of PATH-resolved nix bash" {
  grep -q 'command = "/bin/bash"' "$TEMPLATE"
  if grep -q 'command = "bash"' "$TEMPLATE"; then
    return 1
  fi
}

assert_git_identity() {
  local name="$1" email="$2"
  local config="$BATS_TEST_TMPDIR/identity.json" rendered="$BATS_TEST_TMPDIR/gitconfig"
  jq -nc --arg name "$name" --arg email "$email" \
    '{data:{git_user_name:$name,git_user_email:$email}}' >"$config"
  chezmoi --source "$BATS_TEST_DIRNAME/.." --config "$config" execute-template \
    <"$BATS_TEST_DIRNAME/../dot_gitconfig.tmpl" >"$rendered"

  run git config --file "$rendered" --get user.name
  assert_success
  assert_output "$name"
  run git config --file "$rendered" --get user.email
  assert_success
  assert_output "$email"
}

@test "Git identity preserves quotes, comments, backslashes and Japanese text" {
  assert_git_identity 'Alice #One "Q" C:\Users 日本語' '"quoted\\user"@example.invalid'
}

@test "Git identity preserves nonbreaking Unicode spaces" {
  assert_git_identity $'Alice\u00a0日本語\u2007Name\u202f' $'alice\u00a0@example.invalid'
}
