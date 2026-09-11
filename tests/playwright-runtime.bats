#!/usr/bin/env bats

@test "Playwright runtime keeps locks and fails closed across records and process failures" {
  run node --test "$BATS_TEST_DIRNAME/fixtures/playwright-runtime.test.mjs"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "distributed Playwright package protects the direct CLI and retains shared FDs" {
  [[ -n "${TEST_PLAYWRIGHT_PACKAGE:-}" ]] || skip "Set TEST_PLAYWRIGHT_PACKAGE to the built playwright-cli Nix output"
  local package="$TEST_PLAYWRIGHT_PACKAGE"
  [ -x "$package/bin/managed-chrome-owner" ]
  [ -x "$package/libexec/playwright-runtime" ]
  [ -f "$package/share/playwright-cli/browser-lock.mjs" ]
  export TEST_MANAGED_CHROME_OWNER="$package/bin/managed-chrome-owner"
  export TEST_PLAYWRIGHT_RUNTIME_MODULE="$package/share/playwright-cli/playwright-runtime.mjs"
  run node --test "$BATS_TEST_DIRNAME/fixtures/playwright-runtime.test.mjs"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  run bats --filter 'direct relocate|relocate holds both locks|relocate retains every owner phase' "$BATS_TEST_DIRNAME/managed-chrome-owner.bats"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
