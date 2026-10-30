#!/usr/bin/env bats

load local-skills-helper

setup() {
  setup_local_skills_fixture
  create_retirement_fixture
}

create_retirement_fixture() {
  setup_retirement_verifier_mocks
  mkdir -p "$SKILL_HOME/.local/bin"
  local name
  for name in git-push-topic git-push-reviewed gh-review-thread orca-send codex-reviewer; do
    global_cli_source_body "$name" >"$SKILL_HOME/.local/bin/$name"
    chmod 755 "$SKILL_HOME/.local/bin/$name"
  done
}

install_old_dogfood_copy() {
  local target="$1"
  mkdir -p "$target"
  git -C "$PROJECT_ROOT" archive \
    6d5b73dd8b9c88531a74e724ca9d83fa34b44b35 local-skills/dogfood |
    tar -x -C "$target" --strip-components=2
}

@test "retirement verifies current managed state and plugin payload before removing fixed legacy copies" {
  local target
  for target in \
    "$SKILL_HOME/.agents/skills/dogfood" \
    "$SKILL_HOME/.claude/skills/dogfood" \
    "$SKILL_HOME/.codex/skills/dogfood" \
    "$CODEX_HOME/skills/dogfood"; do
    install_old_dogfood_copy "$target"
  done
  mkdir -p "$SKILL_HOME/.agents/skills/user-owned"
  printf 'keep this\n' >"$SKILL_HOME/.agents/skills/user-owned/SKILL.md"

  run run_skill_retirement

  [ "$status" -eq 0 ]
  [ ! -e "$SKILL_HOME/.agents/skills/dogfood" ]
  [ ! -e "$SKILL_HOME/.claude/skills/dogfood" ]
  [ ! -e "$SKILL_HOME/.codex/skills/dogfood" ]
  [ ! -e "$CODEX_HOME/skills/dogfood" ]
  grep -Fxq 'keep this' "$SKILL_HOME/.agents/skills/user-owned/SKILL.md"
  printf 'codex:sync\ncodex:verify-only\nplugin:verify-only\n' >"$BATS_TEST_TMPDIR/expected-sync.log"
  cmp "$BATS_TEST_TMPDIR/expected-sync.log" "$SYNC_LOG"
}

@test "a failed current runtime verification holds every legacy copy" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  install_old_dogfood_copy "$target"
  export VERIFY_CODEX_FAIL=1

  run run_skill_retirement

  [ "$status" -ne 0 ]
  [ -d "$target" ]
  grep -Fq 'verification failed' <<<"$output"
  ! grep -Fq 'plugin:verify-only' "$SYNC_LOG"
}

@test "an unavailable current global CLI or required module holds legacy copies" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  install_old_dogfood_copy "$target"
  rm "$RETIREMENT_SOURCE/lib/python/treflebonbon_skills/devshell_environment.py"

  run run_skill_retirement

  [ "$status" -ne 0 ]
  [ -d "$target" ]
  [[ "$output" == *'devshell_environment.py'* ]]
}

@test "retirement holds known copies when safe dirfd operations are unavailable" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" <<'PY'
import os
from pathlib import Path
import runpy
import sys

script, baseline_path = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
module["remove_known_skill"].__globals__["dir_fd_operations_supported"] = lambda: False
home = Path(os.environ["HOME"]).resolve()
target = home / ".agents/skills/dogfood"
snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
module["remove_known_skill"]("dogfood", target, snapshot)
assert (target / "SKILL.md").is_file()
PY

  [ "$status" -eq 0 ]
  [ -f "$target/SKILL.md" ]
  [[ "$output" == *'安全な no-follow dirfd 相対削除を利用できません'* ]]
}

@test "a changed legacy baseline cannot authorize source retirement" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  install_old_dogfood_copy "$target"
  python3 - "$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
baseline = json.loads(path.read_text(encoding="utf-8"))
baseline["skills"]["dogfood"]["SKILL.md"]["sha256"] = "0" * 64
path.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  run run_skill_retirement

  [ "$status" -ne 0 ]
  [ -f "$target/SKILL.md" ]
  [[ "$output" == *'baseline 内容が固定値と一致しません'* ]]
}

