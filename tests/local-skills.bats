#!/usr/bin/env bats

load local-skills-helper

setup() {
  setup_local_skills_fixture
}

@test "PR screenshots deploys to both hubs while to-pr stays retired" {
  for _ in 1 2; do
    run run_skill_phase before_remove-orphan-claude-skills
    [ "$status" -eq 0 ]
    run run_skill_phase after_deploy-local-skills
    [ "$status" -eq 0 ]
  done
  local dir
  for dir in .agents .claude; do
    cmp "$SKILL_SOURCE/local-skills/pr-screenshots/SKILL.md" "$SKILL_HOME/$dir/skills/pr-screenshots/SKILL.md"
    [ ! -e "$SKILL_HOME/$dir/skills/to-pr" ]
  done
  [ ! -e "$SKILL_HOME/.codex/skills/pr-screenshots" ]
}

@test "standard workflow migration retires local skills and the removed upstream skill without redeployment" {
  setup_skill_apply
  mkdir -p "$SKILL_HOME/.codex-app/skills" "$SKILL_HOME/.agents/skills/user-owned"
  local dir skill root
  local retired=(
    batch-implement
    to-pr
    harness-feedback
    dogfood-to-issues
    mvp-mediator-architecture
    to-worktree
    rop-visualizer
    resolving-merge-conflicts
  )
  for root in "$SKILL_HOME/.gemini/skills" "$SKILL_HOME/.copilot/skills"; do
    mkdir -p "$root/resolving-merge-conflicts"
    printf 'independent skill\n' >"$root/resolving-merge-conflicts/SKILL.md"
  done
  for dir in .agents .claude .codex .codex-app; do
    for skill in "${retired[@]}"; do
      mkdir -p "$SKILL_HOME/$dir/skills/$skill"
      printf 'old managed payload\n' >"$SKILL_HOME/$dir/skills/$skill/SKILL.md"
    done
  done
  for _ in 1 2; do
    run skill_chezmoi apply
    [ "$status" -eq 0 ]
    for dir in .agents .claude .codex .codex-app; do
      for skill in "${retired[@]}"; do
        [ ! -e "$SKILL_HOME/$dir/skills/$skill" ]
      done
    done
    [ -d "$SKILL_HOME/.agents/skills/user-owned" ]
    [ -f "$SKILL_HOME/.claude/skills/pdf/SKILL.md" ]
    for dir in .agents .claude; do
      cmp "$SKILL_SOURCE/local-skills/dogfood/SKILL.md" "$SKILL_HOME/$dir/skills/dogfood/SKILL.md"
    done
    for root in "$SKILL_HOME/.gemini/skills" "$SKILL_HOME/.copilot/skills"; do
      grep -Fxq 'independent skill' "$root/resolving-merge-conflicts/SKILL.md"
    done
  done
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

@test "local apply detects symlink changes without GNU find or sha256sum" {
  setup_skill_apply
  export SKILL_REAL_FIND="$(command -v find)"
  cat >"$BATS_TEST_TMPDIR/bin/find" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = -printf ]; then
    echo 'find: -printf: unknown primary or operator' >&2
    exit 1
  fi
done
exec "$SKILL_REAL_FIND" "$@"
EOF
  printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/sha256sum"
  chmod +x "$BATS_TEST_TMPDIR/bin/find" "$BATS_TEST_TMPDIR/bin/sha256sum"
  add_local_skill sample-skill
  printf 'first asset\n' >"$SKILL_SOURCE/local-skills/sample-skill/first asset.txt"
  printf 'second asset\n' >"$SKILL_SOURCE/local-skills/sample-skill/second asset.txt"
  ln -s 'first asset.txt' "$SKILL_SOURCE/local-skills/sample-skill/linked.txt"

  run skill_chezmoi init --apply
  [ "$status" -eq 0 ]
  [ "$(cat "$SKILL_HOME/.agents/skills/sample-skill/linked.txt")" = 'first asset' ]
  ln -sfn 'second asset.txt' "$SKILL_SOURCE/local-skills/sample-skill/linked.txt"
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  local dir
  for dir in .agents .claude; do
    [ "$(cat "$SKILL_HOME/$dir/skills/sample-skill/linked.txt")" = 'second asset' ]
    [ ! -L "$SKILL_HOME/$dir/skills/sample-skill/linked.txt" ]
  done
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 2 ]
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

