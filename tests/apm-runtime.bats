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
  grep -Eq "^  resolved_commit: $commit$" <<<"$entry"
  grep -Fq "content_hash: $content_hash" <<<"$entry"
}

@test "APM selects validated Impeccable and retains specialist UI skills" {
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -Fq 'pbakaus/impeccable/.agents/skills/impeccable#414603bf14c7a344edb466bb1f85690c77ce8b7d' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/frontend-design' "$manifest"

  local skill
  for skill in web-design-guidelines react-best-practices composition-patterns react-view-transitions shadcn remotion-best-practices modern-web-guidance; do
    grep -Fq "$skill" "$manifest"
  done
}

@test "APM lock materializes the validated Impeccable payload" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"

  grep -Fq 'apm_version: 0.35.0' "$lock"
  grep -Fq 'repo_url: pbakaus/impeccable' "$lock"
  grep -Fq 'resolved_commit: 414603bf14c7a344edb466bb1f85690c77ce8b7d' "$lock"
  grep -Fq 'content_hash: sha256:d3b31fcb1df5d1c7b9e1bbfe89e0c34263c98c21765bc2a833082f225b1b4b7c' "$lock"
  grep -Fq 'virtual_path: .agents/skills/impeccable' "$lock"
  grep -Fq '.agents/skills/impeccable/scripts/impeccable' "$lock"
  grep -Fq '.claude/skills/impeccable/scripts/impeccable' "$lock"
  ! grep -Fq 'virtual_path: skills/frontend-design' "$lock"
}

