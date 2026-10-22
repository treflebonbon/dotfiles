#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
  GLOBAL_CLAUDE="$PROJECT_ROOT/private_dot_claude/CLAUDE.md"
  GLOBAL_CODEX="$PROJECT_ROOT/private_dot_config/codex/AGENTS.md"
}

@test "agent instructions separate task worktree edits from live chezmoi deployment" {
  local architecture="$PROJECT_ROOT/docs/architecture.md"

  local instructions
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'validated task worktree 内の source を編集する' "$instructions"
    grep -Fq '`chezmoi source-path` が示す live source' "$instructions"
    grep -Fq '未 merge の task worktree から `chezmoi apply` しない' "$instructions"
    grep -Fq '受入後に live source で `chezmoi diff` を確認し、変更した対象を `chezmoi apply <配備先パス>`' "$instructions"
  done

  grep -Fq 'validated task worktree 内の source で行う' "$architecture"
  grep -Fq '`chezmoi source-path` が示す live source' "$architecture"
  grep -Fq '未 merge の task worktree から `chezmoi apply` しない' "$architecture"
}

@test "path-scoped deploys point to the run-script and Codex sync caveats" {
  local architecture="$PROJECT_ROOT/docs/architecture.md"

  local instructions
  for instructions in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq '`docs/architecture.md` の編集・配備ルール' "$instructions"
  done

  grep -Fq '`run_after_*` と `run_onchange_*` を実行しない' "$architecture"
  grep -Fq '`private_dot_config/codex/` を変えた場合は続けて `sync-codex-managed-config`' "$architecture"
  grep -Fq 'chezmoi apply --force <配備先パス>' "$architecture"
  grep -Fq 'キャッシュ更新・Codex 同期のうち必要なもの' "$architecture"
}

@test "runtime notes record Codex sync side effects and isolated-session Herdr targeting" {
  local runtimes="$PROJECT_ROOT/runtime/ai-runtimes.md" index="$PROJECT_ROOT/runtime/index.md"

  grep -Fq 'Orca が登録した hook も消える' "$runtimes"
  grep -Fq 'Orca の起動時に再登録される' "$runtimes"
  grep -Fq '`echo "$HERDR_PANE_ID"` で値を取り' "$runtimes"
  grep -Fq '`herdr pane layout --pane "$HERDR_PANE_ID"`' "$index"
  grep -Fq '変数代入そのものが拒否されるかは未確認' "$index"
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
  grep -Fq 'Continue → /clear → /handoff → Subagent → /compact' "$PROJECT_ROOT/GLOSSARY.md"
}

@test "standard workflow uses one integration PR and preserves publication and destructive-action boundaries" {
  local instructions
  for instructions in "$GLOBAL_CODEX" "$GLOBAL_CLAUDE"; do
    grep -Fq '`implement-spec`' "$instructions"
    grep -Fq '`pr`' "$instructions"
    grep -Fq '`retro`' "$instructions"
    grep -Fq 'Integration Branch／PR' "$instructions"
    ! grep -Eq 'to-pr|batch-implement|harness-feedback' "$instructions"
  done
  grep -Fq '用語集（`GLOSSARY.md`）や対象領域の ADR があれば、コード探索前に読む。無ければそのまま進む。' "$GLOBAL_CODEX"
  ! grep -Fq 'docs/agents/domain.md' "$GLOBAL_CODEX"
  grep -Fq '`docs/agents/domain.md`' "$PROJECT_ROOT/AGENTS.md"
  grep -Fq '`GLOSSARY.md`' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '一つの Integration Branch' "$RUNTIME"
  grep -Fq 'draft PR' "$RUNTIME"
  grep -Fq 'ready 化' "$RUNTIME"
  grep -Fq '上流の reset／cleanup 指示は破壊操作の承認ではない' "$RUNTIME"
  grep -Fq '`git-push-topic`' "$RUNTIME"
  grep -Fq 'gh pr create --base' "$RUNTIME"
  [ -f "$PROJECT_ROOT/GLOSSARY.md" ]
  [ ! -e "$PROJECT_ROOT/CONTEXT.md" ]
  grep -Fxq 'GLOSSARY.md' "$PROJECT_ROOT/.chezmoiignore"
  grep -Fq '**Integration Branch**' "$PROJECT_ROOT/GLOSSARY.md"
  ! grep -Eq 'to-pr|batch-implement|harness-feedback' "$PROJECT_ROOT/runtime/ai-runtimes.md"
}

@test "local workflow overrides preserve triage, review base, and Review Round authority" {
  grep -Fq '`triage` は推薦根拠の read-only 検証' "$GLOBAL_CLAUDE"
  grep -Fq 'standalone で base が不明な場合は確認する' "$GLOBAL_CLAUDE"
  grep -Fq '`gh-review-thread` に統一する' "$GLOBAL_CLAUDE"
  grep -Fq '1つの Review Round' "$GLOBAL_CLAUDE"
  grep -Fq '`git-push-topic`' "$GLOBAL_CLAUDE"

  grep -Fq '`triage` は推薦根拠を得る read-only 検証' "$RUNTIME"
  grep -Fq 'standalone で fixed point が不明な場合だけ質問する' "$RUNTIME"
  grep -Fq '専用 CLI `gh-review-thread` に統一する' "$RUNTIME"
  grep -Fq '選択 thread 群の Review Round' "$RUNTIME"
  grep -Fq '`git-push-topic`' "$RUNTIME"
}

