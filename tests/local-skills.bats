#!/usr/bin/env bats

load local-skills-helper

setup() {
  setup_local_skills_fixture
}

@test "SKILL.md must resolve to a regular file before cleanup" {
  mkdir -p "$SKILL_SOURCE/local-skills/incomplete" "$SKILL_HOME/.claude/skills/orphan"
  mkfifo "$SKILL_SOURCE/local-skills/incomplete/SKILL.md"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILL.md"* ]]
  [ -d "$SKILL_HOME/.claude/skills/orphan" ]
}

@test "local deployment handles spaces and quotes in its source path" {
  mv "$SKILL_SOURCE" "$BATS_TEST_TMPDIR/source's files"
  SKILL_SOURCE="$BATS_TEST_TMPDIR/source's files"
  add_local_skill sample-skill
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/.agents/skills/sample-skill/SKILL.md"
}

@test "unchanged applies do nothing and payload-only changes update local copies without rerunning APM" {
  setup_skill_apply
  add_local_skill sample-skill
  printf 'first asset\n' >"$SKILL_SOURCE/local-skills/sample-skill/asset.txt"
  ln -s asset.txt "$SKILL_SOURCE/local-skills/sample-skill/linked.txt"
  touch "$SKILL_SOURCE/local-skills/sample-skill/.gitkeep"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  printf 'local edit\n' >"$SKILL_HOME/.agents/skills/sample-skill/SKILL.md"

  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(cat "$SKILL_HOME/.agents/skills/sample-skill/SKILL.md")" = 'local edit' ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 2 ]

  printf 'changed asset\n' >"$SKILL_SOURCE/local-skills/sample-skill/asset.txt"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  local dir
  for dir in .agents .claude; do
    cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/$dir/skills/sample-skill/SKILL.md"
    [ "$(cat "$SKILL_HOME/$dir/skills/sample-skill/linked.txt")" = 'changed asset' ]
    [ ! -L "$SKILL_HOME/$dir/skills/sample-skill/linked.txt" ]
    [ ! -e "$SKILL_HOME/$dir/skills/sample-skill/.gitkeep" ]
  done
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 2 ]
}

@test "retirement-only and shared-module changes rerun the required phases" {
  setup_skill_apply
  add_local_skill sample-skill
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  mkdir -p "$SKILL_HOME/.agents/skills/legacy-local" "$SKILL_HOME/.claude/skills/legacy-local" "$SKILL_HOME/.agents/skills/unrelated"
  printf 'localSkills:\n  retired: [legacy-local]\n' >"$SKILL_SOURCE/.chezmoidata/local-skills.yaml"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ ! -e "$SKILL_HOME/.agents/skills/legacy-local" ]
  [ ! -e "$SKILL_HOME/.claude/skills/legacy-local" ]
  [ -d "$SKILL_HOME/.agents/skills/unrelated" ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 4 ]

  printf '\n# Changed shared module.\n' >>"$SKILL_SOURCE/.chezmoitemplates/local-skills.sh"
  printf 'local edit\n' >"$SKILL_HOME/.agents/skills/sample-skill/SKILL.md"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 6 ]
  cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/.agents/skills/sample-skill/SKILL.md"
  [ "$(cat "$SKILL_HOME/.claude/skills/pdf/SKILL.md")" = 'APM payload' ]
}

@test "a missing source root aborts apply before any skill or APM changes" {
  setup_skill_apply
  mkdir -p "$SKILL_HOME/.claude/skills/orphan"
  mv "$SKILL_SOURCE/local-skills" "$BATS_TEST_TMPDIR/missing-source"
  run skill_chezmoi apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"local skill source missing"* ]]
  [ -d "$SKILL_HOME/.claude/skills/orphan" ]
  [ ! -s "$SKILL_APM_LOG" ]
}

@test "a membership change reruns APM after cleanup and deploys the new local skill" {
  setup_skill_apply
  mkdir -p "$SKILL_HOME/.claude/skills/orphan"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(cat "$SKILL_APM_LOG")" = $'install --frozen --target claude,codex --https\nprune' ]
  add_local_skill sample-skill

  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(cat "$SKILL_HOME/.claude/skills/pdf/SKILL.md")" = 'APM payload' ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 4 ]
  cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/.agents/skills/sample-skill/SKILL.md"
  cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/.claude/skills/sample-skill/SKILL.md"
}

