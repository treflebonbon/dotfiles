#!/usr/bin/env bash
# install.sh テスト用ヘルパー（PATH スタブ + ログファイル方式）

# bats libs (bats.withLibraries で自動設定される)
bats_load_library bats-support
bats_load_library bats-assert

export TEST_BIN_DIR="$BATS_TEST_TMPDIR/bin"
export TEST_LOG="$BATS_TEST_TMPDIR/calls.log"

setup_test_env() {
  mkdir -p "$TEST_BIN_DIR"
  : >"$TEST_LOG"

  # set -u 対策のデフォルト
  export SHELL="/bin/bash"

  # 環境変数をクリア
  unset DOTFILES_WORKSPACE_FOLDER
  unset WORKSPACE_FOLDER
}

# スタブ生成: 指定名のコマンドが呼ばれたらログに残す
stub_cmd() {
  local name="$1"
  local exit_code="${2:-0}"
  cat >"$TEST_BIN_DIR/$name" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
STUB_EOF
  echo "exit $exit_code" >>"$TEST_BIN_DIR/$name"
  chmod +x "$TEST_BIN_DIR/$name"
}

# 実コマンドへ委譲するスタブ生成（ログは残す）
stub_real_cmd() {
  local name="$1"
  local path="/bin/$name"
  if [ ! -x "$path" ]; then
    path="/usr/bin/$name"
  fi
  {
    printf '%s\n' '#!/bin/bash'
    # shellcheck disable=SC2016 # generated stub should expand these at runtime
    printf '%s\n' 'echo "$0 $*" >> "$TEST_LOG"'
    printf 'exec "%s" "$@"\n' "$path"
  } >"$TEST_BIN_DIR/$name"
  chmod +x "$TEST_BIN_DIR/$name"
}

# 実コマンドへ委譲しないスタブ。引数 2 番目以降に渡された env vars を log にも dump する
# 例: stub_cmd_with_env nix NIX_CONFIG  → nix 呼び出し時に "NIX_CONFIG=<value>" を TEST_LOG に追記
stub_cmd_with_env() {
  local name="$1"
  shift
  {
    printf '%s\n' '#!/bin/bash'
    # shellcheck disable=SC2016 # generated stub should expand at runtime
    printf '%s\n' 'echo "$0 $*" >> "$TEST_LOG"'
    for ev in "$@"; do
      # shellcheck disable=SC2016
      printf 'echo "%s=${%s:-}" >> "$TEST_LOG"\n' "$ev" "$ev"
    done
    printf 'exit 0\n'
  } >"$TEST_BIN_DIR/$name"
  chmod +x "$TEST_BIN_DIR/$name"
}

# スタブ削除（存在判定を落とす）
unstub_cmd() {
  rm -f "$TEST_BIN_DIR/$1"
}

# ログにパターンが含まれるか確認
assert_log_contains() {
  grep -q -- "$1" "$TEST_LOG" || {
    echo "Expected log to contain: $1"
    echo "Actual log:"
    cat "$TEST_LOG"
    return 1
  }
}

# ログにパターンが含まれないか確認
refute_log_contains() {
  ! grep -q -- "$1" "$TEST_LOG" || {
    echo "Expected log NOT to contain: $1"
    echo "Actual log:"
    cat "$TEST_LOG"
    return 1
  }
}

# install.sh 実行（PATH と HOME を隔離した状態で）
run_install() {
  # HOME を一時ディレクトリに設定（~/.local/bin の実コマンドを隔離）
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.local/bin"

  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$test_home" \
    SHELL="$SHELL" \
    TEST_LOG="$TEST_LOG" \
    DOTFILES_WORKSPACE_FOLDER="${DOTFILES_WORKSPACE_FOLDER:-}" \
    NIX_STORE_PREFIX="${NIX_STORE_PREFIX:-/nix/store}" \
    /bin/bash "$BATS_TEST_DIRNAME/../install.sh"
}
