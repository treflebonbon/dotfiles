#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$PROJECT_ROOT/local-skills/to-pr/SKILL.md"
  HIERARCHY_REPAIR="$PROJECT_ROOT/local-skills/to-pr/references/hierarchy-repair.md"
}

@test "to-pr can be invoked by the model after implementation" {
  ! grep -q '^disable-model-invocation:' "$SKILL"
  grep -Fq 'explicitly authorized AFK/autonomous completion' "$SKILL"
  grep -Fq 'otherwise do not invoke it automatically' "$SKILL"
}

@test "Project workflow preauthorizes routine GitHub writes across runtimes" {
  local instructions
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'ユーザーが結果を依頼し内容が確定した後は、非破壊な GitHub 定型書込みは二重確認しない' "$instructions"
    grep -Fq '本文で宣言済みの missing native edge の追加' "$instructions"
    ! grep -Fq 'push / PR 作成の確認は変更しない' "$instructions"
  done

  grep -Fq '内容確定後の非破壊な GitHub 定型書込みは二重確認しない' \
    "$PROJECT_ROOT/runtime/skill-harness.md"
  ! grep -Fq 'push/PR 作成自体の確認は変更しない' \
    "$PROJECT_ROOT/runtime/skill-harness.md"

  local adr="$PROJECT_ROOT/docs/adr/0030-preauthorize-routine-github-writes.md"
  [ -f "$adr" ]
  grep -Fq 'status: accepted' "$adr"
  grep -Fq 'ADR-0019 Decision 7' "$adr"
}

@test "to-pr reconciles only a native direct parent" {
  grep -Fq 'gh issue view <issue> --json number,state,body,parent' "$SKILL"
  grep -Fq 'gh issue view <parent> --json number,state,body,subIssues,subIssuesSummary' "$SKILL"
  grep -Fq 'GitHub native sub-issues are the source of truth' "$SKILL"
  grep -Fq 'body'\''s `## Parent`' "$SKILL"
  grep -Fq 'Do not recurse to a grandparent' "$SKILL"
  grep -Fq 'freeze this Ticket Hierarchy until merge' "$SKILL"
}

@test "to-pr repairs every body-declared direct sibling before reconciliation" {
  [ -f "$HIERARCHY_REPAIR" ]
  grep -Fq '[Hierarchy Repair](references/hierarchy-repair.md)' "$SKILL"
  grep -Fq 'gh api graphql --paginate --slurp' "$HIERARCHY_REPAIR"
  grep -Fq 'issues(first: 100, after: $endCursor)' "$HIERARCHY_REPAIR"
  grep -Fq 'excludes pull requests' "$HIERARCHY_REPAIR"
  grep -Fq 'direct-child candidates' "$HIERARCHY_REPAIR"
  grep -Fq 'current linked issue' "$HIERARCHY_REPAIR"
  grep -Fq 'every missing edge' "$HIERARCHY_REPAIR"
  grep -Fq 'replaceParent: false' "$HIERARCHY_REPAIR"
  grep -Fq 'before Parent Reconciliation' "$HIERARCHY_REPAIR"
}

@test "Hierarchy Repair verifies both sides and fails safely" {
  grep -Fq 'before the first mutation' "$HIERARCHY_REPAIR"
  grep -Fq 'different native parent' "$HIERARCHY_REPAIR"
  grep -Fq 'abort the whole repair before mutation' "$HIERARCHY_REPAIR"
  grep -Fq 'gh issue view <candidate> --json number,state,body,parent' "$HIERARCHY_REPAIR"
  grep -Fq 'gh issue view <parent> --json number,state,body,subIssues,subIssuesSummary' "$HIERARCHY_REPAIR"
  grep -Fq 'stop adding edges' "$HIERARCHY_REPAIR"
  grep -Fq 'partially successful' "$HIERARCHY_REPAIR"
  grep -Fq 'Parent Reconciliation as `未実施`' "$HIERARCHY_REPAIR"
  grep -Fq 'failed issue numbers and reasons' "$HIERARCHY_REPAIR"
  grep -Fq 'omit the parent `Fixes`' "$HIERARCHY_REPAIR"
  grep -Fq 'continue creating the PR' "$HIERARCHY_REPAIR"

  grep -Fq 'If Hierarchy Repair fails' "$SKILL"
  grep -Fq 'neither a native parent nor a body `## Parent` declaration' "$SKILL"
}

