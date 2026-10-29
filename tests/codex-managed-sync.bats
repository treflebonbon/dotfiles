#!/usr/bin/env bats

setup() {
  unset CODEX_HOME
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SYNC_COMMAND="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  # This file tests the generic file-merge mechanics with minimal, non-real
  # config fixtures; the ponytail plugin-sync step is unrelated to that and,
  # left enabled, would both dial out to the real network and persist
  # marketplace state back into config.toml, breaking the exact `cmp` checks
  # throughout this file. An explicitly empty source skips it entirely.
  export PONYTAIL_MARKETPLACE_SOURCE=""
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  PLUGIN_SYNC_BIN="$BATS_TEST_TMPDIR/plugin-sync-bin"
  PLUGIN_SYNC_LOG="$BATS_TEST_TMPDIR/plugin-sync.log"
  mkdir -p "$PLUGIN_SYNC_BIN"
  cat >"$PLUGIN_SYNC_BIN/sync-skills-plugin" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" >>"$PLUGIN_SYNC_LOG"
printf '\0' >>"$PLUGIN_SYNC_LOG"
if [ "${FAIL_SKILLS_PLUGIN_SYNC:-}" = "1" ]; then
  exit 1
fi
if [ "${PLUGIN_SYNC_APPEND_CONFIG:-}" = "1" ]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--codex-home" ]; then
      codex_home="$2"
      printf '\n[plugins."fixture-after-sync@fixture"]\nenabled = true\n' >>"$codex_home/config.toml"
      shift 2
    else
      shift
    fi
  done
fi
SH
  chmod +x "$PLUGIN_SYNC_BIN/sync-skills-plugin"
  export PLUGIN_SYNC_LOG
  export PATH="$PLUGIN_SYNC_BIN:$PATH"
  mkdir -p "$TEST_HOME/.config/codex/rules" "$TEST_HOME/.config/codex/environments"
  printf 'model = "managed"\n' >"$TEST_HOME/.config/codex/config.toml"
  printf '{"hooks":{}}\n' >"$TEST_HOME/.config/codex/hooks.json"
  printf '# managed rules\n' >"$TEST_HOME/.config/codex/rules/default.rules"
  printf 'name = "default"\n' >"$TEST_HOME/.config/codex/environments/environment.toml"
  printf '# Managed instructions\n' >"$TEST_HOME/.config/codex/AGENTS.md"
}

assert_managed_home() {
  local codex_home="$1"
  local relative_path
  for relative_path in config.toml hooks.json rules/default.rules environments/environment.toml AGENTS.md; do
    cmp "$TEST_HOME/.config/codex/$relative_path" "$codex_home/$relative_path"
    [ "$(stat -c %a "$codex_home/$relative_path")" = "600" ]
  done
}

@test "Codex 管理設定 syncs all files to native home without creating Desktop home" {
  env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  [ ! -d "$TEST_HOME/.codex-app" ]
}

@test "Codex 管理設定の同期は skills.config のテーブル配列を保持する" {
  mkdir -p "$TEST_HOME/.codex"
  cat >"$TEST_HOME/.codex/config.toml" <<'TOML'
model = "local"
[[skills.config]]
path = "/public/skill one/SKILL.md"
enabled = false
[[skills.config]]
path = "/public/日本語/SKILL.md"
enabled = true
TOML

  run env HOME="$TEST_HOME" bash "$SYNC_COMMAND"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  python3 - "$TEST_HOME/.codex/config.toml" <<'PY'
import sys, tomllib
from pathlib import Path
config = tomllib.loads(Path(sys.argv[1]).read_text())
assert config['model'] == 'managed'
assert config['skills']['config'] == [
    {'path': '/public/skill one/SKILL.md', 'enabled': False},
    {'path': '/public/日本語/SKILL.md', 'enabled': True},
]
PY
  cmp "$TEST_HOME/.config/codex/AGENTS.md" "$TEST_HOME/.codex/AGENTS.md"
}

@test "Codex 管理設定 syncs and seeds an existing Desktop home" {
  mkdir -p "$TEST_HOME/.codex-app"
  env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  assert_managed_home "$TEST_HOME/.codex-app"
  [ -f "$TEST_HOME/.codex-app/.managed-config-seeded" ]
}

@test "Codex 管理設定 syncs native and explicit CODEX_HOME including WSL" {
  local codex_home="$BATS_TEST_TMPDIR/custom codex home"
  mkdir -p "$TEST_HOME/.codex-app"
  HOME="$TEST_HOME" CODEX_HOME="$codex_home" WSL_DISTRO_NAME=Ubuntu-24.04 bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  assert_managed_home "$codex_home"
  python3 - "$PLUGIN_SYNC_LOG" "$TEST_HOME" "$codex_home" <<'PY'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b"\0")
