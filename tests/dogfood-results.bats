setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF_DIR="$BATS_TEST_TMPDIR/references"
  mkdir -p "$REF_DIR/node_modules/playwright"
  cp "$PROJECT_ROOT/local-skills/dogfood-to-issues/references/"*.mjs "$REF_DIR/"
  cp "$PROJECT_ROOT/tests/fixtures/dogfood-playwright.mjs" "$REF_DIR/node_modules/playwright/index.mjs"
  printf '%s\n' '{"type":"module","exports":"./index.mjs"}' >"$REF_DIR/node_modules/playwright/package.json"
  export DOGFOOD_TEST_WSL=0
  RUNNER="$REF_DIR/playwright-dogfood-runner.mjs"
  OUT="$BATS_TEST_TMPDIR/output"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$PROJECT_ROOT/tests/fixtures/dogfood-annotation-cli.sh" "$BATS_TEST_TMPDIR/bin/playwright-cli"
  chmod +x "$BATS_TEST_TMPDIR/bin/playwright-cli"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "retry keeps earlier evidence and resolves both latest and historical report paths" {
  run node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 0 ]
  first="$(sed -n 's/^Attempt directory: //p' "$OUT/report.md")"
  [ -n "$first" ]
  [ -f "$OUT/$first/report.md" ]

  run env DOGFOOD_FAULTS=screenshot,trace-stop node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 0 ]
  second="$(sed -n 's/^Attempt directory: //p' "$OUT/report.md")"
  [ "$first" != "$second" ]
  [ -f "$OUT/$first/screenshots/initial.png" ]
  [ ! -e "$OUT/$second/screenshots/initial.png" ]
  ! grep '^Evidence:' "$OUT/report.md" | grep -Fq "$first/"
  python3 - "$OUT/report.md" "$OUT/$first/report.md" "$OUT/$second/report.md" <<'PY'
from pathlib import Path
import sys
for filename in sys.argv[1:]:
    report = Path(filename)
    evidence = [p for line in report.read_text().splitlines() if line.startswith('Evidence: ') for p in line[10:].split(', ') if p]
    assert evidence, filename
    for relative in evidence:
        artifact = report.parent / relative
        assert artifact.is_file() and artifact.stat().st_size > 0, artifact
PY
}

@test "startup failure is recorded as failed rather than a clean zero-finding run" {
  run env DOGFOOD_FAULTS=startup node "$RUNNER" --target about:blank --output "$OUT"

  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"
  grep -Fq 'startup failed' "$OUT/report.md"
  ! grep -Fq 'target loaded' "$OUT/report.md"
  ! grep -q '^### ISSUE-' "$OUT/report.md"
}

@test "missing screenshot and trace warn without losing findings or advertising missing evidence" {
  run env DOGFOOD_FAULTS=screenshot,trace-stop node "$RUNNER" --target about:blank --output "$OUT"

  [ "$status" -eq 0 ]
  grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Evidence status: partial' "$OUT/report.md"
  grep -Fq 'screenshot failed' "$OUT/report.md"
  grep -Fq 'trace-stop failed' "$OUT/report.md"
  grep -Fq 'observed console error' "$OUT/report.md"
  ! grep '^Evidence:' "$OUT/report.md" | grep -Eq 'initial.png|playwright-trace.zip'
}

@test "cleanup failure stops the run while preserving navigation and console findings" {
  run env DOGFOOD_FAULTS=navigation,close node "$RUNNER" --target about:blank --output "$OUT"

  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"
  grep -Fq 'close failed' "$OUT/report.md"
  grep -Fq 'Navigation to target failed' "$OUT/report.md"
  grep -Fq 'observed console error' "$OUT/report.md"
  ! grep -Fq 'target loaded' "$OUT/report.md"
  ! grep '^Evidence:' "$OUT/report.md" | grep -Fq '.webm'
}

