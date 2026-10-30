#!/usr/bin/env bats

load local-skills-helper

install_known_legacy_topic() {
  mkdir -p "$SKILL_HOME/.local/bin"
  git -C "$PROJECT_ROOT" show \
    '6d5b73dd8b9c88531a74e724ca9d83fa34b44b35:private_dot_local/bin/executable_git-push-topic' \
    >"$SKILL_HOME/.local/bin/git-push-topic"
  chmod 755 "$SKILL_HOME/.local/bin/git-push-topic"
}

setup() {
  setup_local_skills_fixture
}

@test "migration preparation stops when an old CLI cannot be inspected" {
  [ "$(id -u)" -ne 0 ] || skip "root は directory の検査拒否を再現できない"
  mkdir -p "$SKILL_HOME/.local/bin"
  global_cli_source_body git-push-topic >"$SKILL_HOME/.local/bin/git-push-topic"
  chmod +x "$SKILL_HOME/.local/bin/git-push-topic"
  chmod 000 "$SKILL_HOME/.local/bin"
  run run_skill_phase before_remove-orphan-claude-skills
  chmod 700 "$SKILL_HOME/.local/bin"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Permission denied'* ]]
  diff -u <(global_cli_source_body git-push-topic) "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "migration preparation does not adopt an unknown CLI symlink even when its content is known" {
  mkdir -p "$SKILL_HOME/.local/bin"
  global_cli_source_body orca-send >"$BATS_TEST_TMPDIR/external-cli"
  chmod +x "$BATS_TEST_TMPDIR/external-cli"
  ln -s "$BATS_TEST_TMPDIR/external-cli" "$SKILL_HOME/.local/bin/orca-send"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -ne 0 ]
  [[ "$output" == *'未知の CLI 参照先'* ]]
  [ -L "$SKILL_HOME/.local/bin/orca-send" ]
  [ ! -e "$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/.local/bin/orca-send" ]
  diff -u <(global_cli_source_body orca-send) "$BATS_TEST_TMPDIR/external-cli"
}

@test "migration preparation saves known CLI implementations once without replacing a changed live CLI" {
  mkdir -p "$SKILL_HOME/.local/bin" "$SKILL_HOME/.local/share/devshell-env"
  local name old_root="$BATS_TEST_TMPDIR/known-old"
  mkdir -p "$old_root/.local/bin" "$old_root/.local/share/devshell-env"
  for name in git-push-topic gh-review-thread orca-send codex-reviewer; do
    printf '#!/bin/sh\n# old CLI %s\n' "$name" >"$old_root/.local/bin/$name"
    chmod 755 "$old_root/.local/bin/$name"
    cp "$old_root/.local/bin/$name" "$SKILL_HOME/.local/bin/$name"
  done
  ln -s git-push-topic "$SKILL_HOME/.local/bin/git-push-reviewed"
  printf '# trusted old devshell module\n' >"$old_root/.local/share/devshell-env/devshell_environment.py"
  cp "$old_root/.local/share/devshell-env/devshell_environment.py" "$SKILL_HOME/.local/share/devshell-env/"
  python3 - "$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json" "$old_root" <<'PY'
import hashlib, json, os, sys
from pathlib import Path
manifest = Path(sys.argv[1])
root = Path(sys.argv[2])
baseline = json.loads(manifest.read_text())
for relative in baseline["cli"]:
    path = root / relative
    if relative.endswith("git-push-reviewed"):
        path = root / ".local/bin/git-push-topic"
    contents = path.read_bytes()
    baseline["cli"][relative] = {
        "sha256": hashlib.sha256(contents).hexdigest(),
        "mode": os.stat(path).st_mode & 0o777,
    }
manifest.write_text(json.dumps(baseline, sort_keys=True, ensure_ascii=False, indent=2) + "\n")
PY
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  local saved="$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35"
  [ -f "$saved/baseline.json" ]
  for name in git-push-topic gh-review-thread orca-send codex-reviewer; do
    cmp "$old_root/.local/bin/$name" "$saved/.local/bin/$name"
    [ -x "$saved/.local/bin/$name" ]
  done
  cmp "$saved/.local/bin/git-push-topic" "$saved/.local/bin/git-push-reviewed"
  cmp "$old_root/.local/share/devshell-env/devshell_environment.py" "$saved/.local/share/devshell-env/devshell_environment.py"
  printf 'user CLI\n' >"$SKILL_HOME/.local/bin/git-push-topic"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -ne 0 ]
  [[ "$output" == *'旧 CLI 切替を保留します'* ]]
  grep -Fxq 'user CLI' "$SKILL_HOME/.local/bin/git-push-topic"
  cmp "$old_root/.local/bin/git-push-topic" "$saved/.local/bin/git-push-topic"

  printf 'damaged backup\n' >"$saved/.local/bin/git-push-topic"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -ne 0 ]
  [[ "$output" == *'保存済みの旧 CLI が不正'* ]]
  grep -Fxq 'user CLI' "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "individual CLI apply does not replace an unknown existing CLI" {
  setup_skill_apply
  mkdir -p "$SKILL_HOME/.local/bin"
  printf 'unknown user CLI\n' >"$SKILL_HOME/.local/bin/git-push-topic"

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"

  [ "$status" -ne 0 ]
  [[ "$output" == *'旧 CLI 切替を保留します'* ]]
  grep -Fxq 'unknown user CLI' "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "full apply prepares and preserves a known old CLI before rendering its shim" {
  setup_skill_apply
  install_known_legacy_topic
  ln -s git-push-topic "$SKILL_HOME/.local/bin/git-push-reviewed"

  run skill_chezmoi apply

  [ "$status" -eq 0 ]
  printf 'codex:sync\ncodex:verify-only\nplugin:verify-only\n' >"$BATS_TEST_TMPDIR/expected-sync.log"
  cmp "$BATS_TEST_TMPDIR/expected-sync.log" "$SYNC_LOG"
  global_cli_source_body git-push-topic | cmp - "$SKILL_HOME/.local/bin/git-push-topic"
  global_cli_source_body git-push-reviewed | cmp - "$SKILL_HOME/.local/bin/git-push-reviewed"
  [ ! -L "$SKILL_HOME/.local/bin/git-push-reviewed" ]
  cmp \
    <(git -C "$PROJECT_ROOT" show '6d5b73dd8b9c88531a74e724ca9d83fa34b44b35:private_dot_local/bin/executable_git-push-topic') \
    "$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/.local/bin/git-push-topic"
  cmp \
    <(git -C "$PROJECT_ROOT" show '6d5b73dd8b9c88531a74e724ca9d83fa34b44b35:private_dot_local/bin/executable_git-push-topic') \
    "$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/.local/bin/git-push-reviewed"
  local dispatch_log="$BATS_TEST_TMPDIR/full-apply-dispatch.log"
  mock_global_cli_dispatcher "$SKILL_HOME"
  assert_global_cli_dispatch git-push-topic "$dispatch_log"
  assert_global_cli_dispatch git-push-reviewed "$dispatch_log"
}