@test "an unavailable APM after cleanup fails apply and retries when APM returns" {
  setup_skill_apply
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  add_local_skill sample-retry
  cat >"$BATS_TEST_TMPDIR/apm-unavailable.bash" <<'EOF'
command() {
  if [ "$#" -eq 2 ] && [ "$1" = -v ] && [ "$2" = apm ]; then
    return 1
  fi
  builtin command "$@"
}
EOF
  export BASH_ENV="$BATS_TEST_TMPDIR/apm-unavailable.bash"
  run skill_chezmoi apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"apm CLI"* ]]
  [ ! -e "$SKILL_HOME/.claude/skills/pdf" ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 2 ]

  unset BASH_ENV
  run skill_chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(cat "$SKILL_HOME/.claude/skills/pdf/SKILL.md")" = 'APM payload' ]
  [ "$(wc -l <"$SKILL_APM_LOG")" -eq 4 ]
  cmp "$SKILL_SOURCE/local-skills/sample-retry/SKILL.md" "$SKILL_HOME/.claude/skills/sample-retry/SKILL.md"
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
  for name in dogfood grilling ../outside; do
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
    [ ! -e "$SKILL_HOME/.agents/skills/dogfood" ]
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

@test "a local skill reusing a retired APM name is preserved only in its current targets" {
  add_local_skill autofix
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]
  mkdir -p "$SKILL_HOME/.codex/skills/autofix" "$SKILL_HOME/.copilot/skills/autofix"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  local dir
  for dir in .agents .claude; do
    cmp "$SKILL_SOURCE/local-skills/autofix/SKILL.md" "$SKILL_HOME/$dir/skills/autofix/SKILL.md"
  done
  [ ! -e "$SKILL_HOME/.codex/skills/autofix" ]
  [ ! -e "$SKILL_HOME/.copilot/skills/autofix" ]
}

@test "herdr and orca architecture candidate skills deploy to both hubs under names APM does not own" {
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  run run_skill_phase after_deploy-local-skills
  [ "$status" -eq 0 ]

  local name dir skill ref
  for name in herdr orca; do
    skill="$SKILL_SOURCE/local-skills/$name-peer-refactor/SKILL.md"
    grep -q "^name: $name-peer-refactor$" "$skill"
    sed -n '/^description:/p' "$skill" | grep -Fq '/improve-codebase-architecture'
    run grep -Fq 'AUTO_PEER_SESSION' "$skill"
    [ "$status" -eq 1 ]
    grep -Fq 'autonomous-peer-contract.md' "$skill"
    for dir in .agents .claude; do
      cmp "$skill" "$SKILL_HOME/$dir/skills/$name-peer-refactor/SKILL.md"
      [ ! -e "$SKILL_HOME/.codex/skills/$name-peer-refactor" ]
      for ref in "references/$name.md" references/evidence.md scripts/run-evidence.py scripts/gh-once.sh scripts/candidate-record.py scripts/check-owned.sh \
        scripts/check-architecture-report.py scripts/check-architecture-render.js; do
        cmp "$SKILL_SOURCE/local-skills/$name-peer-refactor/$ref" \
          "$SKILL_HOME/$dir/skills/$name-peer-refactor/$ref"
      done
      if [ "$name" = herdr ]; then
        cmp "$SKILL_SOURCE/local-skills/herdr-peer-refactor/references/auto-session.md" \
          "$SKILL_HOME/$dir/skills/herdr-peer-refactor/references/auto-session.md"
      fi
    done
  done
  sed -n '/^description:/p' "$SKILL_SOURCE/local-skills/herdr-peer-refactor/SKILL.md" | grep -Fq 'Herdr'
  sed -n '/^description:/p' "$SKILL_SOURCE/local-skills/orca-peer-refactor/SKILL.md" | grep -Fq 'Orca'
  grep -Fq 'scripts/peer-request.sh' "$SKILL_SOURCE/local-skills/herdr-peer-refactor/references/herdr.md"
  grep -Fq 'references/auto-session.md' "$SKILL_SOURCE/local-skills/herdr-peer-refactor/SKILL.md"
  [ ! -e "$SKILL_SOURCE/local-skills/orca-peer-refactor/references/auto-session.md" ]
}

