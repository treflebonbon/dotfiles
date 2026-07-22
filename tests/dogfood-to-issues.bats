setup_file() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF_DIR="$PROJECT_ROOT/local-skills/dogfood-to-issues/references"
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
}

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF_DIR="$PROJECT_ROOT/local-skills/dogfood-to-issues/references"
  RUNNER="$REF_DIR/playwright-dogfood-runner.mjs"
  export NODE_BIN="$(command -v node)"
  export REAL_PLAYWRIGHT_CLI="$(command -v playwright-cli)"
  export FAKE_CLI_LOG="$BATS_TEST_TMPDIR/playwright-cli.log"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/playwright-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_CLI_LOG"

case " $* " in
  *" show --help "*)
    if [[ "${FAKE_CLI_MODE:-}" == "unsupported" ]]; then
      printf '%s\n' 'Options:'
    else
      printf '%s\n' 'Options:' '  --annotate  switch the dashboard into annotation mode.'
    fi
    ;;
  *" attach "*)
    if [[ "${FAKE_CLI_MODE:-}" == "attach-fail" ]]; then
      printf '%s\n' 'attach failed' >&2
      exit 1
    fi
    if [[ "${FAKE_CLI_MODE:-}" == "cdp-probe" ]]; then
      "$REAL_PLAYWRIGHT_CLI" "$@"
    fi
    ;;
  *" show --annotate --json "*)
    mkdir -p .playwright-cli
    printf 'png' >.playwright-cli/annotations.png
    printf '%s\n' '- button "Save"' >.playwright-cli/annotations.yaml
    if [[ "${FAKE_CLI_MODE:-}" == "show-fail" ]]; then
      printf '%s\n' 'dashboard failed' >&2
      exit 1
    elif [[ "${FAKE_CLI_MODE:-}" == "cdp-probe" ]]; then
      "$REAL_PLAYWRIGHT_CLI" "$1" eval '() => document.URL' --json >>"$FAKE_CLI_LOG"
      printf '%s\n' '{"result":"No annotations were submitted."}'
    elif [[ "${FAKE_CLI_MODE:-}" == "empty" ]]; then
      printf '%s\n' '{"result":"No annotations were submitted."}'
    else
      printf '%s\n' '{"result":"Overall contrast needs attention.\nsession / tab @ https://example.com/frame (1440x1000)\n  { x: 10, y: 20, width: 30, height: 40 }: First annotation\n\nSecond line of the same comment\n  { x: 50, y: 60, width: 70, height: 80 }: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n- [Annotation image](.playwright-cli/annotations.png)\n- [Annotation snapshot](.playwright-cli/annotations.yaml)"}'
    fi
    ;;
  *" detach "*)
    if [[ "${FAKE_CLI_MODE:-}" == "cdp-probe" ]]; then
      "$REAL_PLAYWRIGHT_CLI" "$@"
    fi
    ;;
  *)
    printf 'unexpected command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/playwright-cli"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "dogfood without annotation preserves the existing report path" {
  local out="$BATS_TEST_TMPDIR/output"

  run node "$RUNNER" --target about:blank --output "$out"

  [ "$status" -eq 0 ]
  grep -Fq 'No findings: target loaded and no critical browser errors were detected.' "$out/report.md"
  [ ! -e "$FAKE_CLI_LOG" ]
  [ ! -e "$out/annotations" ]
}

@test "annotation cannot be combined with resume" {
  local out="$BATS_TEST_TMPDIR/output"

  run node "$RUNNER" --target about:blank --output "$out" --annotate --resume previous-output

  [ "$status" -ne 0 ]
  [[ "$output" == *"--annotate cannot be combined with --resume"* ]]
  [ ! -e "$out" ]
  [ ! -e "$FAKE_CLI_LOG" ]
}

