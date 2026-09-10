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

@test "native worktree guidance replaces the retired entry skill" {
  [ ! -e "$PROJECT_ROOT/local-skills/to-worktree" ]
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'runtime/skill-harness.md' "$instructions"
    run grep -Fq '/to-worktree' "$instructions"
    [ "$status" -eq 1 ]
  done
  run grep -Fq '/to-worktree' "$RUNTIME"
  [ "$status" -eq 1 ]
  grep -Fq '### Worktree の開始と復旧' "$RUNTIME"
  grep -Fq '**owner 側でも検証不能**' "$RUNTIME"
  grep -Fq '**owner 側では有効、子から参照不能**' "$RUNTIME"
  grep -Fq '子が自分の環境で再検証に成功してから' "$RUNTIME"
  grep -Fq 'Orca native Codex は `codex-orca` / `codex-worktree` を使わない' "$RUNTIME"
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