args = [item.decode() for item in args if item]
assert args == ["--codex-home", f"{sys.argv[2]}/.codex", "--codex-home", f"{sys.argv[2]}/.codex-app", "--codex-home", sys.argv[3]]
PY
}

@test "Codex 管理設定 reports required skills plugin sync failure" {
  mkdir -p "$TEST_HOME/.codex"
  printf 'model = "local before plugin sync"\n' >"$TEST_HOME/.codex/config.toml"

  run env -u CODEX_HOME HOME="$TEST_HOME" FAIL_SKILLS_PLUGIN_SYNC=1 bash "$SYNC_COMMAND"

  [ "$status" -ne 0 ]
  [[ "$output" == *"skills-plugin"* ]]
  [ "$(cat "$TEST_HOME/.codex/config.toml")" = 'model = "local before plugin sync"' ]
  [ ! -e "$TEST_HOME/.codex/hooks.json" ]
}

@test "Codex 管理設定 rejects obsolete selectors without writing settings" {
  local selector
  for selector in all config hooks rules environment agents unknown; do
    run env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND" "$selector"
    [ "$status" -eq 2 ]
    [[ "$output" == *'Usage: sync-codex-managed-config'* ]]
    [ ! -e "$TEST_HOME/.codex" ]
  done
}

@test "Codex 管理設定 validates every home before replacing any existing file" {
  mkdir -p "$TEST_HOME/.codex" "$TEST_HOME/.codex-app"
  printf 'model = "local"\n' >"$TEST_HOME/.codex/config.toml"
  printf 'local hooks\n' >"$TEST_HOME/.codex/hooks.json"
  printf 'model = \n' >"$TEST_HOME/.codex-app/config.toml"

  run env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"

  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_HOME/.codex/config.toml")" = 'model = "local"' ]
  [ "$(cat "$TEST_HOME/.codex/hooks.json")" = 'local hooks' ]
  [ "$(cat "$TEST_HOME/.codex-app/config.toml")" = 'model = ' ]
  [ ! -e "$TEST_HOME/.codex/AGENTS.md" ]
  [ ! -e "$TEST_HOME/.codex-app/.managed-config-seeded" ]
  [[ "$output" == *prepare* ]]
  [[ "$output" == *"$TEST_HOME/.codex-app/config.toml"* ]]
  [ -z "$(find "$TEST_HOME" -name '*.tmp.*' -print)" ]
}

@test "Codex 管理設定 leaves existing files untouched when a managed source is missing" {
  mkdir -p "$TEST_HOME/.codex"
  printf 'model = "local"\n' >"$TEST_HOME/.codex/config.toml"
  mv "$TEST_HOME/.config/codex/AGENTS.md" "$BATS_TEST_TMPDIR/retained-AGENTS.md"

  run env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"

  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_HOME/.codex/config.toml")" = 'model = "local"' ]
  [ ! -e "$TEST_HOME/.codex/hooks.json" ]
  [[ "$output" == *prepare* ]]
  [[ "$output" == *"$TEST_HOME/.config/codex/AGENTS.md"* ]]
}

@test "Codex 管理設定 does not replace files when reading a source fails during preparation" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin" "$TEST_HOME/.codex"
  printf 'model = "local"\n' >"$TEST_HOME/.codex/config.toml"
  cat >"$bin/cp" <<'SH'
#!/usr/bin/env bash
echo 'simulated source read failure' >&2
exit 74
SH
  chmod +x "$bin/cp"

  run env -u CODEX_HOME PATH="$bin:$PATH" HOME="$TEST_HOME" bash "$SYNC_COMMAND"

  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_HOME/.codex/config.toml")" = 'model = "local"' ]
  [ ! -e "$TEST_HOME/.codex/hooks.json" ]
  [[ "$output" == *prepare* ]]
  [[ "$output" == *"$TEST_HOME/.codex/hooks.json"* ]]
  [ -z "$(find "$TEST_HOME" -name '*.tmp.*' -print)" ]
}

