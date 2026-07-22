#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$PROJECT_ROOT/local-skills/to-pr/SKILL.md"
}

@test "to-pr records Playwright evidence in a fresh temporary bundle" {
  grep -Fq 'mktemp -d' "$SKILL"
  grep -Fq 'playwright-report.md' "$SKILL"
  grep -Fq '## Playwright Evidence' "$SKILL"
  grep -Fq 'console/network errors' "$SKILL"
  grep -Fq 'raw requests' "$SKILL"
}

@test "to-pr publishes images as PR attachments with a manual WSL2 fallback" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local adr="$PROJECT_ROOT/docs/adr/0026-attach-playwright-evidence-to-pr.md"

  grep -Fq 'authenticated GitHub session' "$SKILL"
  grep -Fq 'anonymized URL' "$SKILL"
  grep -Fq 'gh pr edit --body-file' "$SKILL"
  grep -Fq 'On WSL2' "$SKILL"
  grep -Fq '手動添付待ち' "$SKILL"
  ! grep -Fq '.github/pr-assets' "$SKILL"

  grep -Fq 'GitHub の PR 添付' "$runtime"
  grep -Fq '手動添付待ち' "$runtime"
  ! grep -Fq '.github/pr-assets' "$runtime"

  [ -f "$adr" ]
  grep -Fq 'ADR-0004 の画像 commit 方針を置き換える' "$adr"
}
