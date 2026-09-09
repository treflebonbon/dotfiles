#!/usr/bin/env bats

@test "rop-visualizer renderer preserves source and validates flowchart paths" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$project_root/tests/helpers/rop-renderer-contract.py" \
    "$project_root/local-skills/rop-visualizer/scripts/render.py"
  [ "$status" -eq 0 ]
}
