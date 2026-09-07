#!/usr/bin/env bats

load 'test_helper'
load 'local-skills-helper'

setup() {
  setup_test_env
  setup_local_skills_fixture
  local cmd
  for cmd in find grep mkdir mv rm tee cat dirname mktemp date sha256sum tail readlink; do
    stub_real_cmd "$cmd"
  done
  mkdir -p "$SKILL_HOME/.config/nix-devshell/lib" "$SKILL_HOME/.cache"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/lib/"{refresh-cache,ensure-env}.sh \
    "$SKILL_HOME/.config/nix-devshell/lib/"
  touch "$SKILL_HOME/.config/nix-devshell/flake.nix"
  echo 'export CACHE_VERSION=old' >"$SKILL_HOME/.cache/nix-devshell-global-env.bash"
  touch -t 202001010000 "$SKILL_HOME/.cache/nix-devshell-global-env.bash"
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  cat >"$TEST_BIN_DIR/apm" <<'STUB'
#!/bin/bash
echo "apm $* CACHE_VERSION=${CACHE_VERSION:-}" >> "$TEST_LOG"
STUB
  chmod +x "$TEST_BIN_DIR/apm"
  APM_SCRIPT="$BATS_TEST_TMPDIR/apm-install.sh"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_after_apm-install.sh.tmpl" >"$APM_SCRIPT"
}

run_apm_deployment() {
  run /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$SKILL_HOME" TEST_LOG="$TEST_LOG" \
    /bin/bash "$APM_SCRIPT"
}

@test "APM 配備は更新したキャッシュを読み込んで install と prune を実行する" {
  run_apm_deployment

  assert_success
  assert_log_contains 'apm install --frozen --target claude,codex --https CACHE_VERSION=fresh'
  assert_log_contains 'apm prune CACHE_VERSION=fresh'
}

@test "APM 配備は Nix の途中出力を伴う失敗で後続処理を止める" {
  echo 'exit 23' >>"$TEST_BIN_DIR/nix"

  run_apm_deployment

  assert_failure
  [ "$(cat "$SKILL_HOME/.cache/nix-devshell-global-env.bash")" = 'export CACHE_VERSION=old' ]
  refute_log_contains 'apm install'
  refute_log_contains 'apm prune'
}

@test "APM 配備は必要な lib や Nix が無ければ旧キャッシュがあっても止まる" {
  local prerequisite
  for prerequisite in "$SKILL_HOME/.config/nix-devshell/lib/refresh-cache.sh" "$TEST_BIN_DIR/nix"; do
    mv "$prerequisite" "$BATS_TEST_TMPDIR/held-prerequisite"

    run_apm_deployment

    assert_failure
    refute_log_contains 'apm install'
    refute_log_contains 'apm prune'
    mv "$BATS_TEST_TMPDIR/held-prerequisite" "$prerequisite"
  done
}

@test "配備入口は非 Nix 入力変更を反映し同じ入力を再評価しない" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  run_apm_deployment
  assert_success
  : >"$TEST_LOG"
  run_apm_deployment
  assert_success
  refute_log_contains 'nix print-dev-env'

  printf 'package input\n' >"$SKILL_HOME/.config/nix-devshell/asset.json"
  : >"$TEST_LOG"
  run_apm_deployment
  assert_success
  assert_log_contains 'nix print-dev-env'
}