@test "the herdr and orca architecture candidate skills share identical common scripts and workflow sections" {
  local h="$BATS_TEST_DIRNAME/../local-skills/herdr-peer-refactor"
  local o="$BATS_TEST_DIRNAME/../local-skills/orca-peer-refactor"
  local script
  for script in run-evidence.py candidate-record.py check-owned.sh gh-once.sh check-architecture-report.py check-architecture-render.js; do
    cmp "$h/scripts/$script" "$o/scripts/$script"
  done
  cmp "$h/references/evidence.md" "$o/references/evidence.md"
  for section in '1\. 元の候補を固定' '3\. peer と設計' '4\. 実装と検証' '5\. 独立レビュー' '6\. PR と報告'; do
    cmp <(sed -n "/^## $section/,/^## [0-9]\\./p" "$h/SKILL.md") <(sed -n "/^## $section/,/^## [0-9]\\./p" "$o/SKILL.md")
  done
}

@test "the architecture report checker accepts Mermaid text references and rejects non-text content" {
  local checker="$BATS_TEST_DIRNAME/../local-skills/herdr-peer-refactor/scripts/check-architecture-report.py"
  local raw="$BATS_TEST_TMPDIR/raw.html"
  local invalid="$BATS_TEST_TMPDIR/invalid.html"
  local content
  printf '%s\n' '<pre class="mermaid">flowchart TD' '  A["&lt;label&gt;"] --> B' '</pre>' >"$raw"

  run python3 "$checker" "$raw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"expected_mermaid_diagrams": 1'* ]]
  [[ "$output" == *'"render_check": "not_performed"'* ]]

  for content in \
    '<code>flowchart TD</code>' \
    '<!-- comment -->flowchart TD' \
    '<!DOCTYPE html>flowchart TD' \
    '<?xml version="1.0"?>flowchart TD' \
    '<![CDATA[flowchart TD]]>'; do
    printf '%s\n' "<pre class=\"mermaid\">$content</pre>" >"$invalid"
    run python3 "$checker" "$invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *'Mermaid の <pre> 内に'* ]]
  done
}

@test "the architecture candidate override requires evidence and gates HTML report presentation" {
  local harness="$BATS_TEST_DIRNAME/../runtime/skill-harness.md"
  local override
  override="$(sed -n '/^外部 skill は APM 配布物を fork せず/,/^### Managed workflow semantics/p' "$harness")"
  grep -Fq 'caller 数は足切りにせず' <<<"$override"
  grep -Fq 'helper 整備・単なる移動だけの案は数合わせに採らない' <<<"$override"
  grep -Fq 'Top recommendation を「該当候補なし」とし、候補選択質問をせず' <<<"$override"
  grep -Fq 'peer 依頼が未承認のまま未選択' <<<"$override"
  grep -Fq '選択を委任された場合は peer が提示済み候補から選び、その元候補を pin' <<<"$override"
  grep -Fq 'favicon.ico の取得失敗だけは console error の例外' <<<"$override"
  grep -Fq 'Orca 内蔵 page は `orca-cli`' <<<"$override"
  grep -Fq '静的検査は実描画検査の代わりにならない' <<<"$override"
  grep -Fq 'Markdown artifact の従来経路は維持する' <<<"$override"
  local skill="$BATS_TEST_DIRNAME/../local-skills/herdr-peer-refactor/SKILL.md"
  local chapter
  chapter="$(sed -n '/^## 1\. 元の候補を固定$/,/^## 2\./p' "$skill")"
  grep -Fq 'Top recommendation は「該当候補なし」とし、候補選択質問をせず' <<<"$chapter"
  grep -Fq 'peer 依頼未承認で未選択なら pin しない' <<<"$chapter"
  grep -Fq 'peer 協働の明示依頼で選択を委任された場合は' <<<"$chapter"
  grep -Fq 'favicon.ico 取得失敗以外の console error' <<<"$chapter"
  grep -Fq 'source checkout では `<repo>/local-skills/herdr-peer-refactor`' <<<"$chapter"
  grep -Fq '配備後は `$HOME/.agents/skills/<skill>`' <<<"$chapter"
  grep -Fq 'playwright-cli run-code' <<<"$chapter"
  grep -Fq "sed '\$s/;\$//'" <<<"$chapter"
}