@test "an edited or extra legacy item is reported and left intact while another exact copy retires" {
  local edited="$SKILL_HOME/.agents/skills/dogfood"
  local exact="$SKILL_HOME/.claude/skills/dogfood"
  install_old_dogfood_copy "$edited"
  install_old_dogfood_copy "$exact"
  printf '\nuser change\n' >>"$edited/SKILL.md"
  printf 'late user asset\n' >"$edited/user-note.txt"

  run run_skill_retirement

  [ "$status" -eq 0 ]
  [ -f "$edited/SKILL.md" ]
  [ -f "$edited/user-note.txt" ]
  [ ! -e "$exact" ]
  [[ "$output" == *"$edited"*'不一致'* ]]
  [[ "$output" == *'user-note.txt: 追加項目'* ]]
}

@test "a symlink legacy target is held without following or deleting its referent" {
  local outside="$BATS_TEST_TMPDIR/outside-dogfood"
  mkdir -p "$SKILL_HOME/.agents/skills"
  install_old_dogfood_copy "$outside"
  ln -s "$outside" "$SKILL_HOME/.agents/skills/dogfood"

  run run_skill_retirement

  [ "$status" -eq 0 ]
  [ -L "$SKILL_HOME/.agents/skills/dogfood" ]
  [ -f "$outside/SKILL.md" ]
  [[ "$output" == *'symlink'* ]]
}

@test "an ancestor changed to a symlink after inventory is held before any outside unlink" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local outside="$BATS_TEST_TMPDIR/outside-skills"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"
  install_old_dogfood_copy "$outside/dogfood"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" "$outside" <<'PY'
import json
import os
from pathlib import Path
import runpy
import sys

script, baseline_path, outside = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
home = Path(os.environ["HOME"]).resolve()
root = home / ".agents/skills/dogfood"
parent_snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
original_check = module["directories_unchanged"]
swapped = False

def swap_then_check(snapshot, *, required=None):
    global swapped
    if not swapped and snapshot is parent_snapshot:
        skills = home / ".agents/skills"
        skills.rename(home / ".agents/skills-before-race")
        skills.symlink_to(outside, target_is_directory=True)
        swapped = True
    return original_check(snapshot, required=required)

module["remove_known_skill"].__globals__["directories_unchanged"] = swap_then_check
module["remove_known_skill"]("dogfood", root, parent_snapshot)
assert swapped
assert (outside / "dogfood/SKILL.md").is_file()
PY
  [ "$status" -eq 0 ]
  [ -L "$SKILL_HOME/.agents/skills" ]
  [ -f "$outside/dogfood/SKILL.md" ]
  [ -f "$SKILL_HOME/.agents/skills-before-race/dogfood/SKILL.md" ]
}

@test "an ancestor changed immediately before unlink cannot redirect the unlink outside its open directory" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local outside="$BATS_TEST_TMPDIR/outside-skills"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"
  install_old_dogfood_copy "$outside/dogfood"
  printf 'outside sentinel\n' >"$outside/sentinel.txt"
  printf 'outside unknown\n' >"$outside/dogfood/user-owned.txt"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" "$outside" <<'PY'
import os
from pathlib import Path
import runpy
import sys

script, baseline_path, outside = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
home = Path(os.environ["HOME"]).resolve()
target = home / ".agents/skills/dogfood"
parent = home / ".agents/skills"
outside_copy = outside / "dogfood"
snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
first_relative = sorted(
    module["baseline"]["skills"]["dogfood"],
    key=lambda item: (item.count("/"), item),
    reverse=True,
)[0]
original_unlink = os.unlink
swapped = False

def swap_then_unlink(path, *args, **kwargs):
    global swapped
    if not swapped:
        parent.rename(home / ".agents/skills-before-unlink")
        parent.symlink_to(outside, target_is_directory=True)
        swapped = True
    return original_unlink(path, *args, **kwargs)

os.unlink = swap_then_unlink
try:
    module["remove_known_skill"]("dogfood", target, snapshot)
finally:
    os.unlink = original_unlink

assert swapped
assert (outside_copy / first_relative).is_file()
assert (outside_copy / "user-owned.txt").read_text(encoding="utf-8") == "outside unknown\n"
assert (outside / "sentinel.txt").read_text(encoding="utf-8") == "outside sentinel\n"
PY
  [ "$status" -eq 0 ]
  [ -f "$outside/dogfood/SKILL.md" ]
  [ -f "$outside/dogfood/user-owned.txt" ]
  [ -f "$outside/sentinel.txt" ]
}

@test "an ancestor changed immediately before rmdir cannot redirect removal outside its open directory" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local outside="$BATS_TEST_TMPDIR/outside-skills"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"
  mkdir -p "$outside/dogfood"
  chmod 755 "$outside/dogfood"
  printf 'outside sentinel\n' >"$outside/sentinel.txt"
  printf 'outside unknown\n' >"$outside/user-owned.txt"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" "$outside" <<'PY'
