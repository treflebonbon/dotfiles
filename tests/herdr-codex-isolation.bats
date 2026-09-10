#!/usr/bin/env bats

load helpers/raw-codex
teardown() { raw_cleanup; }

@test "Herdr probe supports native Linux flakes and reaps failed servers" {
  run python3 -B "$BATS_TEST_DIRNAME/helpers/herdr-codex-isolation.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "real Herdr events and terminals preserve host dotenv while raw Codex develops without it" {
  [ "${HERDR_ISOLATION_REAL:-0}" = 1 ] || skip "opt in with HERDR_ISOLATION_REAL=1; starts a private Herdr server and real Nix/Codex"
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$project_root/scripts/herdr-codex-isolation.py" --output "$BATS_TEST_TMPDIR/herdr"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/herdr/report.json" ]
}
