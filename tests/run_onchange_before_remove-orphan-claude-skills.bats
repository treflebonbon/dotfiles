#!/usr/bin/env bats

setup() {
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.claude/skills"
  SCRIPT="$BATS_TEST_DIRNAME/../run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
}

run_script() {
  HOME="$FAKE_HOME" bash "$SCRIPT"
}

@test "removes real directories directly under ~/.claude/skills/" {
  mkdir -p "$FAKE_HOME/.claude/skills/orphan-skill"
  printf 'stub\n' >"$FAKE_HOME/.claude/skills/orphan-skill/SKILL.md"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/orphan-skill" ]
}

@test "preserves symlinks (does not follow or delete them)" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill" "$FAKE_HOME/.claude/skills/my-custom-skill"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/my-custom-skill" ]
  [ -d "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill" ]
}

@test "no-op when ~/.claude/skills/ does not exist" {
  rm -rf "$FAKE_HOME/.claude/skills"

  run run_script
  [ "$status" -eq 0 ]
}

@test "removes real directories recursively (nested files do not block deletion)" {
  mkdir -p "$FAKE_HOME/.claude/skills/orphan-skill/references"
  printf 'inner\n' >"$FAKE_HOME/.claude/skills/orphan-skill/references/note.md"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/orphan-skill" ]
}

@test "resolves repo-local APM deploy targets via CHEZMOI_SOURCE_DIR when set" {
  local repo="$BATS_TEST_TMPDIR/ghq-source"
  mkdir -p "$repo/.agents/skills/frontend-design" "$repo/.claude/commands"
  printf 'stub\n' >"$repo/.agents/skills/frontend-design/SKILL.md"

  HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR="$repo" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$repo/.agents" ]
  [ ! -e "$repo/.claude/commands" ]
}

@test "removes repo-local APM deploy targets when they are not mounted" {
  local repo="$FAKE_HOME/.local/share/chezmoi"
  mkdir -p \
    "$repo/.agents/skills/frontend-design" \
    "$repo/.codex/agents" \
    "$repo/.codex/skills/frontend-design" \
    "$repo/.claude/skills/frontend-design" \
    "$repo/.claude/agents" \
    "$repo/.claude/commands" \
    "$repo/.claude/hooks"
  printf 'stub\n' >"$repo/.agents/skills/frontend-design/SKILL.md"
  printf 'stub\n' >"$repo/.codex/skills/frontend-design/SKILL.md"
  printf '{}\n' >"$repo/.codex/hooks.json"
  printf '{}\n' >"$repo/.claude/apm-hooks.json"

  HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR= run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ ! -e "$repo/.agents" ]
  [ ! -e "$repo/.codex/agents" ]
  [ ! -e "$repo/.codex/skills" ]
  [ ! -e "$repo/.codex/hooks.json" ]
  [ ! -e "$repo/.claude/skills" ]
  [ ! -e "$repo/.claude/agents" ]
  [ ! -e "$repo/.claude/commands" ]
  [ ! -e "$repo/.claude/hooks" ]
  [ ! -e "$repo/.claude/apm-hooks.json" ]
}

@test "removes nix-store symlinks under ~/.agents/skills when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  ln -s "/nix/store/aaaa-fake/skills/foo" "$FAKE_HOME/.agents/skills/foo"
  ln -s "/nix/store/bbbb-fake/skills/bar" "$FAKE_HOME/.agents/skills/bar"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.agents/skills/foo" ]
  [ ! -e "$FAKE_HOME/.agents/skills/bar" ]
  [ ! -f "$FAKE_HOME/.agents/skills/.managed-by-ai-nix" ]
}

@test "preserves non-nix-store symlinks under ~/.agents/skills even when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  mkdir -p "$BATS_TEST_TMPDIR/apm-cache/my-custom-skill"
  ln -s "$BATS_TEST_TMPDIR/apm-cache/my-custom-skill" "$FAKE_HOME/.agents/skills/my-custom-skill"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.agents/skills/my-custom-skill" ]
  [ ! -f "$FAKE_HOME/.agents/skills/.managed-by-ai-nix" ]
}

@test "removes nix-store symlinks under ~/.agents/skills when marker absent" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  ln -s "/nix/store/cccc-fake/skills/keep-me" "$FAKE_HOME/.agents/skills/keep-me"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.agents/skills/keep-me" ]
}

@test "removes ai-nix companion symlinks under ~/.claude/skills when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills"
  ln -s "../../.agents/skills/agent-browser" "$FAKE_HOME/.claude/skills/agent-browser"
  ln -s "../../.agents/skills/dogfood" "$FAKE_HOME/.claude/skills/dogfood"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/agent-browser" ]
  [ ! -e "$FAKE_HOME/.claude/skills/dogfood" ]
}

@test "preserves unrelated symlinks under ~/.claude/skills even when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills"
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/keep-me"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/keep-me" "$FAKE_HOME/.claude/skills/keep-me"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/keep-me" ]
}

@test "removes ai-nix companion symlinks under ~/.codex/skills when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
}

@test "removes ai-nix companion symlinks under custom CODEX_HOME/skills too" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  ln -s "../../.agents/skills/find-skills" "$codex_home/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -e "$codex_home/skills/find-skills" ]
}

@test "removes ai-nix companion symlinks under existing Codex Desktop home (.codex-app) when CODEX_HOME is unset" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$FAKE_HOME/.codex-app/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex-app/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run env -u CODEX_HOME HOME="$FAKE_HOME" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -e "$FAKE_HOME/.codex-app/skills/find-skills" ]
}