@test "a failed placement restores the old symlink and a retry completes the local deployment" {
  add_local_skill aaa-sample new-payload
  mkdir -p "$SKILL_HOME/.claude/skills" "$BATS_TEST_TMPDIR/bin"
  ln -s "$SKILL_HOME/missing" "$SKILL_HOME/.claude/skills/aaa-sample"
  export SKILL_FAIL_TARGET="$SKILL_HOME/.claude/skills/aaa-sample"
  export SKILL_REAL_MV="$(command -v mv)"
  cat >"$BATS_TEST_TMPDIR/bin/mv" <<'EOF'
#!/usr/bin/env bash
if [ "${@: -1}" = "$SKILL_FAIL_TARGET" ] && [[ "${@: -2:1}" == "$SKILL_FAIL_TARGET.tmp."* ]]; then
  exit 1
fi
exec "$SKILL_REAL_MV" "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/mv"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  run run_skill_phase after_deploy-local-skills
  [ "$status" -ne 0 ]
  [ -L "$SKILL_FAIL_TARGET" ]
  [ "$(readlink "$SKILL_FAIL_TARGET")" = "$SKILL_HOME/missing" ]
  cmp "$SKILL_SOURCE/local-skills/aaa-sample/SKILL.md" "$SKILL_HOME/.agents/skills/aaa-sample/SKILL.md"

  export SKILL_FAIL_TARGET=""
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  cmp "$SKILL_SOURCE/local-skills/aaa-sample/SKILL.md" "$SKILL_HOME/.claude/skills/aaa-sample/SKILL.md"
  [ -z "$(find "$SKILL_HOME" -name '*.old.*' -o -name '*.tmp.*')" ]
}

@test "invalid local retirement declarations cannot remove active, APM, or unrelated paths" {
  mkdir -p "$SKILL_HOME/.agents/outside" "$SKILL_HOME/.claude/skills/orphan"
  local name
  for name in to-pr grilling ../outside; do
    printf 'localSkills:\n  retired: [%s]\n' "$name" >"$SKILL_SOURCE/.chezmoidata/local-skills.yaml"
    run run_skill_phase before_remove-orphan-claude-skills
    [ "$status" -ne 0 ]
    [[ "$output" == *"local skill"* ]]
    [ -d "$SKILL_HOME/.claude/skills/orphan" ]
    [ -d "$SKILL_HOME/.agents/outside" ]
  done
}

@test "a local name colliding with a skill inside an APM collection is rejected before changes" {
  add_local_skill grilling
  mkdir -p "$SKILL_HOME/.agents/skills/grilling" "$SKILL_HOME/.claude/skills/orphan"
  printf 'APM payload\n' >"$SKILL_HOME/.agents/skills/grilling/SKILL.md"
  local phase
  for phase in before_remove-orphan-claude-skills after_deploy-local-skills; do
    run run_skill_phase "$phase"
    [ "$status" -ne 0 ]
    [[ "$output" == *"APM"*"grilling"* ]]
    [ "$(cat "$SKILL_HOME/.agents/skills/grilling/SKILL.md")" = 'APM payload' ]
    [ -d "$SKILL_HOME/.claude/skills/orphan" ]
  done
}

@test "a missing SKILL.md rejects all local changes before cleanup or deployment" {
  mkdir -p "$SKILL_SOURCE/local-skills/incomplete" "$SKILL_HOME/.claude/skills/orphan"
  printf 'keep me\n' >"$SKILL_HOME/.claude/skills/orphan/SKILL.md"
  local phase
  for phase in before_remove-orphan-claude-skills after_deploy-local-skills; do
    run run_skill_phase "$phase"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SKILL.md"* ]]
    [ "$(cat "$SKILL_HOME/.claude/skills/orphan/SKILL.md")" = 'keep me' ]
    [ ! -e "$SKILL_HOME/.agents/skills/to-pr" ]
  done
}

@test "renaming a local skill with an explicit retirement removes the old deployment" {
  add_local_skill old-name
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  mv "$SKILL_SOURCE/local-skills/old-name" "$SKILL_SOURCE/local-skills/new-name"
  add_local_skill new-name
  mkdir -p "$SKILL_SOURCE/.chezmoidata" "$SKILL_HOME/.codex/skills/old-name" "$SKILL_HOME/.codex-app/skills/old-name"
  printf 'localSkills:\n  retired: [old-name]\n' >"$SKILL_SOURCE/.chezmoidata/local-skills.yaml"

  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]

  local dir
  for dir in .agents .claude; do
    [ ! -e "$SKILL_HOME/$dir/skills/old-name" ]
    cmp "$SKILL_SOURCE/local-skills/new-name/SKILL.md" "$SKILL_HOME/$dir/skills/new-name/SKILL.md"
  done
  [ ! -e "$SKILL_HOME/.codex/skills/old-name" ]
  [ ! -e "$SKILL_HOME/.codex-app/skills/old-name" ]
}

@test "a local skill placed in source is deployed and survives the next cleanup" {
  add_local_skill sample-skill

  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]

  local dir
  for dir in .agents .claude; do
    cmp "$SKILL_SOURCE/local-skills/sample-skill/SKILL.md" "$SKILL_HOME/$dir/skills/sample-skill/SKILL.md"
  done
  cmp "$SKILL_SOURCE/local-skills/ui-grill-with-docs/SKILL.md" "$SKILL_HOME/.agents/skills/ui-grill-with-docs/SKILL.md"
  [ ! -e "$SKILL_HOME/.codex/skills/sample-skill" ]
}
