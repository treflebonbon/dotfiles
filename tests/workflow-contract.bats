#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
}

@test "agent instructions separate task worktree edits from live chezmoi deployment" {
  local architecture="$PROJECT_ROOT/docs/architecture.md"

  local instructions
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'validated task worktree 内の source を編集する' "$instructions"
    grep -Fq '`chezmoi source-path` が示す live source' "$instructions"
    grep -Fq '未 merge の task worktree から `chezmoi apply` しない' "$instructions"
    grep -Fq '受入後に live source で `chezmoi apply`' "$instructions"
  done

  grep -Fq 'validated task worktree 内の source で行う' "$architecture"
  grep -Fq '`chezmoi source-path` が示す live source' "$architecture"
  grep -Fq '未 merge の task worktree から `chezmoi apply` しない' "$architecture"
}

@test "grilling uses frontier rounds and waits for human decisions" {
  local skill="$PROJECT_ROOT/local-skills/ui-grill-with-docs/SKILL.md"

  grep -Fq 'frontier round でまとめて提示し、各質問へ推奨を添え' "$RUNTIME"
  grep -Fq '各 round の人間の回答を待ち' "$RUNTIME"
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
  grep -Fq '同じ worktree/branch' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '/compact' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '/handoff' "$PROJECT_ROOT/CLAUDE.md"

  grep -Fq '同一 worktree/branch では ticket をまたいで' "$RUNTIME"
  grep -Fq 'ticket 境界で relevant context が同じ harness / directory にあるなら `/compact`' "$RUNTIME"
  grep -Fq '移植性が必要な場合だけ `/handoff`' "$RUNTIME"
  grep -Fq '`tdd` の red-green、commit、`code-review`、full verification の境界' "$RUNTIME"
}

@test "local workflow overrides preserve triage, review base, and Review Round authority" {
  grep -Fq '`triage` は推薦根拠の read-only 検証' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq 'standalone で base が不明な場合は確認する' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '`gh-review-thread` に統一する' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '1つの Review Round' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '`git-push-topic`' "$PROJECT_ROOT/CLAUDE.md"

  grep -Fq '`triage` は推薦根拠を得る read-only 検証' "$RUNTIME"
  grep -Fq 'standalone で fixed point が不明な場合だけ質問する' "$RUNTIME"
  grep -Fq '専用 CLI `gh-review-thread` に統一する' "$RUNTIME"
  grep -Fq '選択 thread 群の Review Round' "$RUNTIME"
  grep -Fq '`git-push-topic`' "$RUNTIME"
}

@test "empirical prompt tuning does not claim strict convergence without usage metrics" {
  local instructions

  grep -Fq '外部 skill を実行・評価するときのローカル上書き' "$PROJECT_ROOT/AGENTS.md"
  for instructions in "$PROJECT_ROOT/CLAUDE.md" "$RUNTIME"; do
    grep -Fq '`tool_uses` または `duration_ms` を取得できない round' "$instructions"
    grep -Fq 'strict convergence の判定に含めない' "$instructions"
    grep -Fq '`qualitative plateau; quantitative convergence unverified`' "$instructions"
    grep -Fq '明示的な `resource cutoff`' "$instructions"
  done
}

@test "instruction layers guard model-invoked external writes, secrets, and permissions" {
  grep -Fq 'model-invoked discipline' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '外部書込みは親 Contract' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '機密情報・credential・CI secret' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '読み出し、出力、commit' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '無断変更' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq 'permission bypass' "$PROJECT_ROOT/CLAUDE.md"

  grep -Fq 'model-invoked discipline' "$RUNTIME"
  grep -Fq '外部書込み（Issue / PR / shared service など）は親の Contract' "$RUNTIME"
  grep -Fq '機密情報・credential・CI secret' "$RUNTIME"
  grep -Fq '読み出し、出力、commit' "$RUNTIME"
  grep -Fq '無断変更' "$RUNTIME"
  grep -Fq 'permission bypass' "$RUNTIME"
}