import os
from pathlib import Path
import runpy
import sys

script, baseline_path, outside = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
home = Path(os.environ["HOME"]).resolve()
target = home / ".agents/skills/dogfood"
parent = home / ".agents/skills"
snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
original_rmdir = os.rmdir
swapped = False

def swap_then_rmdir(path, *args, **kwargs):
    global swapped
    is_target = (
        os.fsdecode(path) == "dogfood"
        if kwargs.get("dir_fd") is not None
        else Path(path) == target
    )
    if not swapped and is_target:
        parent.rename(home / ".agents/skills-before-rmdir")
        parent.symlink_to(outside, target_is_directory=True)
        swapped = True
    return original_rmdir(path, *args, **kwargs)

os.rmdir = swap_then_rmdir
try:
    module["remove_known_skill"]("dogfood", target, snapshot)
finally:
    os.rmdir = original_rmdir

assert swapped
assert (outside / "dogfood").is_dir()
assert (outside / "sentinel.txt").read_text(encoding="utf-8") == "outside sentinel\n"
assert (outside / "user-owned.txt").read_text(encoding="utf-8") == "outside unknown\n"
PY
  [ "$status" -eq 0 ]
  [ -d "$outside/dogfood" ]
  [ -f "$outside/sentinel.txt" ]
  [ -f "$outside/user-owned.txt" ]
}

@test "a regular file changed to a FIFO before unlink is held without blocking" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" <<'PY'
import os
from pathlib import Path
import runpy
import sys

script, baseline_path = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
home = Path(os.environ["HOME"]).resolve()
root = home / ".agents/skills/dogfood"
parent_snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
original_check = module["directories_unchanged"]
calls = 0

def replace_with_fifo(snapshot, *, required=None):
    global calls
    calls += 1
    if calls == 2:
        skill_file = root / "SKILL.md"
        skill_file.unlink()
        os.mkfifo(skill_file)
    return original_check(snapshot, required=required)

module["remove_known_skill"].__globals__["directories_unchanged"] = replace_with_fifo
module["remove_known_skill"]("dogfood", root, parent_snapshot)
assert (root / "SKILL.md").is_fifo()
PY
  [ "$status" -eq 0 ]
  [ -p "$target/SKILL.md" ]
  [[ "$output" == *'unlink 直前の内容・mode 再照合に失敗しました'* ]]
}

@test "an unknown file added during unlink is retained and reported by its exact path" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  local script="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py"
  local baseline="$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json"
  install_old_dogfood_copy "$target"

  run env HOME="$SKILL_HOME" python3 - "$script" "$baseline" <<'PY'
from pathlib import Path
import os
import runpy
import sys

script, baseline_path = map(Path, sys.argv[1:])
sys.argv = [str(script), baseline_path.read_text(encoding="utf-8")]
module = runpy.run_path(str(script), run_name="legacy_test")
home = Path(os.environ["HOME"]).resolve()
root = home / ".agents/skills/dogfood"
parent_snapshot = module["safe_parent_chain"](home, Path(".agents/skills"))
original_unlink = os.unlink
added = False

def unlink_and_add(path, *args, **kwargs):
    global added
    result = original_unlink(path, *args, **kwargs)
    if not added:
        (root / "late-added.txt").write_text("retain me\n", encoding="utf-8")
        added = True
    return result

os.unlink = unlink_and_add
try:
    module["remove_known_skill"]("dogfood", root, parent_snapshot)
finally:
    os.unlink = original_unlink
assert added
assert (root / "late-added.txt").read_text(encoding="utf-8") == "retain me\n"
PY
  [ "$status" -eq 0 ]
  [ -f "$target/late-added.txt" ]
  [[ "$output" == *"$target/late-added.txt"*'撤去中に追加された項目が残りました'* ]]
}

@test "retirement is idempotent after the known source copies are absent" {
  run run_skill_retirement

  [ "$status" -eq 0 ]
  ! grep -Fq 'skills migration: 保持' <<<"$output"
}

