#!/usr/bin/env bats

load local-skills-helper

setup() {
  setup_local_skills_fixture
  export FAKE_HOME="$SKILL_HOME"
  mkdir -p "$FAKE_HOME/.claude/skills"
  SCRIPT="$BATS_TEST_TMPDIR/cleanup.sh"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_before_remove-orphan-claude-skills.sh.tmpl" >"$SCRIPT"
}

run_script() {
  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" bash "$SCRIPT"
}

copy_cli_shims() {
  local destination="$1"
  mkdir -p "$destination/private_dot_local/bin"
  cp "$PROJECT_ROOT"/private_dot_local/bin/executable_{git-push-topic,git-push-reviewed,gh-review-thread,orca-send,codex-reviewer}.tmpl \
    "$destination/private_dot_local/bin/"
}

@test "preserves real directories whose ownership is unknown" {
  mkdir -p "$FAKE_HOME/.claude/skills/orphan-skill"
  printf 'stub\n' >"$FAKE_HOME/.claude/skills/orphan-skill/SKILL.md"

  run run_script
  [ "$status" -eq 0 ]
  [ -e "$FAKE_HOME/.claude/skills/orphan-skill/SKILL.md" ]
}

@test "preserves symlinks (does not follow or delete them)" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill" "$FAKE_HOME/.claude/skills/my-custom-skill"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/my-custom-skill" ]
  [ -d "$BATS_TEST_TMPDIR/elsewhere/my-custom-skill" ]
}

@test "no-op when ~/.claude/skills/ does not exist" {
  rm -rf "$FAKE_HOME/.claude/skills"

  run run_script
  [ "$status" -eq 0 ]
}

@test "preserves unknown directories and their nested files" {
  mkdir -p "$FAKE_HOME/.claude/skills/orphan-skill/references"
  printf 'inner\n' >"$FAKE_HOME/.claude/skills/orphan-skill/references/note.md"

  run run_script
  [ "$status" -eq 0 ]
  grep -Fxq 'inner' "$FAKE_HOME/.claude/skills/orphan-skill/references/note.md"
}

create_repo_apm_fixture() {
  local repo="$1"
  copy_cli_shims "$repo"
  python3 - "$repo" "$SKILL_SOURCE/apm.lock.yaml" <<'PY'
import hashlib, json, sys
from pathlib import Path
root, lock = map(Path, sys.argv[1:])
files = {
    '.agents/skills/frontend-design/SKILL.md': b'fixture\n',
    '.claude/skills/frontend-design/SKILL.md': b'fixture\n',
    '.codex/hooks.json': b'{}\n',
}
for name, contents in files.items():
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)
lock.write_text(json.dumps({'dependencies': [{
    'deployed_files': list(files),
    'deployed_file_hashes': {
        name: 'sha256:' + hashlib.sha256(contents).hexdigest()
        for name, contents in files.items()
    },
}]}))
PY
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_before_remove-orphan-claude-skills.sh.tmpl" >"$SCRIPT"
}

@test "source 指定先の APM 台帳と一致する file だけを撤去する" {
  local repo="$BATS_TEST_TMPDIR/ghq-source"
  create_repo_apm_fixture "$repo"
  mkdir -p "$repo/.claude/commands"
  printf 'personal\n' >"$repo/.claude/commands/personal.md"

  HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR="$repo" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$repo/.agents" ]
  [ ! -e "$repo/.claude/skills" ]
  [ ! -e "$repo/.codex/hooks.json" ]
  [ "$(cat "$repo/.claude/commands/personal.md")" = personal ]
}

@test "既定 source の変更済み file と未知の追加項目を保持する" {
  local repo="$FAKE_HOME/.local/share/chezmoi"
  create_repo_apm_fixture "$repo"
  printf 'customized\n' >"$repo/.agents/skills/frontend-design/SKILL.md"
  printf 'personal\n' >"$repo/.agents/personal-notes.md"

  HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR= run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(cat "$repo/.agents/skills/frontend-design/SKILL.md")" = customized ]
  [ "$(cat "$repo/.agents/personal-notes.md")" = personal ]
  [ ! -e "$repo/.codex/hooks.json" ]
  [ ! -e "$repo/.claude/skills" ]
}

