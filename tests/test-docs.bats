#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$PROJECT_ROOT"
}

@test "a docs-only change plans the contract Bats plus Bats that reference the file" {
  run -0 scripts/test-docs.sh --plan runtime/skill-harness.md
  [[ "$output" == *"tests/workflow-contract.bats"* ]]
  [[ "$output" == *"tests/autonomous-peer-contract.bats"* ]]
}

@test "an out-of-scope record is a docs-only change" {
  run -0 scripts/test-docs.sh --plan .out-of-scope/embedded-bash-shellcheck.md
  [[ "$output" == *"tests/workflow-contract.bats"* ]]
}

@test "a non-docs file in the change requires the full Bats" {
  run scripts/test-docs.sh --plan runtime/index.md tests/with-env.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"例外の対象外: tests/with-env.bats"* ]]
}

@test "configuration and templates stay outside the exception" {
  local file
  for file in lefthook.yml .chezmoiignore private_dot_claude/settings.json.tmpl private_dot_config/codex/config.toml.tmpl; do
    run scripts/test-docs.sh --plan "$file"
    [ "$status" -eq 2 ]
  done
}
