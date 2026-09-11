#!/usr/bin/env bats

@test "rop-visualizer renderer preserves source and validates flowchart paths" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$project_root/tests/helpers/rop-renderer-contract.py" \
    "$project_root/local-skills/rop-visualizer/scripts/render.py"
  [ "$status" -eq 0 ]
}

@test "rop-visualizer TypeScript evidence preserves source and records fallback" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 "$project_root/tests/helpers/rop-typescript-evidence.py" \
    "$project_root/local-skills/rop-visualizer/scripts/extract-typescript.py"
  [ "$status" -eq 0 ]
}

@test "rop-visualizer deploys its TypeScript helper and reference together" {
  load local-skills-helper
  setup_local_skills_fixture
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  local runtime file
  for runtime in .agents .claude; do
    for file in scripts/extract-typescript.py references/typescript-evidence.md; do
      cmp "$SKILL_SOURCE/local-skills/rop-visualizer/$file" \
        "$SKILL_HOME/$runtime/skills/rop-visualizer/$file"
    done
  done
  run python3 "$SKILL_HOME/.agents/skills/rop-visualizer/scripts/extract-typescript.py" --help
  [ "$status" -eq 0 ]
}
