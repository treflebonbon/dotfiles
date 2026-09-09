#!/usr/bin/env bats

require_isolation_runtime() {
  [ "${SECRET_ISOLATION_REAL_RUNTIME:-0}" = 1 ] ||
    skip "opt in with SECRET_ISOLATION_REAL_RUNTIME=1; requires real Nix/Codex and bubblewrap"
  [ "$(uname -s)" = Linux ] || {
    printf '%s\n' 'real isolation requires Linux/WSL2' >&3
    return 1
  }
  local tool
  for tool in nix bash cat python3 git codex gh bwrap; do
    command -v "$tool" >/dev/null || {
      printf 'missing required isolation tool: %s\n' "$tool" >&3
      return 1
    }
  done
}

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
  require_isolation_runtime
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
  require_isolation_runtime
  local scenario
  for scenario in log-leak log-leak-success; do
    run python3 "$BATS_TEST_DIRNAME/../scripts/secret-isolation-probe.py" --output "$BATS_TEST_TMPDIR/probe/$scenario" --scenario "$scenario"
    [ "$status" -ne 0 ]
    [[ "$output" == *"synthetic secret detected in artifacts"* ]]
    [[ "$output" != *"synthetic-tool-auth"* ]]
    ! rg -q 'synthetic-tool-auth' "$BATS_TEST_TMPDIR/probe/$scenario/runtime.log"
  done
}

@test "timeouts retain diagnostics and failure details without exposing captured synthetic secrets" {
  require_isolation_runtime
  local scenario probe
  for scenario in isolation-timeout isolation-timeout-leak codex-timeout; do
    probe="$BATS_TEST_TMPDIR/probe/$scenario"
    run python3 "$BATS_TEST_DIRNAME/../scripts/secret-isolation-probe.py" --output "$probe" --scenario "$scenario"
    [ "$status" -ne 0 ]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"synthetic-tool-auth"* ]]
    [ -s "$probe/runtime.log" ]
    python3 - "$probe" "$scenario" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
scenario = sys.argv[2]
report = json.loads((root / "report.json").read_text())
assert report["fixture_result"] == "failed"
assert report["production_ready"] is False
assert report["timeout_seconds"] > 0
assert report["timeout_stage"] == ("codex" if scenario == "codex-timeout" else "isolation")
assert "checks" not in report
if scenario == "codex-timeout":
    assert (root / "evidence/codex-started").exists()
    assert (root / "evidence/codex.jsonl").stat().st_size > 0
    assert (root / "evidence/codex.stderr").exists()
    assert json.loads((root / "evidence/provider.json").read_text())
else:
    assert not (root / "evidence/codex-started").exists()
    log = (root / "runtime.log").read_text()
    assert "timeout fixture stdout" in log
    assert "timeout fixture stderr" in log
for path in [root / "runtime.log", root / "report.json", *(root / "evidence").iterdir()]:
    assert b"synthetic-tool-auth" not in path.read_bytes(), path.name
if scenario.endswith("-leak"):
    assert "[redacted synthetic value]" in (root / "runtime.log").read_text()
PY
  done
}

@test "real Nix and Codex execute Git, GitHub and MCP tasks without host fixture secrets" {
  require_isolation_runtime
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
