#!/usr/bin/env bats

@test "skills plugin checkout verification detects tampering outside git status" {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$PROJECT_ROOT/tests/skills-plugin-verify.py"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
