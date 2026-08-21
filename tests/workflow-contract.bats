#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
}

@test "grilling uses frontier rounds and waits for human decisions" {
  local skill="$PROJECT_ROOT/local-skills/ui-grill-with-docs/SKILL.md"

  grep -Fq 'frontier' "$RUNTIME"
  grep -Fq '各 round' "$RUNTIME"
  grep -Fq '人間の回答を待つ' "$RUNTIME"
  grep -Fq 'frontier round' "$skill"
  ! grep -Fq 'one-question-at-a-time' "$skill"
  ! grep -Fq '一問一答' "$skill"
}

@test "phase boundaries use the official five-option order" {
  grep -Fq 'Continue → /clear → /handoff → Subagent → /compact' "$RUNTIME"
  grep -Fq '同じ harness / directory' "$RUNTIME"
  grep -Fq 'portability' "$RUNTIME"
  grep -Fq '150k' "$RUNTIME"
  grep -Fq 'Continue → /clear → /handoff → Subagent → /compact' "$PROJECT_ROOT/CONTEXT.md"
}

@test "Builder-Evaluator keeps ticket crossing in one worktree and branch" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq '同じ worktree/branch' "$instructions"
    grep -Fq '/compact' "$instructions"
    grep -Fq '/handoff' "$instructions"
  done

  grep -Fq '同一 worktree/branch' "$RUNTIME"
  grep -Fq 'ticket をまたいで' "$RUNTIME"
}

@test "instruction layers guard model-invoked external writes, secrets, and permissions" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'model-invoked' "$instructions"
    grep -Fq '外部書込み' "$instructions"
    grep -Fq '機密情報' "$instructions"
    grep -Fq '権限' "$instructions"
  done

  grep -Fq 'model-invoked' "$RUNTIME"
  grep -Fq '外部書込み' "$RUNTIME"
}

@test "prototype contract is a self-contained HTML primary source" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md" "$RUNTIME"; do
    grep -Fq 'single self-contained HTML' "$instructions"
    grep -Fq 'build / server 不要' "$instructions"
    grep -Fq 'primary source' "$instructions"
    grep -Fq 'throwaway branch' "$instructions"
  done
}

@test "AGENTS and CLAUDE remain separate while sharing workflow contract" {
  [ -f "$PROJECT_ROOT/AGENTS.md" ]
  [ -f "$PROJECT_ROOT/CLAUDE.md" ]
  ! cmp -s "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"

  grep -Fq 'AGENTS.md' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq 'CLAUDE.md' "$PROJECT_ROOT/AGENTS.md"
}

@test "workflow migration ADR supersedes old exclusions and pins" {
  local adr="$PROJECT_ROOT/docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md"

  [ -f "$adr" ]
  grep -Fq 'status: accepted' "$adr"
  grep -Fq 'ADR-0022' "$adr"
  grep -Fq 'ADR-0037' "$adr"
  grep -Fq 'supersede' "$adr"
  grep -Fq 'grill-me' "$adr"
  grep -Fq 'teach' "$adr"
  grep -Fq 'writing-great-skills' "$adr"
  grep -Fq 'v1.2.3' "$adr"
}