@test "APM pins the official Matt Pocock full set" {
  local manifest="$PROJECT_ROOT/apm.yml"
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local revision="a496f5513d4a4cf889bc48e189e579f4b0bdf6aa"
  local skill

  grep -Fq "mattpocock/skills#$revision" "$manifest"
  [ "$(grep -Fc "mattpocock/skills/skills/" "$manifest")" -eq 0 ]
  [ "$(grep -Fc "#$revision" "$manifest")" -eq 1 ]
  [ "$(grep -Fc "resolved_commit: $revision" "$lock")" -eq 1 ]
  grep -Fq 'name: mattpocock-skills' "$lock"
  assert_lock_entry "$lock" 'mattpocock/skills' 'mattpocock-skills' \
    "$revision" \
    'sha256:d2c8efe424482ed9b171ed5f61a3315bf7fca87ee88184a0d164477e956ddd45'
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

  # floating の revision は形式を検査し、受け入れた payload は content hash で固定する。

  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#4f2b13e25c5815b3f080ca0d983e828d96561a0f' "$manifest"
  grep -Fq 'remotion-dev/skills/skills/remotion-best-practices#30d4553ecd46fbc5212fd0ff006ae43af522158b' "$manifest"
  grep -Fq 'stablyai/orca/skills/orca-cli#eb3379ff9909f2856113e9cfdc5223c754f5ffe2' "$manifest"
  grep -Fq 'herdrdev/herdr/skills/herdr#2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' "$manifest"
  ! grep -Fq 'anthropics/skills/skills/pdf#0a64e398ec6bb34a494f0c347e8ccae53a862f8e' "$manifest"
  ! grep -Fq 'shadcn-ui/ui/skills/shadcn#683a5a9b370acdb7785a0529434e6a3b8c7e0441' "$manifest"
  ! grep -Fq 'vercel-labs/skills/skills/find-skills#435076e78988e1e6ec40d00b0b1d76bdbbc5419a' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/computer-use#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"
  ! grep -Fq 'stablyai/orca/skills/orchestration#9c01e09ecc9d3c1203968ace9945d16edfb35dd2' "$manifest"

  assert_lock_entry "$lock" 'googlechrome/modern-web-guidance' 'modern-web-guidance' \
    '4f2b13e25c5815b3f080ca0d983e828d96561a0f' \
    'sha256:4132180012a70c5552d55cf5b3a4be8ba571da5c60b7acfc4d8c06c027210008'
  assert_lock_entry "$lock" 'anthropics/skills' 'pdf' \
    '[0-9a-f]{40}' \
    'sha256:69e2ac9eb2bbe2881df26acc53b46b39a15cfda206f5357e5f9c83feb0fadcc7'
  assert_lock_entry "$lock" 'anthropics/skills' 'skill-creator' \
    '[0-9a-f]{40}' \
    'sha256:b2bfe91d69ca99994c0566baede889e7d2b9bb8791c6b6106c5d387392f717f6'
  assert_lock_entry "$lock" 'remotion-dev/skills' 'remotion-best-practices' \
    '30d4553ecd46fbc5212fd0ff006ae43af522158b' \
    'sha256:8c28a53f8d0f70ad6fec905e0216364bd78a47cb86432aa5dd725af5120f7070'
  assert_lock_entry "$lock" 'shadcn-ui/ui' 'shadcn' \
    '[0-9a-f]{40}' \
    'sha256:e976181d1ffe560455eb3c7bd83cec5f111a23b32128c20718fd0db6e071fb2d'
  assert_lock_entry "$lock" 'stablyai/orca' 'computer-use' \
    '[0-9a-f]{40}' \
    'sha256:1130dcb48ca8c1cf00e1c15242e95f0141cad5299b9fc2ebbcd2779c8c2f3194'
  assert_lock_entry "$lock" 'stablyai/orca' 'orca-cli' \
    'eb3379ff9909f2856113e9cfdc5223c754f5ffe2' \
    'sha256:71d6a385d1c691e3062e9b448a3bf0447797a759fbb48cac58551d3a22c564a2'
  assert_lock_entry "$lock" 'herdrdev/herdr' 'herdr' \
    '2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' \
    'sha256:72177e911f55467de8737174072ec6bb08e30bbf62bceabcb69678e944398b18'
  assert_lock_entry "$lock" 'stablyai/orca' 'orchestration' \
    '[0-9a-f]{40}' \
    'sha256:591831560700d73c2bc1ca6658dddb6e91f1b52264d116e8ab9095ec3a80bdf0'
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

@test "APM locks stable Effect and React View Transition compatibility payloads" {
  local lock="$PROJECT_ROOT/apm.lock.yaml"
  local effect_entry
  local view_transition_entry

  effect_entry="$(extract_lock_entry "$lock" 'effect-ts/skills' 'effect-ts')"
  view_transition_entry="$(extract_lock_entry "$lock" 'vercel-labs/agent-skills' 'vercel-react-view-transitions')"

  grep -Eq '^  resolved_commit: [0-9a-f]{40}$' <<<"$effect_entry"
  grep -Fq '.agents/skills/effect-ts/SKILL.md: sha256:30acc24da779cb4e530732bc74cca172adb372f24f42f2d1af18370c27938bff' <<<"$effect_entry"
  grep -Fq '.claude/skills/effect-ts/SKILL.md: sha256:30acc24da779cb4e530732bc74cca172adb372f24f42f2d1af18370c27938bff' <<<"$effect_entry"
  grep -Fq 'content_hash: sha256:cb225ba5dda169883dfee680fba6c570c89245ba19242a9bc5c3f2ac8218a55f' <<<"$effect_entry"

  grep -Eq '^  resolved_commit: [0-9a-f]{40}$' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/references/nextjs.md' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/references/troubleshooting.md' <<<"$view_transition_entry"
  grep -Fq '.agents/skills/react-view-transitions/SKILL.md: sha256:693acbddd1d2dcf774286867efbc9a5c09dce2da6f21f8e12618187a92f2106a' <<<"$view_transition_entry"
  grep -Fq '.claude/skills/react-view-transitions/SKILL.md: sha256:693acbddd1d2dcf774286867efbc9a5c09dce2da6f21f8e12618187a92f2106a' <<<"$view_transition_entry"
  grep -Fq 'content_hash: sha256:ead0425aadb0b73f1d11ef77204d0d12491a5d6c03debb52366e4c289f46a8e2' <<<"$view_transition_entry"
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

prepare_lock_generation() {
  GENERATOR="$PROJECT_ROOT/scripts/generate-apm-lock.sh"
  GENERATION_LOG="$BATS_TEST_TMPDIR/generation.log"
  GENERATION_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$GENERATION_BIN" "$BATS_TEST_TMPDIR/runtime"
  if [[ ${1:-} != real-nix ]]; then
    cat >"$GENERATION_BIN/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${APM_TEST_SNAPSHOT_VERSION-0.35.0}"
exit "${APM_TEST_NIX_STATUS:-0}"
EOF
  fi
  cat >"$GENERATION_BIN/apm" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == --version ]]; then
  [[ -z ${PYTHONPATH:-} ]] || { printf 'Agent Package Manager (APM) CLI version 0.33.0\n'; exit 0; }
  printf '%s\n' "${APM_TEST_CLI_OUTPUT-Agent Package Manager (APM) CLI version 0.35.0}"
  exit "${APM_TEST_CLI_STATUS:-0}"
fi
printf '%s\n' "$*" >>"$APM_TEST_LOG"
printf '%s\n' "${APM_TEST_LOCK-apm_version: 0.35.0}" >apm.lock.yaml
EOF
  chmod +x "$GENERATION_BIN"/*
  cd "$BATS_TEST_TMPDIR/runtime"
  printf 'name: candidate\n' >apm.yml
  export APM_TEST_LOG="$GENERATION_LOG"
  export PATH="$GENERATION_BIN:$PATH"
}

@test "APM candidate generation validates a new lock independently of the old lock version" {
  prepare_lock_generation
  printf 'apm_version: 0.32.0\n' >apm.lock.yaml

  run "$GENERATOR" "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$(cat apm.lock.yaml)" = 'apm_version: 0.35.0' ]
  [ "$(cat "$GENERATION_LOG")" = 'install --target claude,codex --https' ]
}

@test "APM candidate generation ignores an inherited PYTHONPATH that would load a stale apm_cli" {
  prepare_lock_generation

  run env PYTHONPATH=/stale "$GENERATOR" "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
}

@test "APM candidate generation rejects existing deployment paths without changing the lock" {
  prepare_lock_generation
  local runtime="$PWD" path kind
  for path in .agents/skills .claude/skills; do
    for kind in populated empty file symlink; do
      mkdir -p "$runtime/$path-$kind"
      cd "$runtime/$path-$kind"
      printf 'name: candidate\n' >apm.yml
      printf 'apm_version: 0.32.0\n' >apm.lock.yaml
      mkdir -p "$(dirname "$path")"
      case "$kind" in
      populated)
        mkdir -p "$path"
        printf 'retained skill\n' >"$path/SKILL.md"
        ;;
      empty) mkdir -p "$path" ;;
      file) printf 'retained path\n' >"$path" ;;
      symlink) ln -s missing-deployment "$path" ;;
      esac

      run "$GENERATOR" "$PROJECT_ROOT"

      [ "$status" -ne 0 ]
      [[ "$output" == *"$path"* ]]
      [ ! -e "$GENERATION_LOG" ]
      [ "$(cat apm.lock.yaml)" = 'apm_version: 0.32.0' ]
    done
  done
  for path in .agents .claude; do
    mkdir -p "$runtime/parent-$path/external"
    cd "$runtime/parent-$path"
    printf 'name: candidate\n' >apm.yml
    printf 'apm_version: 0.32.0\n' >apm.lock.yaml
    ln -s external "$path"

    run "$GENERATOR" "$PROJECT_ROOT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"$path"* ]]
    [ ! -e "$GENERATION_LOG" ]
    [ ! -e external/skills ]
    [ "$(cat apm.lock.yaml)" = 'apm_version: 0.32.0' ]
  done
}

@test "APM candidate generation rejects missing, malformed, and incorrect CLI versions before install" {
  prepare_lock_generation
  local banner
  for banner in '' '0.35.0' 'Agent Package Manager (APM) CLI version 0.32.0'; do
    run env APM_TEST_CLI_OUTPUT="$banner" "$GENERATOR" "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *'APM CLI'* ]]
    [ ! -e "$GENERATION_LOG" ]
  done

  run env APM_TEST_CLI_STATUS=1 "$GENERATOR" "$PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [ ! -e "$GENERATION_LOG" ]
}

@test "APM candidate generation rejects unknown snapshot metadata before install" {
  prepare_lock_generation
  local version
  for version in '' unknown; do
    run env APM_TEST_SNAPSHOT_VERSION="$version" "$GENERATOR" "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Nix snapshot'* ]]
    [ ! -e "$GENERATION_LOG" ]
  done

  run env APM_TEST_NIX_STATUS=1 "$GENERATOR" "$PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [ ! -e "$GENERATION_LOG" ]
}

@test "APM candidate generation rejects missing, malformed, duplicate, and incorrect lock versions" {
  prepare_lock_generation
  local lock
  for lock in 'lockfile_version: 1' 'apm_version: unknown' 'apm_version: 0.32.0' \
    $'apm_version: 0.35.0\napm_version: 0.35.0'; do
    run env APM_TEST_LOCK="$lock" "$GENERATOR" "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *'生成lockのAPM版'* ]]
    [ "$(cat apm.lock.yaml)" = "$lock" ]
  done
}

@test "APM candidate generation obtains the expected version from the selected Nix package" {
  prepare_lock_generation real-nix

  run "$GENERATOR" "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$(cat "$GENERATION_LOG")" = 'install --target claude,codex --https' ]
}

@test "APM candidate generation rejects a runtime inside the source before install" {
  prepare_lock_generation
  local source="$BATS_TEST_TMPDIR/source"
  mkdir -p "$source/runtime"
  cd "$source/runtime"
  printf 'name: candidate\n' >apm.yml

  run "$GENERATOR" "$source"

  [ "$status" -ne 0 ]
  [ ! -e "$GENERATION_LOG" ]
}