@test "Codex 管理設定 retains completed replacements and converges after a write failure" {
  local bin="$BATS_TEST_TMPDIR/bin"
  local real_mv
  real_mv="$(command -v mv)"
  mkdir -p "$bin" "$TEST_HOME/.codex-app"
  printf 'local hooks\n' >"$TEST_HOME/.codex-app/hooks.json"
  cat >"$bin/mv" <<'SH'
#!/usr/bin/env bash
if [ "${@: -1}" = "$FAIL_TARGET" ]; then
  echo 'simulated rename failure' >&2
  exit 74
fi
exec "$REAL_MV" "$@"
SH
  chmod +x "$bin/mv"

  run env -u CODEX_HOME PATH="$bin:$PATH" REAL_MV="$real_mv" \
    FAIL_TARGET="$TEST_HOME/.codex-app/hooks.json" HOME="$TEST_HOME" bash "$SYNC_COMMAND"

  [ "$status" -ne 0 ]
  assert_managed_home "$TEST_HOME/.codex"
  [ "$(cat "$TEST_HOME/.codex-app/hooks.json")" = 'local hooks' ]
  [ ! -e "$TEST_HOME/.codex-app/.managed-config-seeded" ]
  [[ "$output" == *apply* ]]
  [[ "$output" == *"$TEST_HOME/.codex-app/hooks.json"* ]]
  [ -z "$(find "$TEST_HOME" -name '*.tmp.*' -print)" ]

  env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  assert_managed_home "$TEST_HOME/.codex-app"
  [ -f "$TEST_HOME/.codex-app/.managed-config-seeded" ]
}

prepare_chezmoi_fixture() {
  CHEZMOI_SOURCE="$BATS_TEST_TMPDIR/source"
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  SYNC_LOG_PATH="$BATS_TEST_TMPDIR/sync.log"
  local spy="$BATS_TEST_TMPDIR/count-sync"
  mkdir -p "$CHEZMOI_SOURCE/private_dot_config" "$CHEZMOI_SOURCE/private_dot_local/bin" \
    "$CHEZMOI_SOURCE/private_dot_config/nix-devshell"
  cp -R "$PROJECT_ROOT/private_dot_config/codex" "$CHEZMOI_SOURCE/private_dot_config/codex"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$CHEZMOI_SOURCE/private_dot_config/nix-devshell/skills-plugin.json"
  cp "$SYNC_COMMAND" "$CHEZMOI_SOURCE/private_dot_local/bin/executable_sync-codex-managed-config"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-skills-plugin" \
    "$CHEZMOI_SOURCE/private_dot_local/bin/executable_sync-skills-plugin"
  cp "$PROJECT_ROOT"/run_onchange_after_codex-*.sh.tmpl "$CHEZMOI_SOURCE/"
  printf '{}\n' >"$config"
  cat >"$spy" <<'SH'
#!/usr/bin/env bash
printf 'sync\n' >>"$SYNC_LOG"
exec "$HOME/.local/bin/sync-codex-managed-config" "$@"
SH
  chmod +x "$spy"
  CHEZMOI_APPLY=(env HOME="$TEST_HOME" SYNC_LOG="$SYNC_LOG_PATH" CODEX_MANAGED_CONFIG_SYNC="$spy"
    chezmoi --source "$CHEZMOI_SOURCE" --destination "$TEST_HOME" --config "$config"
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" apply)

}

@test "chezmoi syncs Codex 管理設定 once for each managed source or synchronizer change" {
  prepare_chezmoi_fixture

  run "${CHEZMOI_APPLY[@]}"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$SYNC_LOG_PATH")" -eq 1 ]
  [ ! -d "$TEST_HOME/.codex-app" ]

  local changed count=1
  for changed in private_dot_config/codex/AGENTS.md private_dot_config/codex/config.toml.tmpl \
    private_dot_config/codex/environments/environment.toml private_dot_config/codex/hooks.json \
    private_dot_config/codex/rules/default.rules private_dot_config/nix-devshell/skills-plugin.json \
    private_dot_local/bin/executable_sync-codex-managed-config \
    private_dot_local/bin/executable_sync-skills-plugin; do
    printf '\n' >>"$CHEZMOI_SOURCE/$changed"
    printf 'local drift\n' >"$TEST_HOME/.codex/AGENTS.md"
    run "${CHEZMOI_APPLY[@]}"
    [ "$status" -eq 0 ]
    count=$((count + 1))
    [ "$(wc -l <"$SYNC_LOG_PATH")" -eq "$count" ]
    cmp "$TEST_HOME/.config/codex/AGENTS.md" "$TEST_HOME/.codex/AGENTS.md"
    cmp "$TEST_HOME/.config/codex/hooks.json" "$TEST_HOME/.codex/hooks.json"
    cmp "$TEST_HOME/.config/codex/rules/default.rules" "$TEST_HOME/.codex/rules/default.rules"
    cmp "$TEST_HOME/.config/codex/environments/environment.toml" "$TEST_HOME/.codex/environments/environment.toml"
  done

  run "${CHEZMOI_APPLY[@]}"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$SYNC_LOG_PATH")" -eq "$count" ]
}