@test "annotated dogfood converts submitted feedback into auditable findings" {
  local out="$BATS_TEST_TMPDIR/output"

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -eq 0 ]
  [ "$(grep -c '^### ISSUE-' "$out/report.md")" -eq 3 ]
  grep -Fq 'URL: https://example.com/frame' "$out/report.md"
  grep -Fq 'Coordinates: x=10, y=20, width=30, height=40' "$out/report.md"
  grep -Fq 'Second line of the same comment' "$out/report.md"
  [[ "$(<"$out/report.md")" == *$'Comment: First annotation\n\nSecond line of the same comment'* ]]
  grep -Fq 'Viewport: 1440x1000' "$out/report.md"
  grep -Fq 'Evidence: .playwright-cli/annotations.png, .playwright-cli/annotations.yaml, annotations/response.json' "$out/report.md"
  [ "$(sed -n 's/^### ISSUE-[0-9][0-9][0-9]: //p' "$out/report.md" | tail -1 | wc -c)" -eq 121 ]
  [ -f "$out/.playwright-cli/annotations.png" ]
  [ -f "$out/.playwright-cli/annotations.yaml" ]
  [ -f "$out/annotations/response.json" ]
  grep -Fq 'attach --cdp=http://127.0.0.1:' "$FAKE_CLI_LOG"
  grep -Fq 'show --annotate --json' "$FAKE_CLI_LOG"
  grep -Fq 'detach' "$FAKE_CLI_LOG"
}

@test "empty annotation submission keeps only automated findings" {
  local out="$BATS_TEST_TMPDIR/output"
  export FAKE_CLI_MODE=empty

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -eq 0 ]
  grep -Fq 'No findings: target loaded and no critical browser errors were detected.' "$out/report.md"
  [ -f "$out/annotations/response.json" ]
}

@test "annotation attaches to the runner-owned Chromium and leaves it alive" {
  local out="$BATS_TEST_TMPDIR/output"
  export FAKE_CLI_MODE=cdp-probe

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -eq 0 ]
  grep -Fq 'about:blank' "$FAKE_CLI_LOG"
  grep -Fq 'detach' "$FAKE_CLI_LOG"
  [ -f "$out/traces/playwright-trace.zip" ]
}

@test "annotation attach failure still finalizes automated evidence" {
  local out="$BATS_TEST_TMPDIR/output"
  export FAKE_CLI_MODE=attach-fail

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -ne 0 ]
  [[ "$output" == *"attach failed"* ]]
  [ -f "$out/report.md" ]
  [ -f "$out/traces/playwright-trace.zip" ]
  [ "$(find "$out/videos" -name '*.webm' | wc -l)" -ge 1 ]
}

@test "missing Playwright CLI still finalizes automated evidence" {
  local out="$BATS_TEST_TMPDIR/output"
  local path_without_cli="$BATS_TEST_TMPDIR/path-without-cli"
  mkdir -p "$path_without_cli"
  ln -s "$NODE_BIN" "$path_without_cli/node"

  run env PATH="$path_without_cli" "$NODE_BIN" "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -ne 0 ]
  [[ "$output" == *"playwright-cli show --help failed"* ]]
  [ -f "$out/report.md" ]
  [ -f "$out/traces/playwright-trace.zip" ]
  [ "$(find "$out/videos" -name '*.webm' | wc -l)" -ge 1 ]
}

@test "unsupported annotation command still finalizes automated evidence" {
  local out="$BATS_TEST_TMPDIR/output"
  export FAKE_CLI_MODE=unsupported

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -ne 0 ]
  [[ "$output" == *"does not support show --annotate"* ]]
  [ -f "$out/report.md" ]
  [ -f "$out/traces/playwright-trace.zip" ]
}

@test "annotation dashboard failure detaches and finalizes automated evidence" {
  local out="$BATS_TEST_TMPDIR/output"
  export FAKE_CLI_MODE=show-fail

  run node "$RUNNER" --target about:blank --output "$out" --annotate

  [ "$status" -ne 0 ]
  [[ "$output" == *"dashboard failed"* ]]
  grep -Fq 'detach' "$FAKE_CLI_LOG"
  [ -f "$out/report.md" ]
  [ -f "$out/traces/playwright-trace.zip" ]
}

@test "MV3 inspection and annotation share the persistent Chromium context" {
  local out="$BATS_TEST_TMPDIR/output"
  local extension="$REF_DIR/fixtures/mv3-min"
  export FAKE_CLI_MODE=cdp-probe

  run node "$RUNNER" --target about:blank --extension "$extension" --output "$out" --annotate

  [ "$status" -eq 0 ]
  grep -Eq '^Extension ID: [a-z]+' "$out/report.md"
  grep -Fq 'about:blank' "$FAKE_CLI_LOG"
  ! grep -Fq 'MV3 service worker did not register' "$out/report.md"
}