@test "to-pr authorization covers only declared missing hierarchy edges" {
  local authorization_section
  authorization_section="$(sed -n '/^## 6\. Open the PR/,/^## 7\. Attach Playwright evidence/p' "$SKILL" | tr '\n' ' ' | tr -s ' ')"

  [[ "$authorization_section" == *'adding missing native sub-issue edges already declared in issue bodies'* ]]
  [[ "$authorization_section" == *'This authorization covers missing edges only'* ]]
  [[ "$authorization_section" == *'issue bodies, state, labels, assignees, or existing parent relationships'* ]]
  grep -Fq 'replaceParent: false' "$HIERARCHY_REPAIR"
  ! grep -Fq 'replaceParent: true' "$HIERARCHY_REPAIR"
  ! grep -Eq 'removeSubIssue|delete.*/sub_issue' "$HIERARCHY_REPAIR"
}

@test "project contract documents Hierarchy Repair and its safety conditions" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local context="$PROJECT_ROOT/CONTEXT.md"
  local adr="$PROJECT_ROOT/docs/adr/0027-to-pr-parent-reconciliation.md"

  grep -Fq 'Hierarchy Repair' "$runtime"
  grep -Fq 'missing edge の追加だけ' "$runtime"
  grep -Fq '**Hierarchy Repair**' "$context"
  grep -Fq '全 direct-child candidates' "$adr"
  grep -Fq 'pagination' "$adr"
  grep -Fq 'PR を除外' "$adr"
  grep -Fq '両側から再検証' "$adr"
  grep -Fq '既存 parent の削除・reparent' "$adr"
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

@test "to-pr preauthorizes publication and documents reconciliation ownership" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local context="$PROJECT_ROOT/CONTEXT.md"
  local adr="$PROJECT_ROOT/docs/adr/0027-to-pr-parent-reconciliation.md"
  local publication_section
  publication_section="$(sed -n '/^## 6\. Open the PR/,/^## 7\. Attach Playwright evidence/p' "$SKILL" | tr '\n' ' ' | tr -s ' ')"

  grep -Fq 'Invocation of this skill is authorization for the routine publication actions' "$SKILL"
  grep -Fq 'git-push-topic' "$SKILL"
  [[ "$publication_section" == *'Do not ask for a second confirmation solely because these actions are outward-facing'* ]]
  ! grep -Fq 'Ask once for explicit confirmation' "$SKILL"
  ! grep -Fq 'After confirmation' "$SKILL"
  grep -Fq 'exact list of child and parent issues that will close on' "$SKILL"
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

@test "to-pr publishes images through an authenticated Managed Playwright Chrome profile" {
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"
  local adr="$PROJECT_ROOT/docs/adr/0026-attach-playwright-evidence-to-pr.md"
  local attachment_section
  attachment_section="$(sed -n '/^## 7\. Attach Playwright evidence/,/^## Out of scope/p' "$SKILL" | tr '\n' ' ' | tr -s ' ')"

  [[ "$attachment_section" == *'authenticated GitHub session'* ]]
  grep -Fq 'anonymized URL' "$SKILL"
  grep -Fq 'gh pr edit --body-file' "$SKILL"
  [[ "$attachment_section" == *'On WSL2, use Managed Playwright Chrome'* ]]
  [[ "$attachment_section" == *'only when its dedicated profile already has an authenticated GitHub session'* ]]
  [[ "$attachment_section" == *"Never substitute the user's normal Windows Chrome profile"* ]]
  [[ "$attachment_section" == *'Existing authentication permits this PR-evidence upload only'* ]]
  [[ "$attachment_section" == *'If no authenticated browser is available'* ]]
  [[ "$attachment_section" == *'do not retry by logging in'* ]]
  [[ "$attachment_section" == *'手動添付待ち'* ]]
  [[ "$attachment_section" == *"bundle's absolute path and a file list"* ]]
  ! grep -Fq '.github/pr-assets' "$SKILL"

  grep -Fq 'GitHub の PR 添付' "$runtime"
  grep -Fq 'Managed Playwright Chrome の専用 profile' "$runtime"
  grep -Fq '手動添付待ち' "$runtime"
  ! grep -Fq '.github/pr-assets' "$runtime"

  [ -f "$adr" ]
  grep -Fq 'ADR-0004 の画像 commit 方針を置き換える' "$adr"
}
