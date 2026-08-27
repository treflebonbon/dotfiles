#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$PROJECT_ROOT/local-skills/to-pr/SKILL.md"
  HIERARCHY_REPAIR="$PROJECT_ROOT/local-skills/to-pr/references/hierarchy-repair.md"
  HIERARCHY_SCRIPT="$PROJECT_ROOT/local-skills/to-pr/scripts/repair-ticket-hierarchy.sh"
  RECONCILIATION_SCRIPT="$PROJECT_ROOT/local-skills/to-pr/scripts/reconcile-ticket-hierarchy.sh"
  FAKE_GH="$PROJECT_ROOT/tests/helpers/fake-gh-hierarchy.sh"
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/to-pr-test.XXXXXX")"
  mkdir "$TEST_TEMP/bin"
  ln -s "$FAKE_GH" "$TEST_TEMP/bin/gh"
  export PATH="$TEST_TEMP/bin:$PATH"
  export FAKE_GH_STATE="$TEST_TEMP/state.json"
  export FAKE_GH_LOG="$TEST_TEMP/gh.log"
  export FAKE_GH_REPO='example/project'
  : >"$FAKE_GH_LOG"
  unset FAKE_GH_FAIL_ADD_NUMBER FAKE_GH_FAIL_LIST FAKE_GH_FAIL_PARENT_VERIFY
  unset FAKE_GH_FAIL_READ_NUMBER FAKE_GH_FAIL_VERIFY_NUMBER
}

teardown() {
  rm -f \
    "$TEST_TEMP/bin/gh" \
    "$TEST_TEMP/state.json" \
    "$TEST_TEMP/state.json.mutation-attempted" \
    "$TEST_TEMP/reconciliation.json" \
    "$TEST_TEMP/gh.log"
  rmdir "$TEST_TEMP/bin" "$TEST_TEMP"
}

write_hierarchy_state() {
  printf '%s\n' "$1" >"$FAKE_GH_STATE"
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
  [ -x "$HIERARCHY_SCRIPT" ]
  grep -Fq '[Hierarchy Repair](references/hierarchy-repair.md)' "$SKILL"
  grep -Fq 'scripts/repair-ticket-hierarchy.sh' "$HIERARCHY_REPAIR"
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
  grep -Fq 'post-mutation verification' "$HIERARCHY_REPAIR"
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

@test "Hierarchy Repair paginates issues, mutates exactly missing siblings, and returns the verified snapshot" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"CLOSED","body":"## Parent\n\n- #1\n\n## Acceptance Criteria","parent":{"id":"I1","number":1}},
    {"id":"I3","number":3,"state":"OPEN","body":"## Parent\n\n- https://github.com/example/project/issues/1","parent":null},
    {"id":"I4","number":4,"state":"OPEN","body":"## Parent\n\n- #1","parent":null}
  ]'

  run "$HIERARCHY_SCRIPT" 4

  [ "$status" -eq 0 ]
  jq -e '
    .status == "repaired"
    and .parent == 1
    and .candidates == [2, 3, 4]
    and .added == [3, 4]
    and .failedIssues == []
    and .snapshot.parent == {number: 1, state: "OPEN"}
    and .snapshot.children == [
      {number: 2, state: "CLOSED"},
      {number: 3, state: "OPEN"},
      {number: 4, state: "OPEN"}
    ]' <<<"$output"
  grep -Fq -- '--paginate --slurp' "$FAKE_GH_LOG"
  [ "$(grep '^add:' "$FAKE_GH_LOG")" = $'add:3\nadd:4' ]
  grep -Fq 'read:2:post' "$FAKE_GH_LOG"
  grep -Fq 'read:3:post' "$FAKE_GH_LOG"
  grep -Fq 'read:4:post' "$FAKE_GH_LOG"
  grep -Fq 'subissues:1:post' "$FAKE_GH_LOG"
}

