#!/usr/bin/env bats

@test "gateway ownership releases partial starts, failed preparations, commands and cleanup failures" {
  [ "$(uname -s)" = Linux ] || skip "raw gateway lifecycle requires Linux procfs"
  run python3 -I "$BATS_TEST_DIRNAME/helpers/gateway-lifecycle.py" \
    "$BATS_TEST_DIRNAME/../private_dot_local/share/codex-isolation" "$BATS_TEST_TMPDIR" -v
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
