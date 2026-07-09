#!/usr/bin/env bats

load 'test_helper'

readonly TEMPLATE="$BATS_TEST_DIRNAME/../.chezmoi.toml.tmpl"

@test "chezmoi cd uses system bash instead of PATH-resolved nix bash" {
  grep -q 'command = "/bin/bash"' "$TEMPLATE"
  if grep -q 'command = "bash"' "$TEMPLATE"; then
    return 1
  fi
}
