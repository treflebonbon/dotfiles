#!/usr/bin/env bats

setup() {
  unset CODEX_HOME
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SYNC_COMMAND="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
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

@test "Codex 管理設定 syncs and seeds an existing Desktop home" {
  mkdir -p "$TEST_HOME/.codex-app"
  env -u CODEX_HOME HOME="$TEST_HOME" bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  assert_managed_home "$TEST_HOME/.codex-app"
  [ -f "$TEST_HOME/.codex-app/.managed-config-seeded" ]
}

@test "Codex 管理設定 syncs native and explicit CODEX_HOME including WSL" {
  local codex_home="$BATS_TEST_TMPDIR/custom codex home"
  HOME="$TEST_HOME" CODEX_HOME="$codex_home" WSL_DISTRO_NAME=Ubuntu-24.04 bash "$SYNC_COMMAND"
  assert_managed_home "$TEST_HOME/.codex"
  assert_managed_home "$codex_home"
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
  mkdir -p "$CHEZMOI_SOURCE/private_dot_config" "$CHEZMOI_SOURCE/private_dot_local/bin"
  cp -R "$PROJECT_ROOT/private_dot_config/codex" "$CHEZMOI_SOURCE/private_dot_config/codex"
  cp "$SYNC_COMMAND" "$CHEZMOI_SOURCE/private_dot_local/bin/executable_sync-codex-managed-config"
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
    private_dot_config/codex/rules/default.rules private_dot_local/bin/executable_sync-codex-managed-config; do
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
