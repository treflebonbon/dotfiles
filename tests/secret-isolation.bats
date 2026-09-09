#!/usr/bin/env bats

teardown() {
  # Copied Nix store directories are read-only; allow Bats to remove its own fixture.
  python3 - "$BATS_TEST_TMPDIR/probe" <<'PY'
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
if root.is_dir():
    for parent, directories, _ in os.walk(root, followlinks=False):
        os.chmod(parent, os.stat(parent).st_mode | 0o700)
        directories[:] = [name for name in directories if not (Path(parent) / name).is_symlink()]
PY
}

@test "invalid linked input is rejected before starting isolated Nix or Codex" {
  local attack
  for attack in symlink-input hardlink-input; do
    run python3 "$BATS_TEST_DIRNAME/../scripts/secret-isolation-probe.py" --output "$BATS_TEST_TMPDIR/probe/$attack" --scenario "$attack"
    [ "$status" -ne 0 ]
    [[ "$output" == *"input must be a regular file with one link"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/probe/$attack/evidence/codex-started" ]
  done
}

@test "failed isolation never launches Codex and failed preparation permits only isolated diagnostics" {
  [ "$(uname -s)" = Linux ] || skip "outer isolation probe currently targets Linux/WSL2"
  local scenario
  for scenario in isolation-failure nix-failure hook-failure; do
    run python3 "$BATS_TEST_DIRNAME/../scripts/secret-isolation-probe.py" --output "$BATS_TEST_TMPDIR/probe/$scenario" --scenario "$scenario"
    [ "$status" -ne 0 ]
    [ -f "$BATS_TEST_TMPDIR/probe/$scenario/report.json" ]
    [ ! -e "$BATS_TEST_TMPDIR/probe/$scenario/evidence/codex-started" ]
    if [ "$scenario" = isolation-failure ]; then
      [[ "$output" != *"PASS host-secrets-unavailable"* ]]
    else
      [[ "$output" == *"PASS isolated-diagnostics"* ]]
    fi
  done
}

@test "synthetic log leaks fail both successful and failed preparation without disclosing the value" {
  [ "$(uname -s)" = Linux ] || skip "outer isolation probe currently targets Linux/WSL2"
  local scenario
  for scenario in log-leak log-leak-success; do
    run python3 "$BATS_TEST_DIRNAME/../scripts/secret-isolation-probe.py" --output "$BATS_TEST_TMPDIR/probe/$scenario" --scenario "$scenario"
    [ "$status" -ne 0 ]
    [[ "$output" == *"synthetic secret detected in artifacts"* ]]
    [[ "$output" != *"synthetic-tool-auth"* ]]
    ! rg -q 'synthetic-tool-auth' "$BATS_TEST_TMPDIR/probe/$scenario/runtime.log"
  done
}

@test "real Nix and Codex execute Git, GitHub and MCP tasks without host fixture secrets" {
  [ "$(uname -s)" = Linux ] || skip "outer isolation probe currently targets Linux/WSL2"
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  run python3 "$project_root/scripts/secret-isolation-probe.py" --output "$BATS_TEST_TMPDIR/probe"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&3
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS nix-environment"* ]]
  [[ "$output" == *"PASS host-secrets-unavailable"* ]]
  [[ "$output" == *"PASS codex-shell-git"* ]]
  [[ "$output" == *"PASS codex-mcp"* ]]
  [[ "$output" == *"PASS codex-github-fixture"* ]]
  [[ "$output" == *"PASS dynamic-host-boundary"* ]]
}
