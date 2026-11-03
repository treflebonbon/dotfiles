#!/usr/bin/env bats

load 'test_helper'

readonly TEMPLATE="$BATS_TEST_DIRNAME/../.chezmoi.toml.tmpl"

@test "chezmoi cd uses system bash instead of PATH-resolved nix bash" {
  grep -q 'command = "/bin/bash"' "$TEMPLATE"
  if grep -q 'command = "bash"' "$TEMPLATE"; then
    return 1
  fi
}

@test "Git identity preserves quotes, comments, backslashes and Japanese text" {
  local name='Alice #One "Q" C:\Users 日本語' email='"quoted\\user"@example.invalid'
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
