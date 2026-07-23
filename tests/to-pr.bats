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

@test "to-pr reconciles only a native direct parent" {
  grep -Fq 'gh issue view <issue> --json number,state,body,parent' "$SKILL"
  grep -Fq 'gh issue view <parent> --json number,state,body,subIssues,subIssuesSummary' "$SKILL"
  grep -Fq 'GitHub native sub-issues are the source of truth' "$SKILL"
  grep -Fq 'body'\''s `## Parent`' "$SKILL"
  grep -Fq 'Do not recurse to a grandparent' "$SKILL"
  grep -Fq 'freeze this Ticket Hierarchy until merge' "$SKILL"
}

@test "to-pr closes a direct parent only with complete Ticket Coverage" {
  grep -Fq 'gh issue view <child> --json number,state,body' "$SKILL"
  grep -Fq '**Ticket Coverage**' "$SKILL"
  grep -Fq 'appears in the Contract and has a row in the Verification Matrix' "$SKILL"
  grep -Fq 'not affect Ticket Coverage' "$SKILL"
  grep -Fq '## Parent Reconciliation' "$SKILL"
  grep -Fq '`確認済み`, `未実施`, or `対象なし`' "$SKILL"
  grep -Fq 'every open, covered direct child' "$SKILL"
  grep -Fq 'one more for the direct parent' "$SKILL"
  grep -Fq 'Omit already-closed' "$SKILL"
  grep -Fq 'omit the parent `Fixes` line' "$SKILL"
  grep -Fq 'continue creating the PR' "$SKILL"
  grep -Fq 'If there is no linked issue, record `対象なし` and omit all `Fixes` lines' "$SKILL"
  grep -Fq 'preserve the ordinary `Fixes #N` line for the linked issue' "$SKILL"
}

@test "to-pr confirms close targets and documents reconciliation ownership" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local context="$PROJECT_ROOT/CONTEXT.md"
  local adr="$PROJECT_ROOT/docs/adr/0027-to-pr-parent-reconciliation.md"

  grep -Fq 'the exact list of child and parent issues that will close on merge' "$SKILL"
  grep -Fq 'Keep state labels unchanged' "$SKILL"
  grep -Fq 'Post-merge issue mutation or automation' "$SKILL"
  grep -Fq 'Repeat the Parent Reconciliation state, reason, and close targets in the completion report' "$SKILL"
  ! grep -Fq 'closing issues, verdict gates' "$SKILL"

  grep -Fq 'Parent Reconciliation' "$runtime"
  grep -Fq 'GitHub native subissues' "$runtime"
  grep -Fq '親の `Fixes` を省略しても PR 作成は継続' "$runtime"

  grep -Fq '**Ticket Hierarchy**' "$context"
  grep -Fq '**Ticket Coverage**' "$context"
  grep -Fq '**Parent Reconciliation**' "$context"

  [ -f "$adr" ]
  grep -Fq 'status: accepted' "$adr"
  grep -Fq '直接の親1階層' "$adr"
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
  attachment_section="$(sed -n '/^## 7\. Attach Playwright evidence/,/^## Out of scope/p' "$SKILL" | tr '\n' ' ' | tr -s ' ')"

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