@test "repo 内の symlink 親から外部の同内容 file を削除しない" {
  local repo="$BATS_TEST_TMPDIR/ghq-source"
  create_repo_apm_fixture "$repo"
  mv "$repo/.agents" "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$repo/.agents"

  HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR="$repo" run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ -L "$repo/.agents" ]
  [ -f "$BATS_TEST_TMPDIR/outside/skills/frontend-design/SKILL.md" ]
}

@test "mount の検査失敗や mounted な配備先は保持する" {
  local repo="$BATS_TEST_TMPDIR/ghq-source" result
  create_repo_apm_fixture "$repo"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for result in 0 1; do
    printf '#!/bin/sh\nexit %s\n' "$result" >"$BATS_TEST_TMPDIR/bin/mountpoint"
    chmod +x "$BATS_TEST_TMPDIR/bin/mountpoint"
    HOME="$FAKE_HOME" CHEZMOI_SOURCE_DIR="$repo" PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$repo/.agents/skills/frontend-design/SKILL.md" ]
    [ -f "$repo/.claude/skills/frontend-design/SKILL.md" ]
  done
}

@test "file を開いた後で親 directory が入れ替わったら撤去しない" {
  local repo="$BATS_TEST_TMPDIR/ghq-source"
  create_repo_apm_fixture "$repo"
  run python3 -I - "$PROJECT_ROOT/.chezmoitemplates/apm-repo-cleanup.py" "$repo" "$SKILL_SOURCE/apm.lock.yaml" <<'PY'
import io, json, os, runpy, sys
from pathlib import Path
from unittest.mock import patch
code, root, lock = map(Path, sys.argv[1:])
parent = root / '.agents/skills/frontend-design'
outside = root / 'moved-directory'
original_open = os.open
def replace_parent(path, *args, **kwargs):
    descriptor = original_open(path, *args, **kwargs)
    if path in ('SKILL.md', 'payload') and not outside.exists():
        parent.rename(outside)
        parent.mkdir()
    return descriptor
sys.argv = [str(code), str(root)]
with patch('os.open', replace_parent), patch('sys.stdin', io.StringIO(lock.read_text())):
    runpy.run_path(str(code), run_name='__main__')
assert (outside / 'SKILL.md').read_text() == 'fixture\n'
assert parent.is_dir()
PY
  [ "$status" -eq 0 ]
}

@test "削除直前の差し替え・読取不能・復元先の競合でもデータを保持する" {
  local mode repo
  for mode in replacement unreadable restore-conflict; do
    repo="$BATS_TEST_TMPDIR/$mode"
    create_repo_apm_fixture "$repo"
    run python3 -I - "$PROJECT_ROOT/.chezmoitemplates/apm-repo-cleanup.py" "$repo" "$SKILL_SOURCE/apm.lock.yaml" "$mode" <<'PY'
import io, os, runpy, sys
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch
code, root, lock = map(Path, sys.argv[1:4])
mode = sys.argv[4]
target = root / '.agents/skills/frontend-design/SKILL.md'
original_unlink, original_lstat, original_link = os.unlink, Path.lstat, os.link
changed = False
def replace_before_unlink(path, *args, **kwargs):
    global changed
    if not changed and path in ('SKILL.md', 'payload'):
        target.write_text('new edits\n')
        changed = True
    return original_unlink(path, *args, **kwargs)
def unreadable(path, *args, **kwargs):
    if path == target:
        raise PermissionError('fixture-denied')
    return original_lstat(path, *args, **kwargs)
def conflict(*args, **kwargs):
    target.write_text('new edits\n')
    return original_link(*args, **kwargs)
if mode == 'restore-conflict':
    target.write_text('customized\n')
selected = {
    'replacement': ('os.unlink', replace_before_unlink),
    'unreadable': ('pathlib.Path.lstat', unreadable),
    'restore-conflict': ('os.link', conflict),
}[mode]
sys.argv = [str(code), str(root)]
errors = io.StringIO()
with patch(*selected), patch('sys.stdin', io.StringIO(lock.read_text())), redirect_stderr(errors):
    runpy.run_path(str(code), run_name='__main__')
if mode == 'unreadable':
    assert target.read_text() == 'fixture\n'
    assert str(target) in errors.getvalue() and 'fixture-denied' in errors.getvalue()
else:
    assert target.read_text() == 'new edits\n'
    if mode == 'restore-conflict':
        saved = list(target.parent.glob('.apm-retire.*/payload'))
        assert len(saved) == 1 and saved[0].read_text() == 'customized\n'
        assert '退避を保持' in errors.getvalue()
PY
    [ "$status" -eq 0 ]
  done
}

