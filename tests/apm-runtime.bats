#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "APM selects validated Impeccable and retains specialist UI skills" {
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -Fq 'pbakaus/impeccable/.agents/skills/impeccable#4d849eb75f216109ea7053ed21530a11fafcc786' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/frontend-design' "$manifest"

  local skill
  for skill in web-design-guidelines react-best-practices composition-patterns react-view-transitions shadcn remotion-best-practices modern-web-guidance; do
    grep -Fq "$skill" "$manifest"
  done
}

@test "APM lock materializes the validated Impeccable payload" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'repo_url: pbakaus/impeccable' "$lock"
  grep -Fq 'resolved_commit: 4d849eb75f216109ea7053ed21530a11fafcc786' "$lock"
  grep -Fq 'virtual_path: .agents/skills/impeccable' "$lock"
  grep -Fq '.agents/skills/impeccable/scripts/hook.mjs' "$lock"
  grep -Fq '.claude/skills/impeccable/scripts/hook.mjs' "$lock"
  ! grep -Fq 'virtual_path: skills/frontend-design' "$lock"
}

@test "APM pins the Matt Pocock workflow to one validated revision with Codex metadata" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="9603c1cc8118d08bc1b3bf34cf714f62178dea3b"

  [ "$(grep -Fc "mattpocock/skills/skills/" "$manifest")" -eq 20 ]
  [ "$(grep -Fc "#$revision" "$manifest")" -eq 20 ]
  grep -Fq "resolved_commit: $revision" "$lock"
  grep -Fq '.agents/skills/grill-with-docs/agents/openai.yaml' "$lock"
  grep -Fq '.agents/skills/implement/agents/openai.yaml' "$lock"
  grep -Fq '.claude/skills/grilling/agents/openai.yaml' "$lock"
}

@test "APM runtime deploy targets remain git-ignored" {
  grep -q '^/\.agents/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/agents/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/commands/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/hooks/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/skills/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/apm-hooks\.json$' "$PROJECT_ROOT/.gitignore"
}

@test "APM install runs from HOME, not the chezmoi source checkout" {
  local script="$PROJECT_ROOT/run_onchange_after_apm-install.sh.tmpl"

  grep -q '^cd "\$HOME"$' "$script"
  grep -q '^apm install --frozen$' "$script"
  ! grep -q 'APM_LEGACY_SKILL_PATHS=1' "$script"
}

@test "APM install prunes packages removed from apm.yml" {
  local script="$PROJECT_ROOT/run_onchange_after_apm-install.sh.tmpl"

  grep -q '^apm prune$' "$script"
}

@test "APM targets do not add a duplicate explicit agent-skills target" {
  ! grep -q '^  - agent-skills$' "$PROJECT_ROOT/apm.yml"
}

@test "repo-local Claude skill deploy target is absent" {
  [ ! -e "$PROJECT_ROOT/.claude/skills" ]
}

@test "repo-local Agent skill deploy target is absent" {
  local target="$PROJECT_ROOT/.agents"

  if [ -e "$target" ] && findmnt -T "$target" -n >/dev/null 2>&1; then
    skip "$target is mounted by the current agent runtime"
  fi

  [ ! -e "$target" ]
}
