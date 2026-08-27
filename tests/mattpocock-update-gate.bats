#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MANIFEST="$PROJECT_ROOT/apm.yml"
  LOCK="$PROJECT_ROOT/apm.lock.yaml"
  CLEANUP="$PROJECT_ROOT/run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
  RUNTIME="$PROJECT_ROOT/runtime/skill-harness.md"
  ADR="$PROJECT_ROOT/docs/adr/0042-mattpocock-managed-set-update-gate.md"
  GATE="$PROJECT_ROOT/tests/mattpocock-update-gate.sh"
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$FAKE_BIN"
  ln -s "$PROJECT_ROOT/tests/fixtures/mattpocock-update-gate-apm.sh" "$FAKE_BIN/apm"
  ln -s "$PROJECT_ROOT/tests/fixtures/mattpocock-update-gate-bats.sh" "$FAKE_BIN/bats"
  ln -s "$PROJECT_ROOT/tests/fixtures/mattpocock-update-gate-chezmoi.sh" "$FAKE_BIN/chezmoi"
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
  grep -Fq 'content_hash: sha256:30aaf1538e75a717db8608778e06e1c47ce38578f46fe88e53e599818cf30c9f' "$LOCK"
  grep -Fq 'package_type: marketplace_plugin' "$LOCK"
  ! grep -R -Eiq 'npx[[:space:]]+skills|enabledPlugins.*mattpocock|mattpocock.*enabledPlugins' \
    "$PROJECT_ROOT/private_dot_claude" "$PROJECT_ROOT/private_dot_config" 2>/dev/null
}

@test "managed-set update gate executes the ordered verification seam" {
  local candidate="$BATS_TEST_TMPDIR/candidate.yml"
  local candidate_revision=1111111111111111111111111111111111111111
  local phase_log="$BATS_TEST_TMPDIR/phases.log"

  sed "s/mattpocock\/skills#[0-9a-f]\{40\}/mattpocock\/skills#$candidate_revision/" \
    "$MANIFEST" >"$candidate"

  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATTPOCOCK_GATE_LOG="$phase_log" \
    MATTPOCOCK_GATE_COMMAND_LOG="$COMMAND_LOG" \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$candidate"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Matt Pocock managed-set update gate completed for $candidate_revision"* ]]
  [ "$(cat "$phase_log")" = "$(printf '%s\n' lock-generation frozen-install audit skill-discovery workflow-contract-tests chezmoi-dry-run)" ]
  grep -Fq 'apm install --update --target claude,codex --https' "$COMMAND_LOG"
  grep -Fq 'apm install --frozen --target claude,codex --https' "$COMMAND_LOG"
  grep -Fq 'apm audit --ci' "$COMMAND_LOG"
  grep -Fq 'bats ' "$COMMAND_LOG"
  grep -Fq 'bats '"$PROJECT_ROOT/tests" "$COMMAND_LOG"
  grep -Fq 'chezmoi --source' "$COMMAND_LOG"
}

@test "managed-set update gate rejects frontmatter metadata in the body" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATT_GATE_INVALID_FRONTMATTER=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"discovery target contains an invalid skill payload"* ]]
}

@test "managed-set update gate rejects chezmoi dry-run content or symlink changes" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATTPOCOCK_GATE_COMMAND_LOG="$COMMAND_LOG" \
    MATT_GATE_MUTATE_CHEZMOI_FILE=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"chezmoi dry-run changed the isolated HOME"* ]]

  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATTPOCOCK_GATE_COMMAND_LOG="$COMMAND_LOG" \
    MATT_GATE_MUTATE_CHEZMOI_SYMLINK=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"chezmoi dry-run changed the isolated HOME"* ]]
}

@test "managed-set update gate rejects an unpinned candidate" {
  local candidate="$BATS_TEST_TMPDIR/latest.yml"
  cp "$MANIFEST" "$candidate"
  sed -E 's/mattpocock\/skills#[0-9a-f]{40}/mattpocock\/skills#@latest/' \
    "$candidate" >"$candidate.rewritten"
  mv "$candidate.rewritten" "$candidate"

  run env PATH="$FAKE_BIN:$PATH" "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$candidate"

  [ "$status" -ne 0 ]
  [[ "$output" == *"exact 40-hex commit"* ]]
}

@test "managed-set update gate rejects native or universal ownership" {
  local candidate_source="$BATS_TEST_TMPDIR/native-source"
  mkdir -p "$candidate_source/private_dot_claude"
  cp "$MANIFEST" "$candidate_source/apm.yml"
  cp "$LOCK" "$candidate_source/apm.lock.yaml"
  cp "$CLEANUP" "$candidate_source/run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
  printf '{\n  "enabledPlugins": [\n    "mattpocock@official"\n  ]\n}\n' >"$candidate_source/private_dot_claude/settings.json"

  run env PATH="$FAKE_BIN:$PATH" "$GATE" --source "$candidate_source" --candidate-manifest "$candidate_source/apm.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"native Claude plugin or universal npx skills route"* ]]

  printf 'npx skills add mattpocock/skills\n' >"$candidate_source/private_dot_claude/settings.json"
  run env PATH="$FAKE_BIN:$PATH" "$GATE" --source "$candidate_source" --candidate-manifest "$candidate_source/apm.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"native Claude plugin or universal npx skills route"* ]]
}

@test "managed-set update gate rejects non-Matt lock drift and frozen rewrites" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATT_GATE_MUTATE_NON_MATT=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-Matt dependency fields"* ]]

  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATT_GATE_MUTATE_FROZEN=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen install rewrote"* ]]
}

@test "managed-set update gate accepts Matt-owned deployment metadata changes" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATTPOCOCK_GATE_COMMAND_LOG="$COMMAND_LOG" \
    MATT_GATE_MUTATE_MATT_DEPLOYMENT=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"

  [ "$status" -eq 0 ]
}

@test "managed-set update gate rejects legacy workflow invocation semantics" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATTPOCOCK_GATE_COMMAND_LOG="$COMMAND_LOG" \
    MATT_GATE_LEGACY_WORKFLOW=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate workflow payload"* ]]
}

@test "managed-set update gate rejects extra discovered skills" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATT_GATE_ADD_EXTRA=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly the generated lock target set"* ]]
}

@test "managed-set update gate rejects an aliased Matt skill" {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    MATT_GATE_ALIAS_SKILL=1 \
    "$GATE" --source "$PROJECT_ROOT" --candidate-manifest "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exact official Matt Pocock v1.2.3 full set"* ]]
}

@test "managed-set update gate documents the cross-file contract" {
  [ -f "$ADR" ]
  [ -x "$GATE" ]
  grep -Fq '隔離 runtime' "$ADR"
  grep -Fq 'lock generation' "$ADR"
  grep -Fq 'apm install --update' "$ADR"
  grep -Fq 'apm install --frozen' "$ADR"
  grep -Fq 'apm audit --ci' "$ADR"
  grep -Fq 'skill discovery' "$ADR"
  grep -Fq 'workflow contract tests' "$ADR"
  grep -Fq 'chezmoi dry-run' "$ADR"
  grep -Fq 'rollback' "$ADR"
  grep -Fq '非 Matt' "$ADR"
  grep -Fq 'native lock adoption' "$ADR"
  grep -Fq '検証用lock' "$ADR"
  grep -Fq '@latest' "$ADR"
  grep -Fq '0042-mattpocock-managed-set-update-gate' "$RUNTIME"
}
