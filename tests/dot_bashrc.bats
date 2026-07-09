#!/usr/bin/env bats
# dot_bashrc.tmpl の bash shell ownership を、source 可能な生成済み bashrc と
# スタブコマンドで検証する。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../dot_bashrc.tmpl"

setup() {
  setup_test_env
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  export GENERATED_BASHRC="$BATS_TEST_TMPDIR/bashrc"
  mkdir -p "$FAKE_HOME"
  sed "s#{{ .workspace_folder }}#$BATS_TEST_TMPDIR/workspace#g" "$SRC" >"$GENERATED_BASHRC"
  mkdir -p "$BATS_TEST_TMPDIR/workspace"
}

run_bashrc() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    FLYLINE_BASH_LOADABLE="${FLYLINE_BASH_LOADABLE:-}" \
    TERM="${TERM:-xterm}" \
    /bin/bash --noprofile --norc -i -c "source '$GENERATED_BASHRC'; true"
}

@test "bashrc skips completion/keybinding init when current bash lacks programmable completion builtins" {
  local path_bash
  path_bash="$(command -v bash)"

  run "$path_bash" -lc 'shopt -q progcomp && enable -p | grep -qx "enable complete" && enable -p | grep -qx "enable bind"'
  if [ "$status" -eq 0 ]; then
    skip "PATH bash has programmable completion/readline builtins"
  fi

  run /usr/bin/env -i \
    PATH="$PATH" \
    HOME="$FAKE_HOME" \
    TERM="${TERM:-xterm}" \
    "$path_bash" --noprofile --rcfile "$GENERATED_BASHRC" -ic "true"

  assert_success
  refute_output --partial "shopt: progcomp: invalid shell option name"
  refute_output --partial "complete: command not found"
  refute_output --partial "bind: command not found"
}

@test "bash initializes fzf/zoxide/starship and does not initialize atuin or ble.sh (issue #53)" {
  stub_cmd fzf
  stub_cmd zoxide
  stub_cmd starship
  stub_cmd atuin
  stub_cmd blesh-share

  run_bashrc
  assert_success
  assert_log_contains "fzf --bash"
  assert_log_contains "zoxide init bash --cmd cd"
  assert_log_contains "starship init bash"
  refute_log_contains "atuin init bash"
  refute_log_contains "blesh-share"
}

@test "bash sources bash-preexec when present (issue #53)" {
  mkdir -p "$FAKE_HOME/.config/bash"
  echo 'echo "BASH_PREEXEC_SOURCED" >> "$TEST_LOG"' >"$FAKE_HOME/.config/bash/bash-preexec.sh"

  run_bashrc
  assert_success
  assert_log_contains "BASH_PREEXEC_SOURCED"
}

@test "flyline load failure warns and bash startup continues (issue #53)" {
  export FLYLINE_BASH_LOADABLE="$BATS_TEST_TMPDIR/missing/libflyline.so"

  run_bashrc
  assert_success
  assert_output --partial "Warning: flyline load failed"
}

@test "bashrc config disables flyline mouse capture and does not configure agent mode (issue #53)" {
  grep -q 'flyline mouse --mode disabled' "$SRC"
  ! grep -q 'set-agent-mode' "$SRC"
}
