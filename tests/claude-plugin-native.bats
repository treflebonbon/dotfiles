#!/usr/bin/env bats

@test "real Claude plugin sync preserves rendered managed settings on two repeats" {
  [ "${CLAUDE_PLUGIN_NATIVE:-0}" = 1 ] ||
    skip "opt in with CLAUDE_PLUGIN_NATIVE=1 and CLAUDE_PLUGIN_NATIVE_CHECKOUT"
  [ -n "${CLAUDE_PLUGIN_NATIVE_CHECKOUT:-}" ] || {
    printf '%s\n' 'CLAUDE_PLUGIN_NATIVE_CHECKOUT must point to the pinned public checkout' >&3
    return 1
  }
  local source
  source="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$source/scripts/verify-claude-plugin-sync.py" "$source" \
    --checkout "$CLAUDE_PLUGIN_NATIVE_CHECKOUT"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Claude plugin"* ]]
}