@test "prototype contract is a self-contained HTML primary source" {
  for instructions in "$PROJECT_ROOT/CLAUDE.md" "$RUNTIME"; do
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

  grep -Fq 'Matt Pocock skill の workflow / safety contract' "$PROJECT_ROOT/AGENTS.md"
  grep -Fq '`runtime/skill-harness.md`' "$PROJECT_ROOT/AGENTS.md"
  ! grep -Fq '## Matt Pocock workflow contract' "$PROJECT_ROOT/AGENTS.md"
  ! grep -Fq 'model-invoked discipline' "$PROJECT_ROOT/AGENTS.md"
  ! grep -Fq 'single self-contained HTML' "$PROJECT_ROOT/AGENTS.md"

  grep -Fq 'Matt Pocock workflow contract' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '共有する workflow / safety contract は整合させる' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '**Instruction ownership**' "$RUNTIME"
}

@test "managed workflow revision uses explicit invocation, round separators, and setup pointers" {
  grep -Fq '複数質問の間を horizontal rule (`---`) で区切る' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq 'cross-skill 呼出しは Skill tool と skill 名を明示する' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '別の user-invoked skill から自動実行せず' "$PROJECT_ROOT/CLAUDE.md"

  grep -Fq '6654f6b60cd9d5be8b54c6fafe44346dabeb3b76' "$RUNTIME"
  grep -Fq '複数質問の間を horizontal rule (`---`) で区切る' "$RUNTIME"
  grep -Fq 'Skill tool と skill 名を明示する' "$RUNTIME"
  grep -Fq '`setup-matt-pocock-skills` を自動実行せず' "$RUNTIME"
}

@test "AGENTS routes browser work by interaction surface" {
  local instructions="$PROJECT_ROOT/AGENTS.md"

  grep -Fq 'Orca 内蔵 page は `orca-cli`' "$instructions"
  grep -Fq '外部 Web page の自動操作は `playwright-cli` または CDP' "$instructions"
  grep -Fq '外部 browser window や native app の OS/window-level 操作は `computer-use`' "$instructions"
  grep -Fq 'Chrome MV3 拡張は persistent Chromium context' "$instructions"
  grep -Fq '要素指差しフィードバック機能' "$instructions"
}

