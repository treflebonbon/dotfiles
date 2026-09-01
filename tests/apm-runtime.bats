#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

extract_lock_entry() {
  local lock="$1"
  local target_repo="$2"
  local target_name="$3"

  awk -v target_repo="$target_repo" -v target_name="$target_name" '
    /^- repo_url: / {
      if (selected) exit
      repo = $3
      block = $0 ORS
      next
    }
    { block = block $0 ORS }
    /^  name: / {
      if (repo == target_repo && $2 == target_name) selected = 1
    }
    END {
      if (selected) printf "%s", block
    }
  ' "$lock"
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

  grep -Fq 'apm_version: 0.29.0' "$lock"
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

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#56c61c9ee79a8df1a98822309c04847a57f56000' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#357a270803b23e16b32bec65df07c41a62e94bd9' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#b44ef1e59db4399cbd3a0615d29345de601885e7' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"

  grep -Fq 'resolved_commit: 56c61c9ee79a8df1a98822309c04847a57f56000' "$lock"
  grep -Fq 'content_hash: sha256:cc46430506cf1b6fe0facf191ac30e6cacaa2e0ee4237361bb445ed17c5b9908' "$lock"
  grep -Fq 'resolved_commit: 357a270803b23e16b32bec65df07c41a62e94bd9' "$lock"
  grep -Fq 'content_hash: sha256:3ebdb1c3e503732103a92bba9611685e9e15812adb9b25c3a734ee8d3c228aeb' "$lock"
  grep -Fq 'resolved_commit: 63c1308d112b6b1205d86244a156cca1abef5087' "$lock"
  grep -Fq 'content_hash: sha256:b82236022a12b00cfc80621d5de272e62ce597fb38f496d0a4a586ff954e6ae7' "$lock"
  [ "$(grep -Fc 'resolved_commit: 41ef1ddd80d69795749451116fe70568a3779ca9' "$lock")" -eq 2 ]
  grep -Fq 'content_hash: sha256:eaa770000cf2e806485dc142c815580de3c6df4dfdd0afc792c79498aa93cfec' "$lock"
  grep -Fq 'content_hash: sha256:e611e8065f08f308823d063bb3cd8d4e283242202456b8a3e80058b2f59f0c3a' "$lock"
  [ "$(grep -Fc 'resolved_commit: b44ef1e59db4399cbd3a0615d29345de601885e7' "$lock")" -eq 1 ]
  grep -Fq 'content_hash: sha256:83ece910d035d0684195095bb9df5911a028002b2efba1ebbeb4ae66de5e0903' "$lock"
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

@test "APM locks Effect RC and React View Transition compatibility payloads" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local effect_entry
  local view_transition_entry

  effect_entry="$(extract_lock_entry "$lock" 'effect-ts/skills' 'effect-ts')"
  view_transition_entry="$(extract_lock_entry "$lock" 'vercel-labs/agent-skills' 'vercel-react-view-transitions')"

  grep -Fq 'resolved_commit: 2309e6f27d9955b434c0e3f394b945c136e89fd2' <<<"$effect_entry"
  grep -Fq '.agents/skills/effect-ts/SKILL.md: sha256:509ed4e10def32dc3f6b20854c9ae50a56b7dc525a14a02ab9871eef53a2052e' <<<"$effect_entry"
  grep -Fq '.claude/skills/effect-ts/SKILL.md: sha256:509ed4e10def32dc3f6b20854c9ae50a56b7dc525a14a02ab9871eef53a2052e' <<<"$effect_entry"
  grep -Fq 'content_hash: sha256:6bdb9b95aa83071eca2f67ae947b7d398a22e9e6e08f6cfa35de9516b03efa6e' <<<"$effect_entry"

  grep -Fq 'resolved_commit: 063bee94c3f4df8453406c830b0a7df0f2860278' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/references/nextjs.md' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/references/troubleshooting.md' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/SKILL.md: sha256:1520343c8814c972fee001cac6d6185976d6eb3f4edcac33afe95c10f3b3228b' <<<"$view_transition_entry"
  grep -Fq '.claude/skills/react-view-transitions/SKILL.md: sha256:1520343c8814c972fee001cac6d6185976d6eb3f4edcac33afe95c10f3b3228b' <<<"$view_transition_entry"
  grep -Fq 'content_hash: sha256:0d0012537fe7619026f0a844fe505958beb2d525afb8f854ac7217798a2785e2' <<<"$view_transition_entry"
}

@test "APM 0.29 refresh record documents compatibility gates and isolated adoption" {
  local record="$PROJECT_ROOT/docs/research/llm-agents-and-apm-update-2026-09-01-after-pr-202.md"
  local harness="$PROJECT_ROOT/runtime/skill-harness.md"

  grep -Fq '## Issue #205 実装結果' "$record"
  grep -Fq 'd343147e73c22f76eb0ccbb4a22838987fa29cd6857cd51c8d4002f3fc0e4369' "$record"
  grep -Fq 'Effect-TS compatibility' "$record"
  grep -Fq 'React View Transitions compatibility' "$record"
  grep -Fq 'STARTED_NO_PLAN' "$record"
  grep -Fq 'CONTINUED_SAME_SESSION_NO_PLAN' "$record"
  grep -Fq 'live HOME非変更' "$record"
  grep -Fq 'APM 0.29.0の隔離cwd/HOME' "$harness"
  grep -Fq 'Claude/Codex 42/42 discovery' "$harness"
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

  remotion_entry="$(extract_lock_entry "$lock" 'remotion-dev/skills' 'remotion-best-practices')"

  [ -n "$remotion_entry" ]
  grep -Fq 'resolved_commit: 357a270803b23e16b32bec65df07c41a62e94bd9' <<<"$remotion_entry"
  grep -Fq 'content_hash: sha256:3ebdb1c3e503732103a92bba9611685e9e15812adb9b25c3a734ee8d3c228aeb' <<<"$remotion_entry"
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