@test "detach failure retains already submitted annotations and their files" {
  run env DOGFOOD_FAULTS=detach node "$RUNNER" --target about:blank --output "$OUT" --annotate

  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"
  grep -Fq 'detach failed' "$OUT/report.md"
  grep -Fq 'Control is clipped' "$OUT/report.md"
  grep -Fq 'Review this control.' "$OUT/report.md"
  attempt="$(sed -n 's/^Attempt directory: //p' "$OUT/report.md")"
  [ -f "$OUT/$attempt/annotations/response.json" ]
  grep '^Evidence:' "$OUT/report.md" | grep -Fq "$attempt/.playwright-cli/annotation.png"
  [ -f "$OUT/$attempt/.playwright-cli/annotation.png" ]
}

@test "annotation and cleanup failures both survive alongside earlier findings" {
  run env DOGFOOD_FAULTS=show,close node "$RUNNER" --target about:blank --output "$OUT" --annotate

  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"
  grep '^Failure: inspection:' "$OUT/report.md" | grep -Fq 'show failed'
  grep '^Failure: context close:' "$OUT/report.md" | grep -Fq 'close failed'
  grep -Fq 'observed console error' "$OUT/report.md"
  ! grep '^Evidence:' "$OUT/report.md" | grep -Fq '.webm'
}

@test "zero-finding completed reports expose the collected evidence for audit" {
  run env DOGFOOD_OBSERVATION=none node "$RUNNER" --target about:blank --output "$OUT"

  [ "$status" -eq 0 ]
  grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Evidence status: complete' "$OUT/report.md"
  grep -Fq '## Collected evidence' "$OUT/report.md"
  grep -Fq 'screenshots/initial.png' "$OUT/report.md"
  ! grep -q '^### ISSUE-' "$OUT/report.md"
}

@test "report-only completion keeps observations and explains unavailable evidence" {
  run env DOGFOOD_FAULTS=aux-write node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 0 ]
  grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Evidence status: unavailable' "$OUT/report.md"
  grep -Fq 'auxiliary write failed' "$OUT/report.md"
  grep -Fq 'observed console error' "$OUT/report.md"
  ! grep -Eq '^Evidence: .+' "$OUT/report.md"
}

@test "only a finalized headless MV3 attempt may request headed retry" {
  run env DOGFOOD_FAULTS=sw node "$RUNNER" --target about:blank --output "$OUT" --extension fixture
  [ "$status" -eq 2 ]
  grep -Fq 'Run status: retryable' "$OUT/report.md"

  run env DOGFOOD_FAULTS=sw,close node "$RUNNER" --target about:blank --output "$OUT" --extension fixture
  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"

  run env DOGFOOD_FAULTS=sw node "$RUNNER" --target about:blank --output "$OUT" --extension fixture --headed
  [ "$status" -eq 0 ]
  grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Severity: Critical' "$OUT/report.md"
}

@test "report publication failure cannot leave a completed latest report" {
  run env DOGFOOD_FAULTS=report-write node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'report publish failed'* ]]
  ! grep -Fq 'Run status: completed' "$OUT/report.md"
}

@test "interrupted retry replaces an earlier completed report with an unfinished attempt" {
  run node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 0 ]
  first="$(sed -n 's/^Attempt directory: //p' "$OUT/report.md")"

  run env DOGFOOD_FAULTS=interrupt node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -ne 0 ]
  grep -Fq 'Run status: running' "$OUT/report.md"
  ! grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Run status: completed' "$OUT/$first/report.md"
}

@test "navigation failure alone is a finding and not a runner failure" {
  run env DOGFOOD_FAULTS=navigation node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 0 ]
  grep -Fq 'Run status: completed' "$OUT/report.md"
  grep -Fq 'Navigation to target failed' "$OUT/report.md"
  ! grep -Fq 'target loaded' "$OUT/report.md"
}

