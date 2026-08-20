#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "APM selects validated Impeccable and retains specialist UI skills" {
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -Fq 'pbakaus/impeccable/.agents/skills/impeccable#5a149f3fdb1b5793f10567233b1dcab98fc305fd' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/frontend-design' "$manifest"

  local skill
  for skill in web-design-guidelines react-best-practices composition-patterns react-view-transitions shadcn remotion-best-practices modern-web-guidance; do
    grep -Fq "$skill" "$manifest"
  done
}

@test "APM lock materializes the validated Impeccable payload" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'apm_version: 0.28.0' "$lock"
  grep -Fq 'repo_url: pbakaus/impeccable' "$lock"
  grep -Fq 'resolved_commit: 5a149f3fdb1b5793f10567233b1dcab98fc305fd' "$lock"
  grep -Fq 'content_hash: sha256:b34f5d2af061c9666acf7c0c49c8c502384a16eaa5ca24b819a726b16d303504' "$lock"
  grep -Fq 'virtual_path: .agents/skills/impeccable' "$lock"
  grep -Fq '.agents/skills/impeccable/scripts/hook.mjs' "$lock"
  grep -Fq '.claude/skills/impeccable/scripts/hook.mjs' "$lock"
  ! grep -Fq 'virtual_path: skills/frontend-design' "$lock"
}

@test "APM pins the Matt Pocock workflow to one validated revision with Codex metadata" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="ed37663cc5fbef691ddfecd080dff42f7e7e350d"

  [ "$(grep -Fc "mattpocock/skills/skills/" "$manifest")" -eq 20 ]
  [ "$(grep -Fc "#$revision" "$manifest")" -eq 20 ]
  grep -Fq "resolved_commit: $revision" "$lock"
  grep -Fq '.agents/skills/grill-with-docs/agents/openai.yaml' "$lock"
  grep -Fq '.agents/skills/implement/agents/openai.yaml' "$lock"
  grep -Fq '.claude/skills/grilling/agents/openai.yaml' "$lock"
}

@test "APM advances changed selected payloads without pinning revision-only updates" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#460e5536b8e61034d83ff4af24bb0bf1112d2cb0' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#21320596cf9008cf6ccaa6bf1a2b9f71c8f191c3' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#25be24cca34d06eed29a4779c3f48c4816aa812c' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"

  grep -Fq 'resolved_commit: 460e5536b8e61034d83ff4af24bb0bf1112d2cb0' "$lock"
  grep -Fq 'content_hash: sha256:8951bdfc695fb4d9c5966ecf6b4a9bcc921a6a0a20b2b237b1619735fec0265d' "$lock"
  grep -Fq 'resolved_commit: 21320596cf9008cf6ccaa6bf1a2b9f71c8f191c3' "$lock"
  grep -Fq 'content_hash: sha256:9bf98c09ab9209e1b40868146b012e220b7b08857653480024e7c07cb946f7c8' "$lock"
  [ "$(grep -Fc 'resolved_commit: 5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$lock")" -eq 1 ]
  grep -Fq 'content_hash: sha256:cca6a9098e0dff08ce6fef999da77d98e94255e826b8b9f8132749b5da66dad2' "$lock"
  ! grep -Fq 'resolved_commit: 0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$lock"
  ! grep -Fq 'resolved_commit: 25be24cca34d06eed29a4779c3f48c4816aa812c' "$lock"
  ! grep -Fq 'resolved_commit: 435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$lock"
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