@test "preserves unknown nix-store symlinks even when an old marker is present" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  ln -s "/nix/store/aaaa-fake/skills/foo" "$FAKE_HOME/.agents/skills/foo"
  ln -s "/nix/store/bbbb-fake/skills/bar" "$FAKE_HOME/.agents/skills/bar"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.agents/skills/foo" ]
  [ -L "$FAKE_HOME/.agents/skills/bar" ]
  [ ! -f "$FAKE_HOME/.agents/skills/.managed-by-ai-nix" ]
}

@test "preserves non-nix-store symlinks under ~/.agents/skills even when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  mkdir -p "$BATS_TEST_TMPDIR/apm-cache/my-custom-skill"
  ln -s "$BATS_TEST_TMPDIR/apm-cache/my-custom-skill" "$FAKE_HOME/.agents/skills/my-custom-skill"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.agents/skills/my-custom-skill" ]
  [ ! -f "$FAKE_HOME/.agents/skills/.managed-by-ai-nix" ]
}

@test "preserves unknown nix-store symlinks when marker is absent" {
  mkdir -p "$FAKE_HOME/.agents/skills"
  ln -s "/nix/store/cccc-fake/skills/keep-me" "$FAKE_HOME/.agents/skills/keep-me"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.agents/skills/keep-me" ]
}

@test "removes ai-nix companion symlinks under ~/.claude/skills when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills"
  ln -s "../../.agents/skills/agent-browser" "$FAKE_HOME/.claude/skills/agent-browser"
  ln -s "../../.agents/skills/dogfood" "$FAKE_HOME/.claude/skills/dogfood"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/agent-browser" ]
  [ -L "$FAKE_HOME/.claude/skills/dogfood" ]
}

@test "preserves unrelated symlinks under ~/.claude/skills even when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills"
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/keep-me"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/keep-me" "$FAKE_HOME/.claude/skills/keep-me"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/keep-me" ]
}

@test "removes ai-nix companion symlinks under ~/.codex/skills when marker present" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run run_script
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
}

@test "removes ai-nix companion symlinks under custom CODEX_HOME/skills too" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  ln -s "../../.agents/skills/find-skills" "$codex_home/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -e "$codex_home/skills/find-skills" ]
}

@test "removes ai-nix companion symlinks under existing Codex Desktop home (.codex-app) when CODEX_HOME is unset" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$FAKE_HOME/.codex-app/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex-app/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run env -u CODEX_HOME CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -e "$FAKE_HOME/.codex-app/skills/find-skills" ]
}

@test "leaves Codex Desktop home (.codex-app) untouched when it does not exist and CODEX_HOME is unset" {
  mkdir -p "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills"
  ln -s "../../.agents/skills/find-skills" "$FAKE_HOME/.codex/skills/find-skills"
  : >"$FAKE_HOME/.agents/skills/.managed-by-ai-nix"

  run env -u CODEX_HOME CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.codex/skills/find-skills" ]
  [ ! -d "$FAKE_HOME/.codex-app" ]
}

@test "removes retired APM UI skill real directories from agent runtimes" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    mkdir -p "$dir/baseline-ui" "$dir/fixing-accessibility" "$dir/fixing-metadata" "$dir/fixing-motion-performance" "$dir/modern-web-guidance"
  done

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    [ ! -e "$dir/baseline-ui" ]
    [ ! -e "$dir/fixing-accessibility" ]
    [ ! -e "$dir/fixing-metadata" ]
    [ ! -e "$dir/fixing-motion-performance" ]
  done

  [ -d "$FAKE_HOME/.agents/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.codex/skills/modern-web-guidance" ]
  [ -d "$codex_home/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.gemini/skills/modern-web-guidance" ]
  [ -d "$FAKE_HOME/.copilot/skills/modern-web-guidance" ]
}