@test "Hierarchy Repair makes no mutation when a body parent is absent or ambiguous" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Acceptance Criteria\n\n- done","parent":null}
  ]'

  run "$HIERARCHY_SCRIPT" 2

  [ "$status" -eq 0 ]
  jq -e '.status == "target-none" and .parent == null and .added == []' <<<"$output"
  ! grep -q '^list$\|^add:' "$FAKE_GH_LOG"

  : >"$FAKE_GH_LOG"
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Parent\n\n- #1\n- https://github.com/example/project/issues/1","parent":null}
  ]'

  run "$HIERARCHY_SCRIPT" 2

  [ "$status" -eq 0 ]
  jq -e '.status == "failed" and .failedIssues == [2] and .added == []' <<<"$output"
  ! grep -q '^list$\|^add:' "$FAKE_GH_LOG"

  : >"$FAKE_GH_LOG"
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Parent\n\n- #1oops","parent":null}
  ]'

  run "$HIERARCHY_SCRIPT" 2

  [ "$status" -eq 0 ]
  jq -e '.status == "failed" and .failedIssues == [2] and .added == []' <<<"$output"
  ! grep -q '^list$\|^add:' "$FAKE_GH_LOG"
}

@test "Hierarchy Repair rejects a conflicting native parent before all mutations" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Parent\n\n#1","parent":null},
    {"id":"I3","number":3,"state":"OPEN","body":"## Parent\n\n#1","parent":{"id":"I9","number":9}},
    {"id":"I9","number":9,"state":"OPEN","body":"# Other parent","parent":null}
  ]'

  run "$HIERARCHY_SCRIPT" 2

  [ "$status" -eq 0 ]
  jq -e '
    .status == "failed"
    and .parent == 1
    and .candidates == [2, 3]
    and .added == []
    and .failedIssues == [3]
    and (.reason | contains("different native parent #9"))' <<<"$output"
  ! grep -q '^add:' "$FAKE_GH_LOG"
}

@test "Hierarchy Repair reports pagination failure without mutation" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Parent\n\n#1","parent":null}
  ]'
  export FAKE_GH_FAIL_LIST=1

  run "$HIERARCHY_SCRIPT" 2

  [ "$status" -eq 0 ]
  jq -e '
    .status == "failed"
    and .parent == 1
    and .added == []
    and (.reason | contains("pagination failed"))' <<<"$output"
  ! grep -q '^add:' "$FAKE_GH_LOG"
}

@test "Hierarchy Repair stops after a mutation failure and still re-reads both sides" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"CLOSED","body":"## Parent\n\n#1","parent":{"id":"I1","number":1}},
    {"id":"I3","number":3,"state":"OPEN","body":"## Parent\n\n#1","parent":null},
    {"id":"I4","number":4,"state":"OPEN","body":"## Parent\n\n#1","parent":null}
  ]'
  export FAKE_GH_FAIL_ADD_NUMBER=4

  run "$HIERARCHY_SCRIPT" 4

  [ "$status" -eq 0 ]
  jq -e '
    .status == "failed"
    and .candidates == [2, 3, 4]
    and .added == [3]
    and (.failedIssues | index(4)) != null
    and (.reason | contains("addSubIssue failed"))' <<<"$output"
  [ "$(grep '^add:' "$FAKE_GH_LOG")" = $'add:3\nadd:4' ]
  grep -Fq 'read:2:post' "$FAKE_GH_LOG"
  grep -Fq 'read:3:post' "$FAKE_GH_LOG"
  grep -Fq 'read:4:post' "$FAKE_GH_LOG"
  grep -Fq 'subissues:1:post' "$FAKE_GH_LOG"
  jq -e 'map(select(.number == 3))[0].parent.number == 1' "$FAKE_GH_STATE"
  jq -e 'map(select(.number == 4))[0].parent == null' "$FAKE_GH_STATE"

  repair_result="$output"
  jq -n --argjson hierarchy "$repair_result" \
    '{linkedIssue: 4, coveredIssues: [4], hierarchy: $hierarchy}' \
    >"$TEST_TEMP/reconciliation.json"
  run "$RECONCILIATION_SCRIPT" "$TEST_TEMP/reconciliation.json"

  [ "$status" -eq 0 ]
  jq -e '
    .state == "未実施"
    and .closeTargets == {children: [4], parent: [], all: [4]}
    and .fixes == ["Fixes #4"]
    and (.failedIssues | index(4)) != null' <<<"$output"
}