@test "individual apply resumes a known reviewed alias after the topic shim was installed" {
  setup_skill_apply
  install_known_legacy_topic
  ln -s git-push-topic "$SKILL_HOME/.local/bin/git-push-reviewed"
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  global_cli_source_body git-push-topic >"$SKILL_HOME/.local/bin/git-push-topic"
  local dispatch_log="$BATS_TEST_TMPDIR/partial-dispatch.log"
  mock_global_cli_dispatcher "$SKILL_HOME"
  assert_global_cli_dispatch git-push-reviewed "$dispatch_log"

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-reviewed"

  [ "$status" -eq 0 ]
  global_cli_source_body git-push-reviewed | cmp - "$SKILL_HOME/.local/bin/git-push-reviewed"
  [ ! -L "$SKILL_HOME/.local/bin/git-push-reviewed" ]
  assert_global_cli_dispatch git-push-topic "$dispatch_log"
  assert_global_cli_dispatch git-push-reviewed "$dispatch_log"
}

@test "individual CLI apply retains a known old CLI when its backup is missing" {
  setup_skill_apply
  install_known_legacy_topic
  cp "$SKILL_HOME/.local/bin/git-push-topic" "$BATS_TEST_TMPDIR/old-cli"

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"

  [ "$status" -ne 0 ]
  [[ "$output" == *'固定 backup manifest がありません'* ]]
  cmp "$BATS_TEST_TMPDIR/old-cli" "$SKILL_HOME/.local/bin/git-push-topic"
  [ ! -e "$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35" ]
}

