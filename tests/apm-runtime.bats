#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "APM selects validated Impeccable and retains specialist UI skills" {
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -Fq 'pbakaus/impeccable/.agents/skills/impeccable#63b04e2530f5c7b41ea83c133daab24f34912456' "$manifest"
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
  grep -Fq 'resolved_commit: 63b04e2530f5c7b41ea83c133daab24f34912456' "$lock"
  grep -Fq 'content_hash: sha256:eaf9d73a3348cbda6774b1a8268645c17f4d8cf5b5231743d2c44d71212cd755' "$lock"
  grep -Fq 'virtual_path: .agents/skills/impeccable' "$lock"
  grep -Fq '.agents/skills/impeccable/scripts/hook.mjs' "$lock"
  grep -Fq '.claude/skills/impeccable/scripts/hook.mjs' "$lock"
  ! grep -Fq 'virtual_path: skills/frontend-design' "$lock"
}

@test "Impeccable 4.1.2 record documents native Codex Stop and silent convergence" {
  local adr="$PROJECT_ROOT/docs/adr/0045-separate-llm-agents-and-apm-update-units.md"
  local runtimes="$PROJECT_ROOT/runtime/ai-runtimes.md"
  local harness="$PROJECT_ROOT/runtime/skill-harness.md"

  grep -Fq '63b04e2530f5c7b41ea83c133daab24f34912456' "$adr"
  grep -Fq 'eaf9d73a3348cbda6774b1a8268645c17f4d8cf5b5231743d2c44d71212cd755' "$adr"
  grep -Fq 'top-level `decision` / `reason`' "$runtimes"
  grep -Fq '次回の `Stop` は無言' "$harness"
  grep -Fq '4.1.2' "$harness"
}

@test "APM pins the official Matt Pocock v1.2.3 full set" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="6654f6b60cd9d5be8b54c6fafe44346dabeb3b76"
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
  local manifest_pins
  local lock_refs

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#457c381def89ce6213a171238f92eea63e9eaeb2' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#7a3d0ca45d2f6a00bf35cb3c525734a36d55a834' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"

  grep -Fq 'resolved_commit: 457c381def89ce6213a171238f92eea63e9eaeb2' "$lock"
  grep -Fq 'content_hash: sha256:07775fbfaed98fcf50795256434f646da296311bc10dd54f2de29075eca9095b' "$lock"
  grep -Fq 'resolved_commit: 7a3d0ca45d2f6a00bf35cb3c525734a36d55a834' "$lock"
  grep -Fq 'content_hash: sha256:2493dc60c3917d2e1153cd60d9e4df771b2775f64f3e17cbb1c2f1d011f888f3' "$lock"
  grep -Fq 'resolved_commit: 683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$lock"
  grep -Fq 'content_hash: sha256:8b8c1296ad947a237b32c21857837357f29197c53722131758777c80d26ed1ad' "$lock"
  [ "$(grep -Fc 'resolved_commit: 026389a3bc03da03ca2d65295e805493712b0774' "$lock")" -eq 2 ]
  grep -Fq 'content_hash: sha256:afe48be623c1f6190ade7dacc4c1d334d4150b503ed00b28dda23a499e5bdc30' "$lock"
  grep -Fq 'content_hash: sha256:b5c364878fb07d21a369f091f2e96b823da94308b15b39636f2585d8b5621b51' "$lock"
  [ "$(grep -Fc 'resolved_commit: 5ca747dad0d0583f4a1ac91c2655b345ba6c07eb' "$lock")" -eq 1 ]
  grep -Fq 'content_hash: sha256:cca6a9098e0dff08ce6fef999da77d98e94255e826b8b9f8132749b5da66dad2' "$lock"
  manifest_pins="$(
    sed -nE 's/^[[:space:]]*-[[:space:]]+([^#[:space:]]+)#([0-9a-f]{40})[[:space:]]*$/\1 \2/p' "$manifest" |
      awk '{
        count = split($1, parts, "/")
        repo = tolower(parts[1] "/" parts[2])
        path = ""
        for (i = 3; i <= count; i++) {
          path = path (path == "" ? "" : "/") parts[i]
        }
        print repo "|" path "|" $2
      }' |
      LC_ALL=C sort
  )"
  lock_refs="$(
    awk '
      function emit() {
        if (ref != "") print tolower(repo) "|" path "|" ref
      }
      /^- repo_url: / {
        emit()
        repo = $3
        path = ""
        ref = ""
        next
      }
      /^  virtual_path: / { path = $2; next }
      /^  resolved_ref: / { ref = $2; next }
      END { emit() }
    ' "$lock" | LC_ALL=C sort
  )"
  [ "$lock_refs" = "$manifest_pins" ]
  ! grep -Fq 'resolved_commit: 0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$lock"
  ! grep -Fq 'resolved_commit: 25be24cca34d06eed29a4779c3f48c4816aa812c' "$lock"
  # find-skills is unpinned; vercel-labs/skills main has since genuinely reached
  # 435076e7 (verified via `git ls-remote`), so it no longer denotes a rejected
  # candidate and is not asserted against here.
}

