#!/usr/bin/env bats

setup() {
  export NVIM_CONFIG_SOURCE="$BATS_TEST_DIRNAME/../private_dot_config/nvim"
}

@test "Treesitter の設定を読み込み、標準 API で選択を拡大・縮小できる" {
  run env -u NVIM_TREESITTER_RUNTIME nvim --clean --headless \
    -l "$BATS_TEST_DIRNAME/helpers/nvim-treesitter.lua"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "固定版 Treesitter の実 API でも設定と選択が動く" {
  [[ -n "${NVIM_TREESITTER_RUNTIME:-}" ]] || skip "実 plugin の checkout を NVIM_TREESITTER_RUNTIME に指定してください"
  run nvim --clean --headless -l "$BATS_TEST_DIRNAME/helpers/nvim-treesitter.lua"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
