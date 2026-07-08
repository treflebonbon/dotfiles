#!/usr/bin/env bats
# dot_zshrc.tmpl (macOS 向け zsh config, issue #46) のツール統合を
# 実際の zsh でファイルを source し、スタブしたツールバイナリの呼び出しを
# 検証する。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../dot_zshrc.tmpl"

setup() {
  setup_test_env
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME"
}

run_zshrc() {
  # 末尾に `; true` を付け、ファイル内最後の `command -v X && ...` の真偽
  # （X が PATH に無いだけの不成立）が sourcing 全体の終了コードに漏れて
  # 無関係なテスト失敗を起こさないようにする。
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /usr/bin/zsh -c "source '$SRC'; true"
}

@test "direnv が有効なら direnv hook zsh が呼ばれる" {
  stub_cmd direnv
  run_zshrc
  assert_success
  assert_log_contains "direnv hook zsh"
}

@test "starship が有効なら starship init zsh が呼ばれる" {
  stub_cmd starship
  run_zshrc
  assert_success
  assert_log_contains "starship init zsh"
}

@test "atuin が有効なら atuin init zsh が呼ばれる" {
  stub_cmd atuin
  run_zshrc
  assert_success
  assert_log_contains "atuin init zsh"
}

@test "zoxide が有効なら zoxide init zsh --cmd cd が呼ばれる" {
  stub_cmd zoxide
  run_zshrc
  assert_success
  assert_log_contains "zoxide init zsh --cmd cd"
}

@test "direnv が無ければ direnv hook は呼ばれない" {
  run_zshrc
  assert_success
  refute_log_contains "direnv hook"
}

@test "fzf が有効なら fzf --zsh が呼ばれ Dracula カラーが FZF_DEFAULT_OPTS に設定される" {
  stub_cmd fzf
  run_zshrc
  assert_success
  assert_log_contains "--zsh"
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /usr/bin/zsh -c "source '$SRC'; true; echo \"FZF_DEFAULT_OPTS=\$FZF_DEFAULT_OPTS\""
  assert_success
  assert_output --partial "bg:#282a36"
}

# --- ghq + fzf リポジトリ管理 ---

query_functions_defined() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /usr/bin/zsh -c "source '$SRC'; true; whence -f gcd gclone gedit gweb ginit"
}

@test "ghq と fzf が両方あれば gcd/gclone/gedit/gweb/ginit が定義される" {
  stub_cmd ghq
  stub_cmd fzf
  query_functions_defined
  assert_success
  assert_output --partial "gcd"
  assert_output --partial "gclone"
  assert_output --partial "gedit"
  assert_output --partial "gweb"
  assert_output --partial "ginit"
}

@test "ghq が無ければ gcd 等は定義されない" {
  stub_cmd fzf
  query_functions_defined
  assert_failure
}

@test "fzf が無ければ gcd 等は定義されない" {
  stub_cmd ghq
  query_functions_defined
  assert_failure
}

@test "Ctrl-G (^G) が gcd を呼ぶ widget にバインドされる" {
  stub_cmd ghq
  stub_cmd fzf
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /usr/bin/zsh -c "source '$SRC'; true; bindkey '^G'"
  assert_success
  assert_output --partial "gcd"
}

@test "gcd は ghq list | fzf の選択結果へ実際に cd する" {
  stub_cmd ghq
  # ghq list はダミーの1行、ghq root はテスト用ディレクトリを返す
  cat >"$TEST_BIN_DIR/ghq" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
case "$1" in
  list) echo "github.com/example/repo" ;;
  root) echo "$GHQ_ROOT_FOR_TEST" ;;
esac
STUB_EOF
  chmod +x "$TEST_BIN_DIR/ghq"
  # fzf は標準入力の1行目をそのまま選択結果として返すダミー（隔離 PATH に
  # head が無いため shell 内蔵の read で代用する）
  cat >"$TEST_BIN_DIR/fzf" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
IFS= read -r line
echo "$line"
STUB_EOF
  chmod +x "$TEST_BIN_DIR/fzf"
  mkdir -p "$FAKE_HOME/repo-root/github.com/example/repo"

  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    GHQ_ROOT_FOR_TEST="$FAKE_HOME/repo-root" \
    /usr/bin/zsh -c "source '$SRC'; true; gcd && pwd"
  assert_success
  assert_output --partial "$FAKE_HOME/repo-root/github.com/example/repo"
}

# --- zsh-autosuggestions / zsh-syntax-highlighting（nixpkgs から直接 source） ---

write_fake_plugin() {
  local path="$1" marker="$2"
  echo "echo \"$marker\" >> \"\$TEST_LOG\"" >"$path"
}

@test "両方の env var が設定されていれば autosuggestions → syntax-highlighting の順で source される" {
  write_fake_plugin "$FAKE_HOME/fake-autosuggestions.zsh" "AUTOSUGGESTIONS_SOURCED"
  write_fake_plugin "$FAKE_HOME/fake-syntax-highlighting.zsh" "SYNTAX_HIGHLIGHTING_SOURCED"

  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    ZSH_AUTOSUGGESTIONS_SHARE="$FAKE_HOME/fake-autosuggestions.zsh" \
    ZSH_SYNTAX_HIGHLIGHTING_SHARE="$FAKE_HOME/fake-syntax-highlighting.zsh" \
    /usr/bin/zsh -c "source '$SRC'; true"
  assert_success
  assert_log_contains "AUTOSUGGESTIONS_SOURCED"
  assert_log_contains "SYNTAX_HIGHLIGHTING_SOURCED"

  local autosuggestions_line syntax_line
  autosuggestions_line=$(grep -n "AUTOSUGGESTIONS_SOURCED" "$TEST_LOG" | cut -d: -f1)
  syntax_line=$(grep -n "SYNTAX_HIGHLIGHTING_SOURCED" "$TEST_LOG" | cut -d: -f1)
  [ "$autosuggestions_line" -lt "$syntax_line" ]
}

@test "env var が未設定なら何も source されない（エラーにもならない）" {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /usr/bin/zsh -c "source '$SRC'; true"
  assert_success
  refute_log_contains "SOURCED"
}