@test "leaves Codex Desktop home (.codex-app) untouched when it does not exist and CODEX_HOME is unset" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run env -u CODEX_HOME HOME="$FAKE_HOME" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -d "$FAKE_HOME/.codex-app" ]
}

@test "removes retired APM UI skill real directories from agent runtimes" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    mkdir -p "$dir/baseline-ui" "$dir/fixing-accessibility" "$dir/fixing-metadata" "$dir/fixing-motion-performance" "$dir/modern-web-guidance"
  done

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    [ ! -e "$dir/baseline-ui" ]
    [ ! -e "$dir/fixing-accessibility" ]
    [ ! -e "$dir/fixing-metadata" ]
    [ ! -e "$dir/fixing-motion-performance" ]
  done

  [ -d "$FAKE_HOME/.agents/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.codex/skills/modern-web-guidance" ]
  [ -d "$codex_home/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.gemini/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.copilot/skills/modern-web-guidance" ]
}

@test "preserves external APM skills in ~/.agents for Codex Desktop discovery" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p \
    "$FAKE_HOME/.agents/skills/effect-ts" \
    "$FAKE_HOME/.agents/skills/frontend-design" \
    "$FAKE_HOME/.agents/skills/web-design-guidelines" \
    "$FAKE_HOME/.agents/skills/pdf" \
    "$FAKE_HOME/.agents/skills/react-view-transitions" \
    "$FAKE_HOME/.agents/skills/shadcn" \
    "$FAKE_HOME/.agents/skills/remotion" \
    "$FAKE_HOME/.codex/skills/effect-ts" \
    "$FAKE_HOME/.codex/skills/frontend-design" \
    "$FAKE_HOME/.codex/skills/react-view-transitions" \
    "$FAKE_HOME/.codex/skills/shadcn" \
    "$codex_home/skills/effect-ts" \
    "$codex_home/skills/frontend-design"
  printf 'stub\n' >"$FAKE_HOME/.agents/skills/web-design-guidelines/SKILL.md"

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ -d "$FAKE_HOME/.agents/skills/effect-ts" ]
  [ -d "$FAKE_HOME/.agents/skills/frontend-design" ]
  [ -f "$FAKE_HOME/.agents/skills/web-design-guidelines/SKILL.md" ]
  [ -d "$FAKE_HOME/.agents/skills/pdf" ]
  [ -d "$FAKE_HOME/.agents/skills/react-view-transitions" ]
  [ -d "$FAKE_HOME/.agents/skills/shadcn" ]
  [ -d "$FAKE_HOME/.agents/skills/remotion" ]
  [ -d "$FAKE_HOME/.codex/skills/effect-ts" ]
  [ -d "$FAKE_HOME/.codex/skills/frontend-design" ]
  [ -d "$FAKE_HOME/.codex/skills/react-view-transitions" ]
  [ -d "$FAKE_HOME/.codex/skills/shadcn" ]
  [ -d "$codex_home/skills/effect-ts" ]
  [ -d "$codex_home/skills/frontend-design" ]
}

@test "removes local skill duplicates from Codex native skill dirs" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills"; do
    mkdir -p "$dir/to-pr" "$dir/to-worktree" "$dir/dogfood-to-issues" "$dir/ui-grill-with-docs" "$dir/frontend-design"
    printf 'stub\n' >"$dir/to-pr/SKILL.md"
    printf 'stub\n' >"$dir/frontend-design/SKILL.md"
  done

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ -d "$FAKE_HOME/.agents/skills/to-pr" ]
  [ -d "$FAKE_HOME/.claude/skills/to-pr" ]
  [ -d "$FAKE_HOME/.agents/skills/ui-grill-with-docs" ]
  [ -d "$FAKE_HOME/.claude/skills/ui-grill-with-docs" ]
  [ ! -e "$FAKE_HOME/.codex/skills/to-pr" ]
  [ ! -e "$FAKE_HOME/.codex/skills/to-worktree" ]
  [ ! -e "$FAKE_HOME/.codex/skills/dogfood-to-issues" ]
  [ ! -e "$FAKE_HOME/.codex/skills/ui-grill-with-docs" ]
  [ ! -e "$codex_home/skills/to-pr" ]
  [ ! -e "$codex_home/skills/to-worktree" ]
  [ ! -e "$codex_home/skills/dogfood-to-issues" ]
  [ ! -e "$codex_home/skills/ui-grill-with-docs" ]
  [ -d "$FAKE_HOME/.codex/skills/frontend-design" ]
  [ -d "$codex_home/skills/frontend-design" ]
}

@test "removes retired agent-browser and grill-me from agent runtime skill dirs" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    mkdir -p "$dir/agent-browser" "$dir/grill-me" "$dir/modern-web-guidance"
  done

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    [ ! -e "$dir/agent-browser" ]
    [ ! -e "$dir/grill-me" ]
    [ -d "$dir/modern-web-guidance" ]
  done
}

@test "removes retired coderabbit (autofix/code-review) and uxaudit skills from agent runtime skill dirs" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    mkdir -p "$dir/autofix" "$dir/code-review" "$dir/uxaudit" "$dir/modern-web-guidance"
  done

  HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    [ ! -e "$dir/autofix" ]
    [ ! -e "$dir/code-review" ]
    [ ! -e "$dir/uxaudit" ]
    [ -d "$dir/modern-web-guidance" ]
  done
}
