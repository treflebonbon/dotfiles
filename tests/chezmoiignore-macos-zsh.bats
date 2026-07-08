#!/usr/bin/env bats
# dot_zshrc.tmpl (~/.zshrc) が macOS (darwin) 限定で chezmoi に管理されるかを検証する
# （issue #46: macOS 向け zsh config の OS 分岐）。
#
# `chezmoi execute-template --file .chezmoiignore` はテンプレートのテキスト
# レンダリング結果を返すだけで、chezmoi の実際の ignore パターンマッチング
# （ソースファイル名 `dot_zshrc.tmpl` ではなくターゲット相対パス `.zshrc` で
# マッチする）を検証しない。実際に適用される挙動を見るため `chezmoi managed`
# を使う。

load 'test_helper'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP_CACHE="$BATS_TEST_TMPDIR/cache"
  TMP_STATE="$BATS_TEST_TMPDIR/state.boltdb"
  mkdir -p "$TMP_CACHE"
}

managed_for_os() {
  local os="$1"
  chezmoi managed --source "$PROJECT_ROOT" \
    --cache "$TMP_CACHE" \
    --persistent-state "$TMP_STATE" \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}"
}

@test "darwin では .zshrc が chezmoi 管理対象になる（配備される）" {
  run managed_for_os darwin
  assert_success
  assert_line ".zshrc"
}

@test "linux では .zshrc が chezmoi 管理対象にならない（配備されない）" {
  run managed_for_os linux
  assert_success
  refute_line ".zshrc"
}

@test "linux では .bashrc は引き続き chezmoi 管理対象のまま（回帰なし）" {
  run managed_for_os linux
  assert_success
  assert_line ".bashrc"
}
