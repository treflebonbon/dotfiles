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

assert_lock_entry() {
  local lock="$1"
  local repo="$2"
  local name="$3"
  local commit="$4"
  local content_hash="$5"
  local entry

  entry="$(extract_lock_entry "$lock" "$repo" "$name")"

  [ -n "$entry" ]
  grep -Fq "resolved_commit: $commit" <<<"$entry"
  grep -Fq "content_hash: $content_hash" <<<"$entry"
}

@test "APM selects validated Impeccable and retains specialist UI skills" {
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -Fq 'pbakaus/impeccable/.agents/skills/impeccable#6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/frontend-design' "$manifest"

  local skill
  for skill in web-design-guidelines react-best-practices composition-patterns react-view-transitions shadcn remotion-best-practices modern-web-guidance; do
    grep -Fq "$skill" "$manifest"
  done
}

@test "APM lock materializes the validated Impeccable payload" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'apm_version: 0.33.0' "$lock"
  grep -Fq 'repo_url: pbakaus/impeccable' "$lock"
  grep -Fq 'resolved_commit: 6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e' "$lock"
  grep -Fq 'content_hash: sha256:c9ab9faf1852606e1fdbf21eba87e294eae632cad530785460caf05bf0b0b83a' "$lock"
  grep -Fq 'virtual_path: .agents/skills/impeccable' "$lock"
  grep -Fq '.agents/skills/impeccable/scripts/impeccable' "$lock"
  grep -Fq '.claude/skills/impeccable/scripts/impeccable' "$lock"
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

@test "APM pins the official Matt Pocock full set" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="24fe0ef7737efae15c87225755e9f6f5965e4888"
  local skill

  grep -Fq "mattpocock/skills#$revision" "$manifest"
  [ "$(grep -Fc "mattpocock/skills/skills/" "$manifest")" -eq 0 ]
  [ "$(grep -Fc "#$revision" "$manifest")" -eq 1 ]
  [ "$(grep -Fc "resolved_commit: $revision" "$lock")" -eq 1 ]
  grep -Fq 'name: mattpocock-skills' "$lock"
  assert_lock_entry "$lock" 'mattpocock/skills' 'mattpocock-skills' \
    "$revision" \
    'sha256:127ccf2bbbf1442907b12581be5aba13ed034344e290714172f0a4a1b72942f8'
  for skill in \
    ask-matt diagnosing-bugs grill-with-docs triage improve-codebase-architecture \
    setup-matt-pocock-skills tdd to-spec to-tickets wayfinder implement implement-spec pr retro prototype \
    research domain-modeling codebase-design code-review \
    wizard grill-me grilling handoff teach to-questionnaire wait-what writing-for-agents; do
    grep -Fq "  - .agents/skills/$skill" "$lock"
    grep -Fq "  - .claude/skills/$skill" "$lock"
  done
  ! grep -Fq 'skills/resolving-merge-conflicts' "$lock"
  ! grep -Fq 'writing-great-skills' "$manifest"
  ! grep -Fq 'writing-great-skills' "$lock"
}

@test "APM advances validated selected payloads and floating revision-only updates" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local manifest_pins
  local lock_refs

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#84ae7251ee919239d5ea85aef25897983f26601e' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#0b5db9daae40f42c73544d1cc0a8c733bd530eaa' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#aedb9305cd1b3de859b5eafc1ee0d77fa0df8963' "$manifest"
  grep -Fq 'herdrdev/herdr/skills/herdr#7b116c05bfda646af39d2524c54e70c751f57ee8' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"

  assert_lock_entry "$lock" 'googlechrome/modern-web-guidance' 'modern-web-guidance' \
    '84ae7251ee919239d5ea85aef25897983f26601e' \
    'sha256:8cbb78a90b883129adf34ce85582d1fa708da25944e078732bb01ad494426ea5'
  assert_lock_entry "$lock" 'anthropics/skills' 'pdf' \
    '8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4' \
    'sha256:69e2ac9eb2bbe2881df26acc53b46b39a15cfda206f5357e5f9c83feb0fadcc7'
  assert_lock_entry "$lock" 'anthropics/skills' 'skill-creator' \
    '8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4' \
    'sha256:b2bfe91d69ca99994c0566baede889e7d2b9bb8791c6b6106c5d387392f717f6'
  assert_lock_entry "$lock" 'remotion-dev/skills' 'remotion-best-practices' \
    '0b5db9daae40f42c73544d1cc0a8c733bd530eaa' \
    'sha256:388cfb613be8f0af31c501327f77dd6a16bce51ac1bb583d5e652278900b63d8'
  assert_lock_entry "$lock" 'shadcn-ui/ui' 'shadcn' \
    '295a1f114a138f23b5dfee0e0c6812394dfeb90c' \
    'sha256:bfc2cdcbe8ca341e90d398f9f65eed5e7cd9d147c376554cfcb0d703e7872c41'
  assert_lock_entry "$lock" 'stablyai/orca' 'computer-use' \
    'd9846e64feaed910b058c4128eb4d46ed8e2c4c8' \
    'sha256:1130dcb48ca8c1cf00e1c15242e95f0141cad5299b9fc2ebbcd2779c8c2f3194'
  assert_lock_entry "$lock" 'stablyai/orca' 'orca-cli' \
    'aedb9305cd1b3de859b5eafc1ee0d77fa0df8963' \
    'sha256:ccd717aed7b9866a059b0b31d9a009641a28f6db3201749943fbbb797af4a317'
  assert_lock_entry "$lock" 'herdrdev/herdr' 'herdr' \
    '7b116c05bfda646af39d2524c54e70c751f57ee8' \
    'sha256:66715d76e5947497431ec0db32f2693b9c916ad799c3f32b99e6174b4b9c607f'
  assert_lock_entry "$lock" 'stablyai/orca' 'orchestration' \
    'd9846e64feaed910b058c4128eb4d46ed8e2c4c8' \
    'sha256:0dc04a0a354974eed5c15115fc6cb7461d7423e95a5b19ee995796cf1383e7ed'
  [ "$(grep -Fc 'resolved_commit: aedb9305cd1b3de859b5eafc1ee0d77fa0df8963' "$lock")" -eq 1 ]
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
