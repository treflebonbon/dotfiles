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

run_bashrc_with_flyline() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    FLYLINE_BASH_LOADABLE="$GENERATED_BASHRC" \
    TERM="${TERM:-xterm}" \
    /bin/bash --noprofile --norc -i -c '
      enable() {
        if [ "${1:-}" = "-f" ] && [ "${3:-}" = "flyline" ]; then
          flyline() { printf "flyline %s\\n" "$*" >> "$TEST_LOG"; }
          return 0
        fi
        builtin enable "$@"
      }
      source "'"$GENERATED_BASHRC"'"
      bind -X
    '
}

run_bashrc_with_preloaded_flyline() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    TERM="${TERM:-xterm}" \
    /bin/bash --noprofile --norc -i -c '
      type() {
        if [ "${1:-}" = "-t" ] && [ "${2:-}" = "flyline" ]; then
          printf "%s\\n" builtin
          return 0
        fi
        builtin type "$@"
      }
      flyline() { printf "flyline %s\\n" "$*" >> "$TEST_LOG"; }
      enable() {
        printf "enable %s\\n" "$*" >> "$TEST_LOG"
        builtin enable "$@"
      }
      source "'"$GENERATED_BASHRC"'"
      bind -X
    '
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

@test "bashrc strips bash prompt markers from starship prompt when bash lacks readline bind builtin" {
  cat >"$TEST_BIN_DIR/starship" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [ "${1:-}" = "init" ] && [ "${2:-}" = "bash" ]; then
  cat <<'INIT_EOF'
starship_precmd() {
  PS1='\[\e[31m\]PROMPT\[\e[0m\] '
}
PROMPT_COMMAND=starship_precmd
INIT_EOF
fi
STUB_EOF
  chmod +x "$TEST_BIN_DIR/starship"

  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    TERM="${TERM:-xterm}" \
    /bin/bash --noprofile --norc -i -c "enable -n bind; source '$GENERATED_BASHRC'; starship_precmd; printf '%s' \"\$PS1\""

  assert_success
  assert_output --partial "PROMPT"
  refute_output --partial "\\["
  refute_output --partial "\\]"
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

@test "flyline uses Ctrl-G to insert gcd on an empty command line" {
  stub_cmd ghq
  stub_cmd fzf

  run_bashrc_with_flyline

  assert_success
  assert_log_contains "flyline key bind Ctrl+g bufferIsEmpty=insertString(gcd)"
  refute_output --partial '"\C-g": "gcd"'
}

@test "preloaded flyline uses Ctrl-G without reloading the builtin" {
  stub_cmd ghq
  stub_cmd fzf

  run_bashrc_with_preloaded_flyline

  assert_success
  assert_log_contains "flyline key bind Ctrl+g bufferIsEmpty=insertString(gcd)"
  refute_log_contains "enable -f"
  refute_output --partial '"\C-g": "gcd"'
}

@test "bash fallback keeps Ctrl-G bound to gcd" {
  stub_cmd ghq
  stub_cmd fzf

  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    TERM="${TERM:-xterm}" \
    /bin/bash --noprofile --norc -i -c "source '$GENERATED_BASHRC'; bind -X"

  assert_success
  assert_output --partial '"\C-g": "gcd"'
}

@test "bashrc config disables flyline mouse capture and does not configure agent mode (issue #53)" {
  grep -q 'flyline mouse --mode disabled' "$SRC"
  ! grep -q 'set-agent-mode' "$SRC"
}
