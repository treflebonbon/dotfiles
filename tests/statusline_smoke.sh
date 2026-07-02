#!/usr/bin/env bash
# statusline_smoke.sh - Smoke test for private_dot_claude/executable_statusline.sh
# Pipes fixture JSONs through the statusline script and asserts on output shape
# (line count, label markers, color thresholds, fallback behavior).
#
# Fixtures live in /tmp/statusline-fixtures/ and are created out-of-band by
# the implement-issue plan (Step 1). Run from the repo root.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$REPO_ROOT/private_dot_claude/executable_statusline.sh"
FIXTURES="/tmp/statusline-fixtures"

PASS=0
FAIL=0
FAILED_TESTS=()

# Strip ANSI escape sequences so substring checks work on visible text.
strip_ansi() {
  # shellcheck disable=SC2001
  sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name: expected to contain '$needle'")
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name: expected NOT to contain '$needle'")
  else
    PASS=$((PASS + 1))
  fi
}

assert_line_count() {
  local name="$1" haystack="$2" expected="$3"
  # printf '%s' won't add a trailing newline, but the script's printf '%b\n'
  # ends each of the first 2 lines with \n and the 3rd with no newline.
  # Counting newlines + (1 if there's content on the last line) gives the
  # visible line count.
  local nl_count
  nl_count=$(printf '%s' "$haystack" | tr -cd '\n' | wc -c)
  local last_line_chars
  last_line_chars=$(printf '%s' "$haystack" | tail -c 1 | tr -d '\n' | wc -c)
  local total=$nl_count
  if [ "$last_line_chars" -gt 0 ]; then
    total=$((nl_count + 1))
  fi
  if [ "$total" -eq "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name: expected $expected lines, got $total")
  fi
}

assert_exit() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name: expected exit $expected, got $actual")
  fi
}

run_fixture() {
  local fixture="$1"
  bash "$STATUSLINE" <"$FIXTURES/$fixture"
}

# ----------------------------------------------------------------------
# Preconditions
# ----------------------------------------------------------------------
if [ ! -x "$STATUSLINE" ] && [ ! -r "$STATUSLINE" ]; then
  echo "FATAL: statusline script not found at $STATUSLINE" >&2
  exit 2
fi
for f in full.json no-rate-limits.json empty-current-usage.json; do
  if [ ! -r "$FIXTURES/$f" ]; then
    echo "FATAL: fixture not found: $FIXTURES/$f" >&2
    exit 2
  fi
done

# ----------------------------------------------------------------------
# full.json: 3 lines, ctx/5h/7d labels, model, line stats
# ----------------------------------------------------------------------
out=$(run_fixture full.json)
exit_code=$?
visible=$(printf '%s' "$out" | strip_ansi)

assert_exit "full: exit 0" "$exit_code" 0
assert_line_count "full: 3 lines" "$out" 3
assert_contains "full: ctx label" "$visible" "ctx"
assert_contains "full: 5h label" "$visible" "5h"
assert_contains "full: 7d label" "$visible" "7d"
assert_contains "full: model name" "$visible" "Opus 4.7"
assert_contains "full: line stats added" "$visible" "+120"
assert_contains "full: line stats removed" "$visible" "-30"
assert_contains "full: ctx pct 45%" "$visible" "45%"
assert_contains "full: 5h pct 30%" "$visible" "30%"
assert_contains "full: 7d pct 50%" "$visible" "50%"
assert_not_contains "full: no brain emoji" "$visible" "🧠"
assert_not_contains "full: no \$cost" "$visible" "\$0.00"

# ----------------------------------------------------------------------
# no-rate-limits.json: 5h/7d fall back to --% (DIM)
# ----------------------------------------------------------------------
out=$(run_fixture no-rate-limits.json)
exit_code=$?
visible=$(printf '%s' "$out" | strip_ansi)

assert_exit "no-rate-limits: exit 0" "$exit_code" 0
assert_line_count "no-rate-limits: 3 lines" "$out" 3
assert_contains "no-rate-limits: ctx pct 45%" "$visible" "45%"
assert_contains "no-rate-limits: --%% fallback present" "$visible" "--%"
# +0/-0 must NOT appear in line stats (script suppresses zero stats)
assert_not_contains "no-rate-limits: no +0/-0 stats" "$visible" "+0/-0"

# ----------------------------------------------------------------------
# empty-current-usage.json: CTX_PCT falls back to used_percentage; 5h RED, 7d RED
# ----------------------------------------------------------------------
out=$(run_fixture empty-current-usage.json)
exit_code=$?
visible=$(printf '%s' "$out" | strip_ansi)

assert_exit "empty-current-usage: exit 0" "$exit_code" 0
assert_line_count "empty-current-usage: 3 lines" "$out" 3
assert_contains "empty-current-usage: ctx pct 12%" "$visible" "12%"
assert_contains "empty-current-usage: 5h pct 85%" "$visible" "85%"
assert_contains "empty-current-usage: 7d pct 95%" "$visible" "95%"
assert_contains "empty-current-usage: model Sonnet 4.6" "$visible" "Sonnet 4.6"
# RED ANSI sequence (\033[31m) must be present for both rate limit lines
assert_contains "empty-current-usage: red ANSI for 5h/7d" "$out" $'\033[31m'

# ----------------------------------------------------------------------
# Empty stdin: exit 0, no output
# ----------------------------------------------------------------------
empty_out=$(printf '' | bash "$STATUSLINE")
empty_exit=$?
assert_exit "empty stdin: exit 0" "$empty_exit" 0
if [ -z "$empty_out" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("empty stdin: expected no output, got: $empty_out")
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Failed assertions:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