@test "empirical prompt tuning does not claim strict convergence without usage metrics" {
  local instructions

  grep -Fq '外部 skill を実行・評価するときのローカル上書き' "$GLOBAL_CODEX"
  for instructions in "$GLOBAL_CLAUDE" "$RUNTIME"; do
    grep -Fq '`tool_uses` または `duration_ms` を取得できない round' "$instructions"
    grep -Fq 'strict convergence の判定に含めない' "$instructions"
    grep -Fq '`qualitative plateau; quantitative convergence unverified`' "$instructions"
    grep -Fq '明示的な `resource cutoff`' "$instructions"
  done
}

@test "instruction layers guard model-invoked external writes, secrets, and permissions" {
  grep -Fq 'model-invoked discipline' "$GLOBAL_CLAUDE"
  grep -Fq '外部書込みは親 Contract' "$GLOBAL_CLAUDE"
  grep -Fq '機密情報・credential・CI secret' "$GLOBAL_CLAUDE"
  grep -Fq '読み出し、出力、commit' "$GLOBAL_CLAUDE"
  grep -Fq '無断変更' "$GLOBAL_CLAUDE"
  grep -Fq 'permission bypass' "$GLOBAL_CLAUDE"

  grep -Fq 'model-invoked discipline' "$RUNTIME"
  grep -Fq '外部書込み（Issue / PR / shared service など）は親の Contract' "$RUNTIME"
  grep -Fq '機密情報・credential・CI secret' "$RUNTIME"
  grep -Fq '読み出し、出力、commit' "$RUNTIME"
  grep -Fq '無断変更' "$RUNTIME"
  grep -Fq 'permission bypass' "$RUNTIME"
}

@test "instruction layers keep newly generated secrets off screen" {
  for instructions in "$GLOBAL_CLAUDE" "$GLOBAL_CODEX"; do
    grep -Fq 'including ones you just generated' "$instructions"
    grep -Fq 'commands you hand to the user' "$instructions"
    grep -Fq 'mode-0600 temporary file' "$instructions"
    grep -Fq 'without reading the value back' "$instructions"
  done
  grep -Fq '新しく作る値も' "$RUNTIME"
  grep -Fq '権限 0600 の一時ファイル' "$RUNTIME"
  grep -Fq '値を読み戻さず' "$RUNTIME"
}

@test "rejected shell syntax falls back to a single allowed command, then to the human" {
  run grep -Fq 'スクリプトを scratchpad に書いて実行する' "$GLOBAL_CLAUDE"
  [ "$status" -eq 1 ]
  grep -Fq '許可された単一のコマンドへ書き直す' "$GLOBAL_CLAUDE"
  grep -Fq '同じ形の再試行をせず' "$GLOBAL_CLAUDE"
  grep -Fq '外部のターミナル向けにまとめて渡す' "$GLOBAL_CLAUDE"
  grep -Fq '権限による拒否の迂回には使わない' "$GLOBAL_CLAUDE"

  local index="$PROJECT_ROOT/runtime/index.md"
  grep -Fq '`--body-file <相対パス>`' "$index"
  grep -Fq 'scratchpad' "$index"
}

@test "prototype contract is a self-contained HTML primary source" {
  for instructions in "$GLOBAL_CLAUDE" "$RUNTIME"; do
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

  grep -Fq 'Matt Pocock skill の workflow / safety contract' "$GLOBAL_CODEX"
  grep -Fq '`~/runtime/skill-harness.md`' "$GLOBAL_CODEX"
  ! grep -Fq '## Matt Pocock workflow contract' "$GLOBAL_CODEX"
  ! grep -Fq 'model-invoked discipline' "$GLOBAL_CODEX"
  ! grep -Fq 'single self-contained HTML' "$GLOBAL_CODEX"

  grep -Fq 'Matt Pocock workflow contract' "$GLOBAL_CLAUDE"
  grep -Fq '共有する workflow / safety contract は整合させる' "$PROJECT_ROOT/CLAUDE.md"
  grep -Fq '共有する workflow / safety contract は整合させる' "$PROJECT_ROOT/AGENTS.md"
  grep -Fq '**Instruction ownership**' "$RUNTIME"
  grep -Fq 'OpenCode / Zed / Cursor などのグローバル指示はこの dotfiles では管理しない' "$RUNTIME"
  ! grep -Fq '`AGENTS.md` は Codex / OpenCode / Zed / Cursor' "$RUNTIME"
}