@test "preserves external APM skills in ~/.agents for Codex Desktop discovery" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p \
    "$FAKE_HOME/.agents/skills/effect-ts" \
    "$FAKE_HOME/.agents/skills/frontend-design" \
    "$FAKE_HOME/.agents/skills/web-design-guidelines" \
    "$FAKE_HOME/.agents/skills/pdf" \
    "$FAKE_HOME/.agents/skills/react-view-transitions" \
    "$FAKE_HOME/.agents/skills/shadcn" \
    "$FAKE_HOME/.agents/skills/remotion" \
    "$FAKE_HOME/.codex/skills/effect-ts" \
    "$FAKE_HOME/.codex/skills/frontend-design" \
    "$FAKE_HOME/.codex/skills/react-view-transitions" \
    "$FAKE_HOME/.codex/skills/shadcn" \
    "$codex_home/skills/effect-ts" \
    "$codex_home/skills/frontend-design"
  printf 'stub\n' >"$FAKE_HOME/.agents/skills/web-design-guidelines/SKILL.md"

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ -d "$FAKE_HOME/.agents/skills/effect-ts" ]
  [ -d "$FAKE_HOME/.agents/skills/frontend-design" ]
  [ -f "$FAKE_HOME/.agents/skills/web-design-guidelines/SKILL.md" ]
  [ -d "$FAKE_HOME/.agents/skills/pdf" ]
  [ -d "$FAKE_HOME/.agents/skills/react-view-transitions" ]
  [ -d "$FAKE_HOME/.agents/skills/shadcn" ]
  [ -d "$FAKE_HOME/.agents/skills/remotion" ]
  [ -d "$FAKE_HOME/.codex/skills/effect-ts" ]
  [ -d "$FAKE_HOME/.codex/skills/frontend-design" ]
  [ -d "$FAKE_HOME/.codex/skills/react-view-transitions" ]
  [ -d "$FAKE_HOME/.codex/skills/shadcn" ]
  [ -d "$codex_home/skills/effect-ts" ]
  [ -d "$codex_home/skills/frontend-design" ]
}

@test "preserves migrating local duplicates and still removes previously retired names" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills"; do
    mkdir -p "$dir/to-pr" "$dir/to-worktree" "$dir/dogfood" "$dir/ui-grill-with-docs" "$dir/frontend-design"
    printf 'stub\n' >"$dir/to-pr/SKILL.md"
    printf 'stub\n' >"$dir/frontend-design/SKILL.md"
  done

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  [ ! -e "$FAKE_HOME/.agents/skills/to-pr" ]
  [ ! -e "$FAKE_HOME/.claude/skills/to-pr" ]
  [ -d "$FAKE_HOME/.agents/skills/ui-grill-with-docs" ]
  [ -d "$FAKE_HOME/.claude/skills/ui-grill-with-docs" ]
  [ ! -e "$FAKE_HOME/.codex/skills/to-pr" ]
  [ ! -e "$FAKE_HOME/.codex/skills/to-worktree" ]
  [ -d "$FAKE_HOME/.codex/skills/dogfood" ]
  [ -d "$FAKE_HOME/.codex/skills/ui-grill-with-docs" ]
  [ ! -e "$codex_home/skills/to-pr" ]
  [ ! -e "$codex_home/skills/to-worktree" ]
  [ -d "$codex_home/skills/dogfood" ]
  [ -d "$codex_home/skills/ui-grill-with-docs" ]
  [ -d "$FAKE_HOME/.codex/skills/frontend-design" ]
  [ -d "$codex_home/skills/frontend-design" ]
}