@test "individual CLI apply retains a known old CLI when its saved copy is corrupt" {
  setup_skill_apply
  install_known_legacy_topic
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  cp "$SKILL_HOME/.local/bin/git-push-topic" "$BATS_TEST_TMPDIR/old-cli"
  printf 'corrupt backup\n' \
    >"$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/.local/bin/git-push-topic"

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"

  [ "$status" -ne 0 ]
  [[ "$output" == *'既知 backup がありません'* ]]
  cmp "$BATS_TEST_TMPDIR/old-cli" "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "individual CLI apply rejects a corrupt backup and self-updated manifest together" {
  setup_skill_apply
  install_known_legacy_topic
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  local saved="$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35"
  cp "$SKILL_HOME/.local/bin/git-push-topic" "$BATS_TEST_TMPDIR/old-cli"
  python3 - "$saved" <<'PY'
import hashlib, json, os, sys
from pathlib import Path

root = Path(sys.argv[1])
payload = b"corrupt backup\n"
cli = root / ".local/bin/git-push-topic"
cli.write_bytes(payload)
os.chmod(cli, 0o755)
manifest = root / "baseline.json"
baseline = json.loads(manifest.read_text(encoding="utf-8"))
baseline["cli"][".local/bin/git-push-topic"] = {
    "sha256": hashlib.sha256(payload).hexdigest(),
    "mode": 0o755,
}
manifest.write_text(json.dumps(baseline, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
PY

  run skill_chezmoi apply "$SKILL_HOME/.local/bin/git-push-topic"

  [ "$status" -ne 0 ]
  [[ "$output" == *'固定 backup manifest がありません'* ]]
  cmp "$BATS_TEST_TMPDIR/old-cli" "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "legacy preparation and cutover reject relative XDG state without CWD writes" {
  install_known_legacy_topic
  local baseline_json
  baseline_json="$(cat "$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.json")"
  cd "$BATS_TEST_TMPDIR"

  run env HOME="$SKILL_HOME" XDG_STATE_HOME=relative-state \
    python3 "$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py" "$baseline_json" prepare
  [ "$status" -ne 0 ]
  [[ "$output" == *'XDG_STATE_HOME must be absolute'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/relative-state" ]
  grep -q 'set -euo pipefail' "$SKILL_HOME/.local/bin/git-push-topic"

  run env HOME="$SKILL_HOME" XDG_STATE_HOME=relative-state \
    python3 "$SKILL_SOURCE/.chezmoitemplates/local-skills-legacy.py" \
      "$baseline_json" preflight-cli-cutover "$SKILL_SOURCE"
  [ "$status" -ne 0 ]
  [[ "$output" == *'XDG_STATE_HOME must be absolute'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/relative-state" ]
  grep -q 'set -euo pipefail' "$SKILL_HOME/.local/bin/git-push-topic"
}

@test "empty and absent legacy source render cleanup hooks and share a stable empty hash" {
  local empty_hash absent_hash rendered absent_rendered
  local hash_helper="$SKILL_SOURCE/.chezmoitemplates/local-skills-hash.py"
  local render_file="$BATS_TEST_TMPDIR/local-skills-phase.sh"
  rm -rf -- "$SKILL_SOURCE/local-skills"
  run python3 "$hash_helper" "$SKILL_SOURCE/local-skills"
  [ "$status" -eq 0 ]
  absent_hash="$output"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/.chezmoitemplates/local-skills.sh.tmpl" \
    >"$BATS_TEST_TMPDIR/local-skills-absent.sh"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_before_remove-orphan-claude-skills.sh.tmpl" \
    >"$render_file"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_after_apm-install.sh.tmpl" \
    >"$BATS_TEST_TMPDIR/apm-absent.sh"
  absent_rendered="$(cat "$render_file")"
  grep -Fq 'apm install --frozen --target claude,codex --https' "$BATS_TEST_TMPDIR/apm-absent.sh"
  grep -Fq 'apm prune' "$BATS_TEST_TMPDIR/apm-absent.sh"
  ! grep -Fq 'local_skills_deploy' "$render_file"
  setup_skill_apply
  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  run run_skill_phase after_apm-install
  [ "$status" -eq 0 ]

  mkdir -p "$SKILL_SOURCE/local-skills"
  run python3 "$hash_helper" "$SKILL_SOURCE/local-skills"
  [ "$status" -eq 0 ]
  empty_hash="$output"
  [ "$empty_hash" = "$absent_hash" ]
  skill_chezmoi execute-template --file "$SKILL_SOURCE/.chezmoitemplates/local-skills.sh.tmpl" \
    >"$BATS_TEST_TMPDIR/local-skills-empty.sh"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_before_remove-orphan-claude-skills.sh.tmpl" \
    >"$render_file"
  rendered="$(cat "$render_file")"
  [ "$rendered" = "$absent_rendered" ]
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_after_apm-install.sh.tmpl" \
    >"$BATS_TEST_TMPDIR/apm-empty.sh"
  [ "$(cat "$BATS_TEST_TMPDIR/apm-empty.sh")" = "$(cat "$BATS_TEST_TMPDIR/apm-absent.sh")" ]

  run run_skill_phase before_remove-orphan-claude-skills
  [ "$status" -eq 0 ]
  run run_skill_phase after_apm-install
  [ "$status" -eq 0 ]
  printf 'install --frozen --target claude,codex --https\nprune\ninstall --frozen --target claude,codex --https\nprune\n' \
    >"$BATS_TEST_TMPDIR/expected-apm.log"
  cmp "$BATS_TEST_TMPDIR/expected-apm.log" "$SKILL_APM_LOG"
}

@test "remaining legacy source stays ignored and is not copied into runtime skill homes" {
  setup_skill_apply
  mkdir -p "$SKILL_SOURCE/local-skills/marp" "$SKILL_HOME/.agents/skills" "$SKILL_HOME/.claude/skills"
  printf 'unmanaged source copy\n' >"$SKILL_SOURCE/local-skills/marp/SKILL.md"

  run skill_chezmoi apply

  [ "$status" -eq 0 ]
  [ -f "$SKILL_SOURCE/local-skills/marp/SKILL.md" ]
  [ ! -e "$SKILL_HOME/local-skills" ]
  [ ! -e "$SKILL_HOME/.agents/skills/marp" ]
  [ ! -e "$SKILL_HOME/.claude/skills/marp" ]
}
