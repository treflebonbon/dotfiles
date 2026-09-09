#!/usr/bin/env bats

@test "six language templates run devShell and with-env from independent locked repositories" {
  [ "${TEMPLATE_WITH_ENV_REAL_NIX:-0}" = 1 ] || skip "opt in with TEMPLATE_WITH_ENV_REAL_NIX=1; builds all six language devShells"
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$project_root/tests/helpers/template-with-env.py"
  printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