@test "removes retired agent-browser and obsolete writing skill while preserving official Matt skills" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  local hub_dirs=(
    "$FAKE_HOME/.agents/skills"
  )
  local claude_dirs=(
    "$FAKE_HOME/.claude/skills"
  )
  local native_dirs=(
    "$FAKE_HOME/.codex/skills"
    "$codex_home/skills"
  )
  local other_dirs=(
    "$FAKE_HOME/.gemini/skills"
    "$FAKE_HOME/.copilot/skills"
  )

  for dir in "${hub_dirs[@]}" "${claude_dirs[@]}" "${native_dirs[@]}" "${other_dirs[@]}"; do
    mkdir -p "$dir/agent-browser" "$dir/grill-me" "$dir/teach" "$dir/writing-for-agents" "$dir/writing-great-skills" "$dir/modern-web-guidance"
  done

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "${hub_dirs[@]}"; do
    [ ! -e "$dir/agent-browser" ]
    [ -d "$dir/grill-me" ]
    [ -d "$dir/teach" ]
    [ -d "$dir/writing-for-agents" ]
    [ ! -e "$dir/writing-great-skills" ]
    [ -d "$dir/modern-web-guidance" ]
  done

  for dir in "${claude_dirs[@]}"; do
    [ ! -e "$dir/agent-browser" ]
    [ -d "$dir/grill-me" ]
    [ -d "$dir/teach" ]
    [ -d "$dir/writing-for-agents" ]
    [ ! -e "$dir/writing-great-skills" ]
    [ -d "$dir/modern-web-guidance" ]
  done

  for dir in "${native_dirs[@]}"; do
    [ ! -e "$dir/agent-browser" ]
    [ ! -e "$dir/grill-me" ]
    [ ! -e "$dir/teach" ]
    [ ! -e "$dir/writing-for-agents" ]
    [ ! -e "$dir/writing-great-skills" ]
    [ -d "$dir/modern-web-guidance" ]
  done

  for dir in "${other_dirs[@]}"; do
    [ ! -e "$dir/agent-browser" ]
    [ -d "$dir/grill-me" ]
    [ -d "$dir/teach" ]
    [ -d "$dir/writing-for-agents" ]
    [ ! -e "$dir/writing-great-skills" ]
    [ -d "$dir/modern-web-guidance" ]
  done
}

@test "preserves every Matt Pocock skill across managed runtime directories" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  local matt_skills=(
    ask-matt
    code-review
    codebase-design
    diagnosing-bugs
    domain-modeling
    grill-me
    grill-with-docs
    grilling
    handoff
    implement
    implement-spec
    improve-codebase-architecture
    pr
    prototype
    research
    retro
    setup-matt-pocock-skills
    tdd
    teach
    to-questionnaire
    to-spec
    to-tickets
    triage
    wait-what
    wayfinder
    wizard
    writing-for-agents
  )
  local managed_dirs=(
    "$FAKE_HOME/.agents/skills"
    "$FAKE_HOME/.claude/skills"
  )
  local native_dirs=(
    "$FAKE_HOME/.codex/skills"
    "$codex_home/skills"
  )

  for dir in "${managed_dirs[@]}" "${native_dirs[@]}"; do
    for skill in "${matt_skills[@]}"; do
      mkdir -p "$dir/$skill"
    done
    mkdir -p "$dir/writing-great-skills"
  done

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "${managed_dirs[@]}"; do
    for skill in "${matt_skills[@]}"; do
      [ -d "$dir/$skill" ]
    done
    [ ! -e "$dir/writing-great-skills" ]
  done

  for dir in "${native_dirs[@]}"; do
    for skill in "${matt_skills[@]}"; do
      [ ! -e "$dir/$skill" ]
    done
    [ ! -e "$dir/writing-great-skills" ]
  done
}

@test "removes retired coderabbit (autofix) and uxaudit skills from agent runtime skill dirs" {
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    mkdir -p "$dir/autofix" "$dir/uxaudit" "$dir/modern-web-guidance"
  done

  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" HOME="$FAKE_HOME" CODEX_HOME="$codex_home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  for dir in "$FAKE_HOME/.agents/skills" "$FAKE_HOME/.codex/skills" "$codex_home/skills" "$FAKE_HOME/.gemini/skills" "$FAKE_HOME/.copilot/skills"; do
    [ ! -e "$dir/autofix" ]
    [ ! -e "$dir/uxaudit" ]
    [ -d "$dir/modern-web-guidance" ]
  done
}
