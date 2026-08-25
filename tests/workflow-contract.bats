#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
}

@test "grilling uses frontier rounds and waits for human decisions" {
  local skill="$PROJECT_ROOT/local-skills/ui-grill-with-docs/SKILL.md"

  grep -Fq 'frontier round でまとめて提示し、各質問へ推奨を添え、各 round の人間の回答を待つ' "$RUNTIME"
  grep -Fq '未回答の decision を推測して先へ進まない' "$RUNTIME"
  grep -Fq 'In each round, ask every decision whose prerequisites are' "$skill"
  grep -Fq "wait for the human's answers" "$skill"
  ! grep -Fq 'one-question-at-a-time' "$skill"
  ! grep -Fq '一問一答' "$skill"
}

@test "phase boundaries use the official five-option order" {
  grep -Fq 'Continue → /clear → /handoff → Subagent → /compact' "$RUNTIME"
  grep -Fq '新しい harness / directory / repo / colleague へ portability が必要な場合だけ `/handoff`' "$RUNTIME"
  grep -Fq '同じ harness / directory の relevant context を保ったまま要約する場合は `/compact`' "$RUNTIME"
  grep -Fq 'smart zone（目安 ~150k tokens）に収まるなら `Continue`' "$RUNTIME"
  grep -Fq 'Continue → /clear → /handoff → Subagent → /compact' "$PROJECT_ROOT/CONTEXT.md"
}

@test "Builder-Evaluator keeps ticket crossing in one worktree and branch" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq '同じ worktree/branch' "$instructions"
    grep -Fq '/compact' "$instructions"
    grep -Fq '/handoff' "$instructions"
  done

  grep -Fq '同一 worktree/branch では ticket をまたいで' "$RUNTIME"
  grep -Fq 'ticket 境界で relevant context が同じ harness / directory にあるなら `/compact`' "$RUNTIME"
  grep -Fq '移植性が必要な場合だけ `/handoff`' "$RUNTIME"
  grep -Fq '`tdd` の red-green、commit、`code-review`、full verification の境界' "$RUNTIME"
}

@test "instruction layers guard model-invoked external writes, secrets, and permissions" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'model-invoked discipline' "$instructions"
    grep -Fq '外部書込みは親 Contract' "$instructions"
    grep -Fq '機密情報・credential・CI secret' "$instructions"
    grep -Fq '読み出し、出力、commit' "$instructions"
    grep -Fq '無断変更' "$instructions"
    grep -Fq 'permission bypass' "$instructions"
  done

  grep -Fq 'model-invoked discipline' "$RUNTIME"
  grep -Fq '外部書込み（Issue / PR / shared service など）は親の Contract' "$RUNTIME"
  grep -Fq '機密情報・credential・CI secret' "$RUNTIME"
  grep -Fq '読み出し、出力、commit' "$RUNTIME"
  grep -Fq '無断変更' "$RUNTIME"
  grep -Fq 'permission bypass' "$RUNTIME"
}

@test "prototype contract is a self-contained HTML primary source" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md" "$RUNTIME"; do
    grep -Fq 'single self-contained HTML' "$instructions"
    grep -Fq 'build / server 不要' "$instructions"
    grep -Fq 'pure logic' "$instructions"
    grep -Fq 'free-play' "$instructions"
    grep -Fq 'guided walkthroughs' "$instructions"
    grep -Fq '全 state 表示' "$instructions"
    grep -Fq 'primary source' "$instructions"
    grep -Fq 'throwaway branch' "$instructions"
  done
}

@test "AGENTS and CLAUDE remain separate while sharing workflow contract" {
  [ -f "$PROJECT_ROOT/AGENTS.md" ]
  [ -f "$PROJECT_ROOT/CLAUDE.md" ]
  ! cmp -s "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"

  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'v1.2.3 workflow contract' "$instructions"
    grep -Fq '共有する workflow / safety contract は整合させる' "$instructions"
  done
}

@test "to-worktree routes representative runtime owners through one Worktree Entry Point" {
  local skill="$PROJECT_ROOT/local-skills/to-worktree/SKILL.md"

  grep -Fq 'Worktree Entry Point' "$skill"
  grep -Fq '**Existing linked worktree**' "$skill"
  grep -Fq '**Orca**' "$skill"
  grep -Fq '`orca-cli` skill' "$skill"
  grep -Fq 'version-matched' "$skill"
  grep -Fq 'native worktree' "$skill"
  grep -Fq 'creation and full handoff' "$skill"
  grep -Fq 'stop the original session' "$skill"
  grep -Fq '**Codex Desktop**' "$skill"
  grep -Fq '**Claude Code**' "$skill"
  grep -Fq '**raw Codex CLI**' "$skill"
  grep -Fq '`EnterWorktree`' "$skill"
  grep -Fq '`codex-worktree`' "$skill"
  grep -Fq 'fresh session' "$skill"
}

@test "to-worktree preserves the caller checkout and never reuses another worktree" {
  local skill="$PROJECT_ROOT/local-skills/to-worktree/SKILL.md"

  grep -Fq 'caller `HEAD`' "$skill"
  grep -Fq 'Do not fetch' "$skill"
  grep -Fq 'Leave every parent change untouched' "$skill"
  grep -Fq 'Reuse only the current linked worktree' "$skill"
  grep -Fq 'same-topic worktree at any other path is a conflict' "$skill"
}

@test "to-worktree anchors raw Codex CLI creation to the repository physical top level" {
  local skill="$PROJECT_ROOT/local-skills/to-worktree/SKILL.md"

  grep -Fq 'git -C <physical-top-level> worktree add <physical-top-level>/.worktrees/<topic> -b <type>/<topic> HEAD' "$skill"
  grep -Fq 'same absolute physical top level for `-C` and the destination' "$skill"
  grep -Fq '同じ absolute physical top level を `git -C` と destination の両方に使う1 commandの成功を完了条件' "$RUNTIME"
}

@test "instruction layers align Worktree Entry Point ownership without merging runtime guidance" {
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'Worktree Entry Point' "$instructions"
    grep -Fq '同じ checkout' "$instructions"
    grep -Fq '`orca-cli` の version-matched native create / full handoff' "$instructions"
    grep -Fq '元セッションを停止' "$instructions"
  done

  grep -Fq 'Codex Desktop' "$PROJECT_ROOT/AGENTS.md"
  grep -Fq 'raw Codex CLI' "$PROJECT_ROOT/AGENTS.md"
  grep -Fq '`EnterWorktree`' "$PROJECT_ROOT/CLAUDE.md"
  ! cmp -s "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"
}

@test "workflow migration ADR supersedes old exclusions and pins" {
  local adr="$PROJECT_ROOT/docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md"

  [ -f "$adr" ]
  grep -Fq 'status: accepted' "$adr"
  grep -Fq '旧一問一答・120k smart-zone・旧 phase boundary' "$adr"
  grep -Fq 'ADR-0022 の `grill-me` / `teach` 非導入判断' "$adr"
  grep -Fq 'ADR-0037 の旧20-skill pin 据え置き理由' "$adr"
  grep -Fq 'supersede' "$adr"
  grep -Fq 'full set の配備判断自体は ADR-0040 が正本' "$adr"
}