@test "each environment skill is normally invocable and keeps its six-step workflow in native references" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local front
  front="$(awk 'NR>1 && /^---$/{exit} NR>1' "$skill")"
  run grep -Fq 'disable-model-invocation' <<<"$front"
  [ "$status" -eq 1 ]
  grep -Fq 'description:' <<<"$front"

  for heading in \
    '^## 1\. 元の候補を固定' \
    '^## 2\. worktree と担当' \
    '^## 3\. peer と設計' \
    '^## 4\. 実装と検証' \
    '^## 5\. 独立レビュー' \
    '^## 6\. PR と報告'; do
    grep -Eq "$heading" "$skill"
  done
  grep -Fq "references/$name.md" "$skill"
  [ -f "$(dirname "$skill")/references/$name.md" ]
  if [ "$name" = herdr ]; then grep -Fq 'references/auto-session.md' "$skill"; fi
  # The dedicated auto-session deny stays documented separately, not as this skill's start gate.
  run grep -Fq 'The deny fragment is applied to this session' "$skill"
  [ "$status" -eq 1 ]
  done
}

@test "each environment skill pins upstream candidates before design and checks them before publication" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local candidates design publication pin_line design_check_line publish_check_line
  candidates="$(sed -n '/^## 1\. 元の候補を固定/,/^## 2\./p' "$skill")"
  design="$(sed -n '/^## 3\. peer と設計/,/^## 4\./p' "$skill")"
  publication="$(sed -n '/^## 6\. PR と報告/,$p' "$skill")"
  printf '%s\n' "$candidates" | grep -Fq 'candidate-record.py pin'
  printf '%s\n' "$candidates" | grep -Fq '提示済み artifact'
  for field in 'artifact' 'repo' 'source SHA' 'acceptance' 'non_goals' 'owned_files'; do
    grep -Fq "$field" "$skill"
  done
  printf '%s\n' "$candidates" | grep -Fq '`check` は設計前、再開時、公開前'
  # Human-selected candidates stay selected; only unselected candidates go through peer evidence.
  printf '%s\n' "$candidates" | grep -Fq '人が選んだ候補'
  printf '%s\n' "$candidates" | grep -Fq '未選択なら'
  printf '%s\n' "$design" | grep -Fq '根拠'

  pin_line="$(grep -n 'candidate-record.py pin' "$skill" | head -1 | cut -d: -f1)"
  design_check_line="$(grep -n '`check` は設計前、再開時、公開前' "$skill" | cut -d: -f1)"
  design_line="$(grep -n '^## 3\. peer と設計' "$skill" | cut -d: -f1)"
  [ -n "$pin_line" ] && [ -n "$design_check_line" ]
  [ "$pin_line" -lt "$design_line" ]
  [ "$design_check_line" -lt "$design_line" ]
  done
}

@test "each environment skill uses native peer guidance and model-independent decision rules" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local peer
  peer="$(sed -n '/^## 3\. peer と設計/,/^## 4\./p' "$skill")"
  run grep -Fq 'same model' <<<"$peer"
  [ "$status" -eq 1 ]
  run grep -Fq '同一モデル' <<<"$peer"
  [ "$status" -eq 1 ]
  printf '%s\n' "$peer" | grep -Fq 'Held Candidate'
  printf '%s\n' "$peer" | grep -Fq 'Peer Decision'
  printf '%s\n' "$peer" | grep -Fq '反例または peer 自身の検証'
  printf '%s\n' "$peer" | grep -Fq '新しい ADR'
  done
}

