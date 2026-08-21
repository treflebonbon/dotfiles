#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MANIFEST="$PROJECT_ROOT/apm.yml"
  LOCK="$PROJECT_ROOT/apm.lock.yaml"
  CLEANUP="$PROJECT_ROOT/run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
  ADR="$PROJECT_ROOT/docs/adr/0042-mattpocock-managed-set-update-gate.md"
}

lock_managed_skills() {
  awk '
    /^- repo_url: mattpocock\/skills$/ { active = 1; next }
    active && /^- repo_url:/ { exit }
    active && /^  - \.agents\/skills\/[^/]+$/ {
      sub(/^  - \.agents\/skills\//, "")
      print
    }
  ' "$LOCK" | sort
}

cleanup_managed_skills() {
  awk '
    /^managed_apm_skills=\(/ { active = 1; next }
    active && /^\)/ { exit }
    active && /^  [a-z0-9-]+$/ { print $1 }
  ' "$CLEANUP" | sort
}

@test "APM lock and orphan cleanup share the exact managed full set" {
  local lock_skills cleanup_skills

  lock_skills="$(lock_managed_skills)"
  cleanup_skills="$(cleanup_managed_skills)"

  [ "$(printf '%s\n' "$lock_skills" | sed '/^$/d' | wc -l)" -eq 25 ]
  [ "$(printf '%s\n' "$cleanup_skills" | sed '/^$/d' | wc -l)" -eq 25 ]
  [ "$lock_skills" = "$cleanup_skills" ]
}

@test "Matt managed set remains an exact commit pin with one APM owner" {
  local pin_line revision

  pin_line="$(grep -E '^[[:space:]]*-[[:space:]]mattpocock/skills#[0-9a-f]{40}$' "$MANIFEST")"
  revision="${pin_line##*#}"

  [ -n "$pin_line" ]
  ! grep -Eq 'mattpocock/skills#(@latest|main|v[0-9])' "$MANIFEST"
  [ "$(grep -Fc "resolved_commit: $revision" "$LOCK")" -eq 1 ]
  grep -Fq 'content_hash: sha256:7c5f630f29793c83e7ed0998b07689fd022709c243e8d36174fd06a98a9029f2' "$LOCK"
  grep -Fq 'package_type: marketplace_plugin' "$LOCK"
  ! grep -R -Eiq 'npx[[:space:]]+skills|enabledPlugins.*mattpocock|mattpocock.*enabledPlugins' \
    "$PROJECT_ROOT/private_dot_claude" "$PROJECT_ROOT/private_dot_config" 2>/dev/null
}

@test "managed-set update gate documents the ordered verification seam" {
  [ -f "$ADR" ]
  grep -Fq '隔離 runtime' "$ADR"
  grep -Fq 'lock generation' "$ADR"
  grep -Fq 'apm install --update' "$ADR"
  grep -Fq 'apm install --frozen' "$ADR"
  grep -Fq 'apm audit --ci' "$ADR"
  grep -Fq 'skill discovery' "$ADR"
  grep -Fq 'workflow contract tests' "$ADR"
  grep -Fq 'chezmoi dry-run' "$ADR"
  grep -Fq 'rollback' "$ADR"
  grep -Fq '@latest' "$ADR"
  grep -Fq '0042-mattpocock-managed-set-update-gate' "$RUNTIME"
}
