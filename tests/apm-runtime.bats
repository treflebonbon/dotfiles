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

@test "APM pins the official Matt Pocock v1.2.3 full set" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="6acc160e4e0cd062dbbbd7a1b26ae92855edf07e"
  local skill

  grep -Fq "mattpocock/skills#$revision" "$manifest"
  [ "$(grep -Fc "mattpocock/skills/skills/" "$manifest")" -eq 0 ]
  [ "$(grep -Fc "#$revision" "$manifest")" -eq 1 ]
  [ "$(grep -Fc "resolved_commit: $revision" "$lock")" -eq 1 ]
  grep -Fq 'name: mattpocock-skills' "$lock"
  grep -Fq 'package_type: marketplace_plugin' "$lock"
  for skill in \
    ask-matt diagnosing-bugs grill-with-docs triage improve-codebase-architecture \
    setup-matt-pocock-skills tdd to-spec to-tickets wayfinder implement prototype \
    research domain-modeling codebase-design code-review resolving-merge-conflicts \
    wizard grill-me grilling handoff teach to-questionnaire wait-what writing-for-agents; do
    grep -Fq "  - .agents/skills/$skill" "$lock"
    grep -Fq "  - .claude/skills/$skill" "$lock"
  done
  ! grep -Fq 'writing-great-skills' "$manifest"
  ! grep -Fq 'writing-great-skills' "$lock"
}

@test "APM advances changed selected payloads without pinning revision-only updates" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#460e5536b8e61034d83ff4af24bb0bf1112d2cb0' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#7fc6dea333869e23f58bf9e9861010e9ba589e5e' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#25be24cca34d06eed29a4779c3f48c4816aa812c' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"

  grep -Fq 'resolved_commit: 460e5536b8e61034d83ff4af24bb0bf1112d2cb0' "$lock"
  grep -Fq 'content_hash: sha256:8951bdfc695fb4d9c5966ecf6b4a9bcc921a6a0a20b2b237b1619735fec0265d' "$lock"
  grep -Fq 'resolved_commit: 7fc6dea333869e23f58bf9e9861010e9ba589e5e' "$lock"
  grep -Fq 'content_hash: sha256:7e361522d093e36666b234e3f0a4eaae11bd1a160de4bbfd6baea9a3228c595a' "$lock"
  [ "$(grep -Fc 'resolved_commit: 5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$lock")" -eq 1 ]
  grep -Fq 'content_hash: sha256:cca6a9098e0dff08ce6fef999da77d98e94255e826b8b9f8132749b5da66dad2' "$lock"
  ! grep -Fq 'resolved_commit: 0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$lock"
  ! grep -Fq 'resolved_commit: 25be24cca34d06eed29a4779c3f48c4816aa812c' "$lock"
  ! grep -Fq 'resolved_commit: 435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$lock"
}

@test "APM install is gated on a successful nix-devshell snapshot refresh" {
  local script="$PROJECT_ROOT/run_onchange_after_apm-install.sh.tmpl"
  local refresh_line
  local install_line

  grep -q 'NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache' "$script"
  refresh_line="$(grep -n 'NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache' "$script" | cut -d: -f1)"
  install_line="$(grep -n '^apm install --frozen$' "$script" | cut -d: -f1)"
  [ "$refresh_line" -lt "$install_line" ]
}

@test "APM Remotion assertions keep commit and content hash in one lock entry" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local remotion_entry

  remotion_entry="$(awk '
    /^- repo_url: / {
      if (active && repo == "- repo_url: remotion-dev/skills") {
        print block
        exit
      }
      repo = $0
      block = $0 ORS
      active = 1
      next
    }
    active { block = block $0 ORS }
    END {
      if (active && repo == "- repo_url: remotion-dev/skills") print block
    }
  ' "$lock")"

  [ -n "$remotion_entry" ]
  grep -Fq 'resolved_commit: 7fc6dea333869e23f58bf9e9861010e9ba589e5e' <<<"$remotion_entry"
  grep -Fq 'content_hash: sha256:7e361522d093e36666b234e3f0a4eaae11bd1a160de4bbfd6baea9a3228c595a' <<<"$remotion_entry"
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
