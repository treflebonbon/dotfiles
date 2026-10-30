#!/usr/bin/env bats

@test "Playwright runtime keeps locks and fails closed across records and process failures" {
  local skills_root="$(cd "${TREFLEBONBON_SKILLS_LIB:?run tests in the pinned skills-plugin devShell}/../.." && pwd)"
  local suite="$skills_root/packages/wsl2-browser/tests/playwright-runtime.bats"

  [ -f "$suite" ]
  run bats --filter '^Playwright runtime keeps locks and fails closed across records and process failures$' "$suite"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "distributed Playwright package protects the direct CLI and retains shared FDs" {
  [[ -n "${TEST_PLAYWRIGHT_PACKAGE:-}" ]] || skip "Set TEST_PLAYWRIGHT_PACKAGE to the built playwright-cli Nix output"
  local skills_root="$(cd "${TREFLEBONBON_SKILLS_LIB:?run tests in the pinned skills-plugin devShell}/../.." && pwd)"
  local package="$TEST_PLAYWRIGHT_PACKAGE"
  [ -x "$package/bin/managed-chrome-owner" ]
  [ -x "$package/bin/playwright-cli" ]
  [ -x "$package/libexec/playwright-runtime" ]
  [ -f "$package/share/playwright-cli/playwright-runtime.mjs" ]
  [ -f "$package/share/playwright-cli/browser-lock.mjs" ]
  run python3 "$BATS_TEST_DIRNAME/helpers/playwright-runtime-distribution.py" \
    "$package" "$skills_root" "$BATS_TEST_TMPDIR" "$PWD"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