@test "each environment skill requires an independent final-SHA review before a safe PR" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local implementation review publication
  implementation="$(sed -n '/^## 4\. 実装と検証/,/^## 5\./p' "$skill")"
  review="$(sed -n '/^## 5\. 独立レビュー/,/^## 6\./p' "$skill")"
  publication="$(sed -n '/^## 6\. PR と報告/,$p' "$skill")"
  printf '%s\n' "$implementation" | grep -Fq '最小の変更'
  printf '%s\n' "$implementation" | grep -Fq 'base を固定'
  printf '%s\n' "$implementation" | grep -Fq 'repo の必要な全チェック'
  printf '%s\n' "$implementation" | grep -Fq '再検証'
  printf '%s\n' "$review" | grep -Fq 'Standards'
  printf '%s\n' "$review" | grep -Fq 'Spec'
  printf '%s\n' "$review" | grep -Fq '最終 SHA'
  printf '%s\n' "$publication" | grep -Fq 'git-push-topic'
  printf '%s\n' "$publication" | grep -Fq 'gh pr view'
  printf '%s\n' "$publication" | grep -Fq 'state'
  printf '%s\n' "$publication" | grep -Fq 'head'
  printf '%s\n' "$publication" | grep -Fq 'merge と issue の直接 close は行わない'
  grep -Fq 'grilling' "$skill"
  printf '%s\n' "$publication" | grep -Fq 'issue がある場合だけ `Closes #N`'
  done
}

@test "each environment skill keeps issue creation optional and external writes explicit" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local design publication
  design="$(sed -n '/^## 3\. peer と設計/,/^## 4\./p' "$skill")"
  publication="$(sed -n '/^## 6\. PR と報告/,$p' "$skill")"
  printf '%s\n' "$design" | grep -Fq 'issue は任意'
  printf '%s\n' "$design" | grep -Fq '承認済みの場合だけ'
  printf '%s\n' "$design" | grep -Fq '小さな候補は設計記録から直接実装'
  printf '%s\n' "$publication" | grep -Fq '外部書込みは依頼の承認範囲に限り'
  printf '%s\n' "$publication" | grep -Fq 'issue がある場合だけ'
  done
}

@test "legacy dedicated auto-session procedure and its independent permission/helper boundaries stay documented" {
  local skill="$BATS_TEST_DIRNAME/../local-skills/herdr-peer-refactor/SKILL.md"
  local auto="$BATS_TEST_DIRNAME/../local-skills/herdr-peer-refactor/references/auto-session.md"
  [ -f "$auto" ]
  grep -Fq 'auto-peer-deny.json' "$auto"
  grep -Fq 'auto-peer.rules' "$auto"
  grep -Fq 'dotfiles-peer' "$auto"
  grep -Fq 'plan-parallel.sh' "$auto"
  grep -Fq 'launch-child.sh' "$auto"
  grep -Fq 'check-owned.sh' "$auto"
  grep -Fq 'permission' "$auto"
  grep -Fq 'references/auto-session.md' "$skill"
}

@test "each environment skill preserves the report and idempotent external-write safety" {
  local name skill
  for name in herdr orca; do
  skill="$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/SKILL.md"
  local publication
  publication="$(sed -n '/^## 6\. PR と報告/,$p' "$skill")"
  printf '%s\n' "$publication" | grep -Fq '承認範囲'
  printf '%s\n' "$publication" | grep -Fq 'gh-once.sh'
  printf '%s\n' "$publication" | grep -Fq 'gh pr view --json state,headRefOid,isDraft'
  [ -x "$BATS_TEST_DIRNAME/../local-skills/$name-peer-refactor/scripts/gh-once.sh" ]
  done
}

@test "every local skill shell script is executable" {
  local script
  while IFS= read -r script; do
    [ -x "$script" ] || { echo "not executable: $script" >&2; return 1; }
  done < <(find "$BATS_TEST_DIRNAME/../local-skills" -path '*/scripts/*.sh')
}

@test "peer contract Run Scope names the approved external operations" {
  local scope
  scope="$(grep -F 'Run Scope は' "$BATS_TEST_DIRNAME/../runtime/autonomous-peer-contract.md")"
  printf '%s\n' "$scope" | grep -Fq 'git-push-topic'
  printf '%s\n' "$scope" | grep -Fq 'draft PR'
  printf '%s\n' "$scope" | grep -Fq 'ready 化・merge・close・force push・secret は承認に含めない'
}