@test "managed workflow revision uses explicit invocation, round separators, and setup pointers" {
  grep -Fq '複数質問の間を horizontal rule (`---`) で区切る' "$GLOBAL_CLAUDE"
  grep -Fq 'cross-skill 呼出しは Skill tool と skill 名を明示する' "$GLOBAL_CLAUDE"
  grep -Fq '別の user-invoked skill から自動実行せず' "$GLOBAL_CLAUDE"

  grep -Fq '49dd158d1076134a641b33efb035946536778336' "$RUNTIME"
  grep -Fq '複数質問の間を horizontal rule (`---`) で区切る' "$RUNTIME"
  grep -Fq 'Skill tool と skill 名を明示する' "$RUNTIME"
  grep -Fq '`setup-matt-pocock-skills` を自動実行せず' "$RUNTIME"
}

@test "AGENTS routes browser work by interaction surface" {
  local instructions="$GLOBAL_CODEX"

  grep -Fq 'Orca 内蔵 page は `orca-cli`' "$instructions"
  grep -Fq '外部 Web page の自動操作は `playwright-cli` または CDP' "$instructions"
  grep -Fq '外部 browser window や native app の OS/window-level 操作は `computer-use`' "$instructions"
  grep -Fq 'Chrome MV3 拡張は persistent Chromium context' "$instructions"
  grep -Fq '要素指差しフィードバック機能' "$instructions"
}

@test "native worktree guidance replaces the retired entry skill" {
  [ ! -e "$PROJECT_ROOT/local-skills/to-worktree" ]
  for instructions in "$GLOBAL_CODEX" "$GLOBAL_CLAUDE"; do
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
  grep -Fq '[worker readiness 手順](../local-skills/orca-peer-refactor/references/orca.md#worktree-readiness)' "$RUNTIME"
  grep -Fq 'ローカル変更につながる診断・実装を Orca の Git task worktree で監督する場合は' "$RUNTIME"
  grep -Fq '配備先: `~/.agents/skills/orca-peer-refactor/references/orca.md#worktree-readiness`' "$RUNTIME"
  grep -Fq '同じ実行 host の worktree 検証が前提で、remote placement は実行 host 側の独立観測を要する' "$RUNTIME"
  grep -Fq 'folder workspace、および primary checkout での説明・状態確認・読み取り調査は対象外' "$RUNTIME"
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

@test "repo-root instructions stay out of home while global sources carry shared contracts" {
  grep -Fxq 'CLAUDE.md' "$PROJECT_ROOT/.chezmoiignore"
  grep -Fxq 'AGENTS.md' "$PROJECT_ROOT/.chezmoiignore"
  local root instructions
  for root in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq 'home へは配備しない' "$root"
    ! grep -Fq '## 設計→実装ワークフロー' "$root"
    ! grep -Fq '## ブラウザ操作ツール' "$root"
    ! grep -Fq '## Google Cloud / GitHub の調査' "$root"
  done
  for instructions in "$GLOBAL_CLAUDE" "$GLOBAL_CODEX"; do
    grep -Fq '## 設計→実装ワークフロー' "$instructions"
    grep -Fq '## Google Cloud / GitHub の調査' "$instructions"
    ! grep -Fq '`runtime/' "$instructions"
  done
  grep -Fq 'status: accepted' "$PROJECT_ROOT/docs/adr/0078-keep-repo-instructions-out-of-home.md"
}

@test "pre-commit runs the instruction contract tests when instruction files change" {
  run python3 -I - "$PROJECT_ROOT" <<'PY'
import json
import shlex
import subprocess
import sys

dump = subprocess.run(["lefthook", "dump", "--format", "json"], cwd=sys.argv[1], capture_output=True, text=True, check=True)
job = next(job for job in json.loads(dump.stdout)["pre-commit"]["jobs"] if job.get("name") == "instruction-contract")
commands = [shlex.split(part) for part in job["run"].split("&&")]
assert commands[0][:3] == ["command", "-v", "codex"], commands
assert commands[1] == ["bats", "tests/workflow-contract.bats", "tests/autonomous-peer-contract.bats"], commands
assert commands[2] == ["bats", "--filter", "Review Round contract", "tests/gh-review-thread.bats"], commands
# 契約テストが読むファイルの変更で起動する。
required = {
    "CLAUDE.md", "AGENTS.md", "GLOSSARY.md", ".chezmoiignore", "lefthook.yml", "runtime/*.md",
    "private_dot_claude/CLAUDE.md", "private_dot_claude/auto-peer-deny.json", "private_dot_claude/settings.json.tmpl",
    "private_dot_config/codex/AGENTS.md", "private_dot_config/codex/auto-peer.rules",
    "private_dot_config/codex/config.toml.tmpl", "private_dot_config/codex/rules/default.rules",
    "private_dot_local/bin/executable_sync-codex-managed-config", "private_dot_gemini/AGENTS.md",
    "tests/workflow-contract.bats", "tests/autonomous-peer-contract.bats", "tests/gh-review-thread.bats",
}
missing = sorted(required - set(job["glob"]))
assert not missing, missing
PY
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  run bats --count --filter 'Review Round contract' "$PROJECT_ROOT/tests/gh-review-thread.bats"
  [ "$output" -ge 1 ]
}