@test "APM install is gated on a successful nix-devshell snapshot refresh" {
  local script="$PROJECT_ROOT/run_onchange_after_apm-install.sh.tmpl"
  local refresh_line
  local install_line

  grep -q 'NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache' "$script"
  refresh_line="$(grep -n 'NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache' "$script" | cut -d: -f1)"
  install_line="$(grep -n '^apm install --frozen --target claude,codex --https$' "$script" | cut -d: -f1)"
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
  grep -Fq 'resolved_commit: 7a3d0ca45d2f6a00bf35cb3c525734a36d55a834' <<<"$remotion_entry"
  grep -Fq 'content_hash: sha256:2493dc60c3917d2e1153cd60d9e4df771b2775f64f3e17cbb1c2f1d011f888f3' <<<"$remotion_entry"
}

@test "APM refresh record distinguishes payload changes from revision-only movement" {
  local adr="$PROJECT_ROOT/docs/adr/0045-separate-llm-agents-and-apm-update-units.md"
  local runtimes="$PROJECT_ROOT/runtime/ai-runtimes.md"
  local harness="$PROJECT_ROOT/runtime/skill-harness.md"

  grep -Fq '457c381def89ce6213a171238f92eea63e9eaeb2' "$adr"
  grep -Fq '07775fbfaed98fcf50795256434f646da296311bc10dd54f2de29075eca9095b' "$adr"
  grep -Fq '7a3d0ca45d2f6a00bf35cb3c525734a36d55a834' "$adr"
  grep -Fq '2493dc60c3917d2e1153cd60d9e4df771b2775f64f3e17cbb1c2f1d011f888f3' "$adr"
  grep -Fq '683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$adr"
  grep -Fq '9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$adr"
  grep -Fq '026389a3bc03da03ca2d65295e805493712b0774' "$adr"
  grep -Fq '29186c40a47bf6c25d9fbf73d15ebba4dc9575be7242f381ddaeac82ed24e6c4' "$adr"
  grep -Fq 'revision-only' "$runtimes"
  grep -Fq 'd43138a744099027b61ad50150b4a36246f747214d23761c9f970b3a38d03720' "$harness"
  grep -Fq '29186c40a47bf6c25d9fbf73d15ebba4dc9575be7242f381ddaeac82ed24e6c4' "$harness"
}

@test "APM runtime deploy targets remain git-ignored" {
  grep -q '^/\.agents/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/agents/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/commands/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/hooks/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/skills/$' "$PROJECT_ROOT/.gitignore"
  grep -q '^/\.claude/apm-hooks\.json$' "$PROJECT_ROOT/.gitignore"
}

@test "APM install reproduces the lock generation layout from HOME" {
  local script="$PROJECT_ROOT/run_onchange_after_apm-install.sh.tmpl"

  grep -q '^cd "\$HOME"$' "$script"
  grep -q '^apm install --frozen --target claude,codex --https$' "$script"
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
