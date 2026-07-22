#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$PROJECT_ROOT/local-skills/to-pr/SKILL.md"
}

@test "to-pr can be invoked by the model after implementation" {
  ! grep -q '^disable-model-invocation:' "$SKILL"
  grep -Fq 'explicitly authorized AFK/autonomous completion' "$SKILL"
  grep -Fq 'otherwise do not invoke it automatically' "$SKILL"
}

@test "to-pr records Playwright evidence in a fresh temporary bundle" {
  grep -Fq 'mktemp -d' "$SKILL"
  grep -Fq 'playwright-report.md' "$SKILL"
  grep -Fq 'one representative `screenshot` for every UI criterion that was exercised' "$SKILL"
  grep -Fq '## Playwright Evidence' "$SKILL"
  grep -Fq 'console/network errors' "$SKILL"
  grep -Fq 'raw requests' "$SKILL"
}

@test "to-pr keeps Playwright CLI runtime artifacts out of the repository" {
  grep -Fq 'TO_PR_EVIDENCE_DIR="$(mktemp -d' "$SKILL"
  grep -Fq '(cd "$TO_PR_EVIDENCE_DIR" && playwright-cli -s=<branch-or-workspace-name> ...)' "$SKILL"
  grep -Fq 'Do not run `playwright-cli` from the repository worktree.' "$SKILL"
  grep -Fq 'Resolve repository-relative' "$SKILL"
  grep -Fq 'input paths to absolute paths' "$SKILL"
}

@test "to-pr publishes images as PR attachments with a manual WSL2 fallback" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local adr="$PROJECT_ROOT/docs/adr/0026-attach-playwright-evidence-to-pr.md"
  local attachment_section
  attachment_section="$(sed -n '/^## 6\. Attach Playwright evidence/,/^## Out of scope/p' "$SKILL" | tr '\n' ' ' | tr -s ' ')"

  grep -Fq 'authenticated GitHub session' "$SKILL"
  grep -Fq 'anonymized URL' "$SKILL"
  grep -Fq 'gh pr edit --body-file' "$SKILL"
  [[ "$attachment_section" == *'On WSL2, do not assume that a Windows Chrome session'* ]]
  [[ "$attachment_section" == *'only when Chrome running in WSL2 already has an authenticated GitHub session'* ]]
  [[ "$attachment_section" == *'If no authenticated browser is available'* ]]
  [[ "$attachment_section" == *'do not retry by logging in'* ]]
  [[ "$attachment_section" == *'手動添付待ち'* ]]
  [[ "$attachment_section" == *"bundle's absolute path and a file list"* ]]
  ! grep -Fq '.github/pr-assets' "$SKILL"

  grep -Fq 'GitHub の PR 添付' "$runtime"
  grep -Fq '手動添付待ち' "$runtime"
  ! grep -Fq '.github/pr-assets' "$runtime"

  [ -f "$adr" ]
  grep -Fq 'ADR-0004 の画像 commit 方針を置き換える' "$adr"
}
