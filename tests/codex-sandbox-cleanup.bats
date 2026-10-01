#!/usr/bin/env bats

setup() {
  [ "$(uname -s)" = Linux ] || skip "Linux sandbox cleanup"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "Codex sandbox removes missing dotenv after normal teardown" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" normal
}

@test "Codex sandbox removes missing dotenv after process-group SIGKILL" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" killed
}

@test "Codex sandbox removes missing dotenv after overlapping teardown and SIGKILL" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" overlap
}

@test "Codex sandbox preserves existing empty and nonempty dotenv after SIGKILL" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" existing
}

@test "Codex sandbox cleans up after SIGKILL when the command ignores SIGTERM" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" ignored
}

@test "Codex sandbox preserves stdout stderr and nonzero exit status through cleanup" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" exit-status
}

@test "Codex read-only sandbox preserves input from its controlling terminal" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" tty
}

@test "Codex supervised sandbox preserves terminal input and removes its denied mount target" {
  python3 "$PROJECT_ROOT/tests/helpers/codex-sandbox-cleanup.py" "$BATS_TEST_TMPDIR" tty-denied
}
