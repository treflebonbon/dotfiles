#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env

  # 前提: git curl がある
  stub_cmd git
  stub_cmd curl

  # 依存で使われるコマンドをスタブ
  stub_cmd chezmoi
  stub_cmd nix
  stub_cmd direnv
  stub_cmd sudo

  # install.sh が使う基本コマンド
  stub_real_cmd dirname
  stub_real_cmd pwd
  stub_cmd cd
  stub_cmd echo
  stub_cmd hash
  stub_cmd sh
  stub_real_cmd mkdir
  stub_real_cmd grep
  # OS 判定（既定は実環境の判定を使う。macOS 分岐のテストでは個別に上書きする）
  stub_real_cmd uname
  stub_real_cmd rm
  stub_real_cmd mv
  stub_cmd gh
}

# =============================================================================
# 前提条件チェック
# =============================================================================

@test "git がない場合はエラー終了" {
  unstub_cmd git

  run_install

  assert_failure
  assert_output --partial "git is required"
}

@test "curl がない場合はエラー終了" {
  unstub_cmd curl

  run_install

  assert_failure
  assert_output --partial "curl is required"
}

# =============================================================================
# gh (GitHub CLI) soft prerequisite
# =============================================================================

@test "gh がない場合は warning を表示して続行" {
  unstub_cmd gh

  run_install

  assert_success
  assert_output --partial "Warning: gh (GitHub CLI) is not installed"
}

@test "gh がある場合は warning を表示しない" {
  run_install

  assert_success
  refute_output --partial "Warning: gh"
}

# =============================================================================
# chezmoi インストール
# =============================================================================

@test "chezmoi が PATH にある場合 sideload しない" {
  run_install

  assert_success
  refute_log_contains "get.chezmoi.io"
}

@test "chezmoi が nix store にある場合 PATH に追加して使う" {
  unstub_cmd chezmoi
  local fake_store="$BATS_TEST_TMPDIR/nix/store"
  mkdir -p "$fake_store/abc123-chezmoi-2.70.2/bin"
  cat >"$fake_store/abc123-chezmoi-2.70.2/bin/chezmoi" <<'STUB'
#!/bin/bash
echo "store-chezmoi $*" >> "$TEST_LOG"
STUB
  chmod +x "$fake_store/abc123-chezmoi-2.70.2/bin/chezmoi"
  export NIX_STORE_PREFIX="$fake_store"

  run_install

  assert_success
  assert_log_contains "store-chezmoi"
  refute_log_contains "get.chezmoi.io"
}

@test "PATH/store どちらにも無い場合 sideload する" {
  unstub_cmd chezmoi
  export NIX_STORE_PREFIX="$BATS_TEST_TMPDIR/empty-store"

  run_install

  assert_log_contains "curl"
  assert_log_contains "get.chezmoi.io"
}

@test "chezmoi インストール後も見つからない場合はエラー終了" {
  unstub_cmd chezmoi
  export NIX_STORE_PREFIX="$BATS_TEST_TMPDIR/empty-store"

  run_install

  assert_failure
  assert_output --partial "chezmoi installation failed"
}

# =============================================================================
# Nix インストール
# =============================================================================

@test "nix が既存の場合はインストールをスキップ" {
  run_install

  assert_success
  refute_log_contains "artifacts.nixos.org"
}

@test "nix が未存在の場合はインストールを試行" {
  unstub_cmd nix

  run_install

  assert_log_contains "curl"
  assert_log_contains "artifacts.nixos.org"
}

@test "nix インストール時に Numtide キャッシュが設定される" {
  unstub_cmd nix

  run_install

  assert_log_contains "extra-conf"
  assert_log_contains "cache.numtide.com"
}

@test "nix インストール時に flakes が --extra-conf で有効化される" {
  unstub_cmd nix

  run_install

  assert_log_contains "extra-experimental-features = nix-command flakes"
}

@test "nix インストール時に --init none で systemd 統合を無効化する" {
  unstub_cmd nix

  run_install

  assert_log_contains "--init none"
}

@test "macOS (Darwin) では nix-installer に macos プランナーを使い --init を渡さない" {
  unstub_cmd nix
  stub_cmd_with_output uname Darwin

  run_install

  assert_log_contains "install macos"
  refute_log_contains "install linux"
  refute_log_contains "--init none"
  assert_log_contains "cache.numtide.com"
}

@test "Linux (uname 明示モック) では linux プランナー + --init none を使う（回帰なし）" {
  unstub_cmd nix
  stub_cmd_with_output uname Linux

  run_install

  assert_log_contains "install linux"
  refute_log_contains "install macos"
  assert_log_contains "--init none"
  assert_log_contains "cache.numtide.com"
}

@test "NIX_CONFIG env で flakes をスクリプトスコープに付与" {
  stub_cmd_with_env nix NIX_CONFIG

  run_install

  assert_success
  assert_log_contains "NIX_CONFIG=extra-experimental-features = nix-command flakes"
}

# =============================================================================
# python3 ブートストラップ（run_onchange スクリプトの codex-config.sh 等が
# devShell 評価より前の chezmoi init --apply 時点で必要とする）
# =============================================================================

@test "python3 がない場合 nix profile 経由でインストールする" {
  run_install

  assert_success
  assert_log_contains "nix profile add nixpkgs#python3"
}

@test "python3 がある場合はインストールをスキップする" {
  stub_cmd python3

  run_install

  assert_success
  refute_log_contains "nix profile add nixpkgs#python3"
}

# =============================================================================
# 環境変数
# =============================================================================

@test "デフォルト環境変数が設定される" {
  run_install

  assert_success
  assert_output --partial "WORKSPACE_FOLDER:"
}

@test "DOTFILES_* 環境変数が優先される" {
  export DOTFILES_WORKSPACE_FOLDER="/custom/workspace"

  run_install

  assert_success
  assert_output --partial "/custom/workspace"
}

# =============================================================================
# chezmoi apply
# =============================================================================

@test "chezmoi init --source --apply --force が呼ばれる" {
  run_install

  assert_success
  assert_log_contains "chezmoi init"
  assert_log_contains "--source="
  assert_log_contains "--apply"
  assert_log_contains "--force"
}

# =============================================================================
# flake devShell セットアップ
# =============================================================================

@test "user devShell の初回評価が呼ばれる" {
  # nix develop は $HOME/.config/nix-devshell/flake.nix が存在する場合のみ実行
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/nix-devshell"
  touch "$test_home/.config/nix-devshell/flake.nix"

  run_install

  assert_success
  assert_log_contains "nix develop --command true"
}

@test "install.sh は refresh-cache lib を source して呼ぶ" {
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/nix-devshell/lib"
  touch "$test_home/.config/nix-devshell/flake.nix"
  cat >"$test_home/.config/nix-devshell/lib/refresh-cache.sh" <<'STUB'
#!/usr/bin/env bash
refresh_nix_devshell_cache() {
  echo "REFRESH_CALLED" >> "$TEST_LOG"
}
STUB

  run_install

  assert_success
  assert_log_contains "REFRESH_CALLED"
}

@test "direnv allow が ~/.config/nix-devshell で呼ばれる" {
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/nix-devshell"
  touch "$test_home/.config/nix-devshell/flake.nix"

  run_install

  assert_success
  assert_log_contains "direnv allow"
  assert_log_contains ".config/nix-devshell"
}