@test "Hierarchy Repair treats a post-mutation re-read failure as a failed repair" {
  write_hierarchy_state '[
    {"id":"I1","number":1,"state":"OPEN","body":"# Parent","parent":null},
    {"id":"I2","number":2,"state":"OPEN","body":"## Parent\n\n#1","parent":{"id":"I1","number":1}},
    {"id":"I3","number":3,"state":"OPEN","body":"## Parent\n\n#1","parent":null}
  ]'
  export FAKE_GH_FAIL_VERIFY_NUMBER=3

  run "$HIERARCHY_SCRIPT" 3

  [ "$status" -eq 0 ]
  jq -e '
    .status == "failed"
    and .added == [3]
    and .failedIssues == [3]
    and (.reason | contains("could not be re-read after mutation"))' <<<"$output"
  grep -Fq 'read:3:post' "$FAKE_GH_LOG"
  grep -Fq 'subissues:1:post' "$FAKE_GH_LOG"
}

@test "Parent Reconciliation suppresses early parent Fixes and emits last-child Fixes" {
  [ -x "$RECONCILIATION_SCRIPT" ]
  grep -Fq 'scripts/reconcile-ticket-hierarchy.sh' "$SKILL"

  printf '%s\n' '{
    "linkedIssue": 4,
    "coveredIssues": [4],
    "hierarchy": {
      "status": "repaired",
      "reason": "verified",
      "snapshot": {
        "parent": {"number": 1, "state": "OPEN"},
        "children": [
          {"number": 2, "state": "CLOSED"},
          {"number": 3, "state": "OPEN"},
          {"number": 4, "state": "OPEN"}
        ]
      }
    }
  }' >"$TEST_TEMP/reconciliation.json"

  run "$RECONCILIATION_SCRIPT" "$TEST_TEMP/reconciliation.json"

  [ "$status" -eq 0 ]
  jq -e '
    .state == "未実施"
    and .uncoveredIssues == [3]
    and .closeTargets == {children: [4], parent: [], all: [4]}
    and .fixes == ["Fixes #4"]' <<<"$output"

  jq '.hierarchy.snapshot.children |= map(if .number == 3 then .state = "CLOSED" else . end)' \
    "$TEST_TEMP/reconciliation.json" >"$TEST_TEMP/reconciliation-next.json"
  mv "$TEST_TEMP/reconciliation-next.json" "$TEST_TEMP/reconciliation.json"

  run "$RECONCILIATION_SCRIPT" "$TEST_TEMP/reconciliation.json"

  [ "$status" -eq 0 ]
  jq -e '
    .state == "確認済み"
    and .uncoveredIssues == []
    and .closeTargets == {children: [4], parent: [1], all: [4, 1]}
    and .fixes == ["Fixes #4", "Fixes #1"]' <<<"$output"
}

@test "Parent Reconciliation rejects malformed snapshots instead of generating parent Fixes" {
  local invalid_filter
  local -a invalid_filters=(
    '.hierarchy.snapshot.children[0].state = "UNKNOWN"'
    '.hierarchy.snapshot.children[0].number = 0'
    '.hierarchy.snapshot.children[0].number = 4'
    '.hierarchy.snapshot.children |= map(select(.number != 4))'
  )

  for invalid_filter in "${invalid_filters[@]}"; do
    jq -n '{
      linkedIssue: 4,
      coveredIssues: [4],
      hierarchy: {
        status: "ready",
        reason: "verified",
        snapshot: {
          parent: {number: 1, state: "OPEN"},
          children: [
            {number: 3, state: "CLOSED"},
            {number: 4, state: "OPEN"}
          ]
        }
      }
    }' >"$TEST_TEMP/reconciliation.json"

    # Apply the invalid transformation after constructing the valid baseline.
    jq "$invalid_filter" "$TEST_TEMP/reconciliation.json" \
      >"$TEST_TEMP/reconciliation-next.json"
    mv "$TEST_TEMP/reconciliation-next.json" "$TEST_TEMP/reconciliation.json"

    run "$RECONCILIATION_SCRIPT" "$TEST_TEMP/reconciliation.json"

    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid verified hierarchy snapshot'* ]]
  done
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