@test "to-worktree is the non-Orca entry and fails closed inside an Orca primary checkout" {
  local skill="$PROJECT_ROOT/local-skills/to-worktree/SKILL.md"
  local orca_gate_line unknown_runtime_gate_line git_inspection_line

  grep -Fq 'Use this **Worktree Entry Point** outside Orca' "$skill"
  orca_gate_line="$(grep -nF 'Before running any Git command, use runtime-provided session context' "$skill" | cut -d: -f1)"
  unknown_runtime_gate_line="$(grep -nF 'If runtime self-identification is unavailable' "$skill" | cut -d: -f1)"
  git_inspection_line="$(grep -nF "Inspect the target repository's physical top level" "$skill" | cut -d: -f1)"
  [ -n "$orca_gate_line" ]
  [ -n "$unknown_runtime_gate_line" ]
  [ -n "$git_inspection_line" ]
  [ "$orca_gate_line" -lt "$git_inspection_line" ]
  [ "$unknown_runtime_gate_line" -lt "$git_inspection_line" ]
  grep -Fq 'stop before repository inspection' "$skill"
  grep -Fq '**Existing linked worktree**' "$skill"
  grep -Fq '**Orca guard**' "$skill"
  grep -Fq 'runtime self-identification' "$skill"
  grep -Fq 'Orca native worktree' "$skill"
  grep -Fq 'launching its built-in' "$skill"
  grep -Fq 'agent from the Agent Picker' "$skill"
  grep -Fq "Orca owns that agent's permission mode" "$skill"
  grep -Fq 'new agent session' "$skill"
  grep -Fq 'Do not invoke Orca CLI or raw Git' "$skill"
  grep -Fq 'Do not probe `ORCA_*` environment variables' "$skill"
  ! grep -Fq '`orca-cli` skill' "$skill"
  ! grep -Fq 'creation and full handoff through Orca' "$skill"
  grep -Fq '**Codex Desktop**' "$skill"
  grep -Fq '**Claude Code**' "$skill"
  grep -Fq '**raw Codex CLI**' "$skill"
  grep -Fq '`EnterWorktree`' "$skill"
  grep -Fq '`codex-worktree`' "$skill"
  grep -Fq 'fresh session' "$skill"
  grep -Fq 'do not relaunch the agent through `codex-orca` or `codex-worktree`' "$skill"
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

@test "to-worktree stops when the exact raw Codex creation command is rejected" {
  local skill="$PROJECT_ROOT/local-skills/to-worktree/SKILL.md"

  grep -Fq 'runtime rejects this exact command, treat the branch as terminally blocked' "$skill"
  grep -Fq 'overrides any general suggestion to retry with alternate Git syntax' "$skill"
  grep -Fq 'no further worktree command, file write, or workflow phase is authorized' "$skill"
}

@test "instruction layers align Worktree Entry Point ownership without merging runtime guidance" {
  local agents="$PROJECT_ROOT/AGENTS.md"

  grep -Fq 'Worktree Entry Point は validated task worktree' "$agents"
  grep -Fq 'Orca native worktree' "$agents"
  grep -Fq 'Agent Picker' "$agents"
  grep -Fq 'current checkout が linked worktree か read-only に検証' "$agents"
  grep -Fq 'primary checkout' "$agents"
  grep -Fq '新しい agent session' "$agents"
  grep -Fq '非 Orca runtime では `/to-worktree`' "$agents"
  grep -Fq '同じ checkout' "$agents"

  for instructions in "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'Worktree Entry Point は共通の入口契約' "$instructions"
    grep -Fq 'Orca では agent session を始める前に Orca native worktree' "$instructions"
    grep -Fq 'Agent Picker から built-in agent' "$instructions"
    grep -Fq '自律 workflow は shipped Yolo' "$instructions"
    grep -Fq 'Manual と Orca Source Control' "$instructions"
    grep -Fq 'Orca native Codex は `codex-orca` / `codex-worktree` を使わない' "$instructions"
    grep -Fq 'OS sandbox ではない' "$instructions"
    grep -Fq '信頼できる repository / host' "$instructions"
    grep -Fq '非 Orca runtime では `/to-worktree`' "$instructions"
    grep -Fq 'local file の変更につながる engineering flow' "$instructions"
    grep -Fq 'primary checkout' "$instructions"
    grep -Fq 'read-only' "$instructions"
    grep -Fq '新しい agent session' "$instructions"
    grep -Fq '同じ checkout' "$instructions"
    ! grep -Fq '`orca-cli` の version-matched native create / full handoff' "$instructions"
  done

  grep -Fq 'runtime 自己認識' "$RUNTIME"
  grep -Fq '`ORCA_*` environment の汎用判定' "$RUNTIME"
  grep -Fq 'Orca primary checkout' "$RUNTIME"
  grep -Fq 'Orca CLI や raw Git を呼ばず' "$RUNTIME"
  grep -Fq 'Worktree Entry Point（Orca native または `to-worktree`）→ `grill-with-docs`' "$RUNTIME"
  grep -Fq '**Orca native agent launch**' "$RUNTIME"
  grep -Fq '**Codex Runtime Adapter（raw CLI only）**' "$RUNTIME"
  grep -Fq 'Orca native session の entry / activation には使わない' "$RUNTIME"
  grep -Fq '`EnterWorktree`' "$PROJECT_ROOT/CLAUDE.md"
  ! cmp -s "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"
}

@test "ADR-0046 uses Orca built-in Codex launch and keeps the adapter outside Orca" {
  local adr="$PROJECT_ROOT/docs/adr/0046-separate-orca-native-worktree-entry.md"

  grep -Fq 'status: accepted' "$adr"
  grep -Fq 'Agent Picker からの built-in agent 起動' "$adr"
  grep -Fq 'Orca shipped Yolo' "$adr"
  grep -Fq '`codex-orca` / `codex-worktree` や repository-owned permission override を挟まない' "$adr"
  grep -Fq 'filesystem / network の security boundary ではない' "$adr"
  grep -Fq 'Agent Permissions を Manual' "$adr"
  grep -Fq 'Orca Source Control で stage / commit / push' "$adr"
  grep -Fq 'raw Codex CLI の `codex-worktree` Worktree Activation' "$adr"
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