run_documented_invocation() {
  mkdir -p "$OUT"
  printf '%s\n' 'MV3 service worker did not register' >"$OUT/report.md"
  export CLI_RUN_LOG="$BATS_TEST_TMPDIR/cli-runs"
  export CODEX_SKILL_DIR="$PROJECT_ROOT/local-skills/dogfood-to-issues"
  export WT_DIR="$BATS_TEST_TMPDIR" OUTPUT_DIR=output TARGET_URL=about:blank EXTENSION_PATH=fixture
  export WSL_DISTRO_NAME=test
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$BATS_TEST_TMPDIR/bin/npm"
  cat >"$BATS_TEST_TMPDIR/bin/node" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLI_RUN_LOG"
if [[ " $* " == *" --headed "* ]]; then
  exit "${HEADED_CODE:-0}"
fi
exit "${PRIMARY_CODE:-0}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"{npm,node}
  python3 - "$CODEX_SKILL_DIR/SKILL.md" "$BATS_TEST_TMPDIR/invoke.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().split('```bash\n', 1)[1].split('```', 1)[0]
Path(sys.argv[2]).write_text('set -eu\n' + text + '\nprintf "review allowed\\n"\n')
PY
  run bash "$BATS_TEST_TMPDIR/invoke.sh"
}

@test "documented caller never retries exit 1 based on a stale MV3 report" {
  export PRIMARY_CODE=1
  run_documented_invocation
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$CLI_RUN_LOG")" -eq 1 ]
  [[ "$output" != *'review allowed'* ]]
}

@test "operational diagnostics cannot introduce finding blocks" {
  run env DOGFOOD_FAULTS=diagnostic-lines node "$RUNNER" --target about:blank --output "$OUT"
  [ "$status" -eq 1 ]
  grep -Fq 'startup failed' "$OUT/report.md"
  ! grep -q '^### ISSUE-' "$OUT/report.md"
}

@test "documented caller retries exit 2 exactly once and then permits completed review" {
  export PRIMARY_CODE=2 HEADED_CODE=0
  run_documented_invocation
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CLI_RUN_LOG")" -eq 2 ]
  [[ "$output" == *'review allowed'* ]]
}

@test "documented caller stops if the headed retry fails or requests another retry" {
  export PRIMARY_CODE=2 HEADED_CODE=2
  run_documented_invocation
  [ "$status" -eq 2 ]
  [ "$(wc -l <"$CLI_RUN_LOG")" -eq 2 ]
  [[ "$output" != *'review allowed'* ]]
}

@test "native dogfood uses the supplied Chromium bundle across npm revision updates" {
  local layout index=0
  for layout in \
    'chrome-linux64/chrome' \
    'chrome-linux/chrome' \
    'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'; do
    index=$((index + 1))
    export PLAYWRIGHT_BROWSERS_PATH="$BATS_TEST_TMPDIR/nix-browsers-$index"
    local bundle="$BATS_TEST_TMPDIR/chromium-output-$index"
    mkdir -p "$PLAYWRIGHT_BROWSERS_PATH" "$bundle/$(dirname "$layout")"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$bundle/$layout"
    chmod +x "$bundle/$layout"
    ln -s "$bundle" "$PLAYWRIGHT_BROWSERS_PATH/chromium-1217"
    export DOGFOOD_EXPECT_CHROMIUM="$PLAYWRIGHT_BROWSERS_PATH/chromium-1217/$layout"

    run node "$RUNNER" --target about:blank --output "$OUT-$index" --extension fixture

    [ "$status" -eq 0 ]
    grep -Fq 'Run status: completed' "$OUT-$index/report.md"
    grep -Fq 'screenshots/initial.png' "$OUT-$index/report.md"
  done
}

@test "native dogfood reports an unusable supplied bundle instead of launching another browser" {
  export PLAYWRIGHT_BROWSERS_PATH="$BATS_TEST_TMPDIR/nix-browsers"
  mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"

  run node "$RUNNER" --target about:blank --output "$OUT"

  [ "$status" -eq 1 ]
  grep -Fq 'Run status: failed' "$OUT/report.md"
  grep -Fq 'Expected one Chromium executable' "$OUT/report.md"
  ! grep -Fq 'target loaded' "$OUT/report.md"
}