@test "Codex permissions read only the verified plugin cache for each managed home" {
  prepare_chezmoi_fixture
  local explicit_home="$BATS_TEST_TMPDIR/explicit-codex-home"
  mkdir -p "$TEST_HOME/.codex-app"

  run env CODEX_HOME="$explicit_home" "${CHEZMOI_APPLY[@]}"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  python3 - "$TEST_HOME/.codex/config.toml" "$TEST_HOME/.codex-app/config.toml" "$explicit_home/config.toml" <<'PY'
import sys, tomllib
from pathlib import Path
for config_path in sys.argv[1:]:
    config = tomllib.loads(Path(config_path).read_text())
    cache_path = str(
        Path(config_path).parent
        / "plugins/cache/treflebonbon/treflebonbon-skills"
    )
    for profile_name in ("dotfiles-secure", "dotfiles-peer"):
        filesystem = config["permissions"][profile_name]["filesystem"]
        assert filesystem[":root"] == "deny"
        assert filesystem[cache_path] == {".": "read"}
        assert "~/.ssh" not in filesystem
        assert str(Path(cache_path).parent.parent) not in filesystem
PY
}

@test "Codex managed sync preserves config changes made by plugin installation" {
  prepare_chezmoi_fixture
  mkdir -p "$TEST_HOME/.codex"
  printf 'model = "local before plugin sync"\n' >"$TEST_HOME/.codex/config.toml"

  run env PLUGIN_SYNC_APPEND_CONFIG=1 "${CHEZMOI_APPLY[@]}"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  grep -Fq '[plugins."fixture-after-sync@fixture"]' "$TEST_HOME/.codex/config.toml"
  grep -Fq 'model = "gpt-6.1-sol"' "$TEST_HOME/.codex/config.toml"
}

@test "Codex 管理設定 repairs target drift and new CODEX_HOME only on explicit sync" {
  prepare_chezmoi_fixture
  "${CHEZMOI_APPLY[@]}"
  printf 'local drift\n' >"$TEST_HOME/.codex/hooks.json"
  local codex_home="$BATS_TEST_TMPDIR/new codex home"

  run env CODEX_HOME="$codex_home" "${CHEZMOI_APPLY[@]}"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$SYNC_LOG_PATH")" -eq 1 ]
  [ "$(cat "$TEST_HOME/.codex/hooks.json")" = 'local drift' ]
  [ ! -d "$codex_home" ]

  HOME="$TEST_HOME" CODEX_HOME="$codex_home" "$TEST_HOME/.local/bin/sync-codex-managed-config"

  cmp "$TEST_HOME/.config/codex/hooks.json" "$TEST_HOME/.codex/hooks.json"
  cmp "$TEST_HOME/.config/codex/AGENTS.md" "$codex_home/AGENTS.md"
  [ -f "$codex_home/config.toml" ]
}

@test "chezmoi retries failed Codex 管理設定 sync until the same source succeeds" {
  prepare_chezmoi_fixture
  "${CHEZMOI_APPLY[@]}"
  mkdir -p "$TEST_HOME/.codex-app"
  printf 'model = \n' >"$TEST_HOME/.codex-app/config.toml"
  printf '\n# Updated instructions\n' >>"$CHEZMOI_SOURCE/private_dot_config/codex/AGENTS.md"
  cp "$TEST_HOME/.codex/AGENTS.md" "$BATS_TEST_TMPDIR/previous-AGENTS.md"

  local attempt
  for attempt in 2 3; do
    run "${CHEZMOI_APPLY[@]}"
    [ "$status" -ne 0 ]
    [ "$(wc -l <"$SYNC_LOG_PATH")" -eq "$attempt" ]
    cmp "$BATS_TEST_TMPDIR/previous-AGENTS.md" "$TEST_HOME/.codex/AGENTS.md"
    [ ! -e "$TEST_HOME/.codex-app/.managed-config-seeded" ]
  done

  printf 'model = "local"\n' >"$TEST_HOME/.codex-app/config.toml"
  "${CHEZMOI_APPLY[@]}"
  [ "$(wc -l <"$SYNC_LOG_PATH")" -eq 4 ]
  cmp "$TEST_HOME/.config/codex/AGENTS.md" "$TEST_HOME/.codex-app/AGENTS.md"
  [ -f "$TEST_HOME/.codex-app/.managed-config-seeded" ]

  "${CHEZMOI_APPLY[@]}"
  [ "$(wc -l <"$SYNC_LOG_PATH")" -eq 4 ]
}
