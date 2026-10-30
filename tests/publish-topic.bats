#!/usr/bin/env bats

@test "topic publication records push separately and verifies without another push" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$root/tests/publish-topic.py"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
