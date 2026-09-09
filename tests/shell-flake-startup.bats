#!/usr/bin/env bats
# shellcheck disable=SC2016 # Commands and cache expressions expand in the child shell.

load 'test_helper'

setup() {
  setup_test_env
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/lib" "$FAKE_HOME/.cache" "$FAKE_HOME/tools" "$FAKE_HOME/project"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/lib/ensure-env.sh" "$FAKE_HOME/.config/nix-devshell/lib/"
  env HOME="$FAKE_HOME" chezmoi execute-template --config /dev/null --config-format toml --source "$PROJECT_ROOT" --destination "$FAKE_HOME" \
    --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" \
    --override-data '{"workspace_folder":"/nonexistent-workspace"}' \
    <"$PROJECT_ROOT/dot_bashrc.tmpl" >"$FAKE_HOME/.bashrc"
  env HOME="$FAKE_HOME" chezmoi execute-template --config /dev/null --config-format toml --source "$PROJECT_ROOT" --destination "$FAKE_HOME" \
    --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" \
    <"$PROJECT_ROOT/dot_zshrc.tmpl" >"$FAKE_HOME/.zshrc"
  printf 'export PATH="%s/tools:$PATH"\n' "$FAKE_HOME" >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf '#!/bin/bash\necho common-tool-ok\n' >"$FAKE_HOME/tools/common-tool"
  chmod +x "$FAKE_HOME/tools/common-tool"
  stub_cmd nix
  stub_cmd direnv
}

check_startup() {
  local shell="$1"
  run env -i HOME="$FAKE_HOME" ZDOTDIR="$FAKE_HOME" PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    NIX_PROFILES=fixture TEST_LOG="$TEST_LOG" TERM=dumb \
    "$shell" -ic 'cd "$HOME/project"; common-tool; command -v direnv'
  assert_success
  assert_output --partial common-tool-ok
  assert_output --partial "$TEST_BIN_DIR/direnv"
  refute_log_contains 'direnv'
  refute_log_contains 'nix print-dev-env'
}

@test "standard bash startup keeps cached tools without running direnv" {
  check_startup /bin/bash
}

@test "standard zsh startup keeps cached tools without running direnv" {
  local zsh
  zsh="$(command -v zsh)" || skip 'zsh not installed'
  check_startup "$zsh"
}