@test "a targeted Chezmoi apply cannot retire legacy copies after current verification fails" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  install_old_dogfood_copy "$target"
  export VERIFY_CODEX_FAIL=1

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"

  [ -d "$target" ]
  if grep -Fxq 'codex:verify-only' "$SYNC_LOG"; then
    [ "$status" -ne 0 ]
    ! grep -Fq 'plugin:verify-only' "$SYNC_LOG"
    printf 'codex:sync\ncodex:verify-only\n' >"$BATS_TEST_TMPDIR/expected-sync.log"
    cmp "$BATS_TEST_TMPDIR/expected-sync.log" "$SYNC_LOG"
    printf '# path apply ran the hook and stopped at its failed read-only gate\n' >&3
  else
    [ "$status" -eq 0 ]
    [ ! -s "$SYNC_LOG" ]
    printf '# path apply skipped the global hook and retained the old copy\n' >&3
  fi
}

@test "documented first migration can show its diff while preserving old CLI and skill deployments" {
  local cli="$SKILL_HOME/.local/bin/git-push-topic"
  local legacy="$SKILL_HOME/.agents/skills/dogfood"
  local apm="$SKILL_HOME/.agents/skills/domain-modeling"
  local script="$BATS_TEST_TMPDIR/documented-diff.sh"
  local real_chezmoi
  real_chezmoi="$(command -v chezmoi)"
  install_old_dogfood_copy "$legacy"
  (cd "$PROJECT_ROOT" && git show \
    '6d5b73dd8b9c88531a74e724ca9d83fa34b44b35:private_dot_local/bin/executable_git-push-topic') >"$cli"
  chmod 755 "$cli"
  cp "$cli" "$BATS_TEST_TMPDIR/old-cli"
  ln -s /nix/store/old-apm-skill "$apm"

  python3 - "$PROJECT_ROOT/docs/architecture.md" "$script" <<'PY'
from pathlib import Path
import sys

document, script = map(Path, sys.argv[1:])
example = document.read_text().split("```bash\n", 1)[1].split("```", 1)[0]
before_confirmation, separator, _ = example.partition(
    "# 差分が意図した内容だけであることを確認し、未知差分があれば保留する。"
)
assert separator, "移行手順の差分確認境界がありません"
script.write_text(before_confirmation.replace(
    "/tmp/codex/skills-retire.XXXXXX", str(script.parent / "skills-retire.XXXXXX")
))
PY
  cat >"$BATS_TEST_TMPDIR/bin/chezmoi" <<'SH'
#!/usr/bin/env bash
exec "$REAL_CHEZMOI" --source "$SKILL_SOURCE" --destination "$SKILL_HOME" \
  --config "$SKILL_CONFIG" --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" \
  --cache "$BATS_TEST_TMPDIR/chezmoi-cache" "$@"
SH
  chmod 755 "$BATS_TEST_TMPDIR/bin/chezmoi"

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" REAL_CHEZMOI="$real_chezmoi" \
    SKILL_SOURCE="$SKILL_SOURCE" SKILL_HOME="$SKILL_HOME" SKILL_CONFIG="$SKILL_CONFIG" \
    bash "$script"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" | sed -n '/^skills migration:/p' >&3
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *'git-push-topic'* ]]
  local backup="$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35"
  cmp "$BATS_TEST_TMPDIR/old-cli" "$backup/.local/bin/git-push-topic"
  cmp "$BATS_TEST_TMPDIR/old-cli" "$cli"
  [ -f "$legacy/SKILL.md" ]
  [ "$(readlink "$apm")" = /nix/store/old-apm-skill ]
  [ ! -s "$SYNC_LOG" ]
}

@test "targeted cutover prepares old CLI first and retires legacy copies only after the explicit sync hook" {
  local target="$SKILL_HOME/.agents/skills/dogfood"
  install_old_dogfood_copy "$target"
  mkdir -p "$SKILL_HOME/.local/bin"
  git -C "$PROJECT_ROOT" show \
    '6d5b73dd8b9c88531a74e724ca9d83fa34b44b35:private_dot_local/bin/executable_git-push-topic' \
    >"$SKILL_HOME/.local/bin/git-push-topic"
  chmod 755 "$SKILL_HOME/.local/bin/git-push-topic"

  run run_skill_phase before_remove-orphan-claude-skills

  [ "$status" -eq 0 ]
  [ -f "$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/.local/bin/git-push-topic" ]
  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"
  [ "$status" -eq 0 ]
  [ -d "$target" ]
  [ ! -s "$SYNC_LOG" ]

  run run_skill_phase after_codex-managed-sync

  [ "$status" -eq 0 ]
  [ ! -e "$target" ]
  printf 'codex:sync\ncodex:verify-only\nplugin:verify-only\n' >"$BATS_TEST_TMPDIR/expected-sync.log"
  cmp "$BATS_TEST_TMPDIR/expected-sync.log" "$SYNC_LOG"
}
