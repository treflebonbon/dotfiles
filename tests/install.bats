#!/usr/bin/env bats

load 'test_helper'
load 'cache-deployment-concurrency-helper'

setup() {
  setup_test_env

  # 前提: git curl がある
  stub_cmd git
  stub_cmd curl

  # 依存で使われるコマンドをスタブ
  stub_cmd chezmoi
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "nix $*" >> "$TEST_LOG"
echo "NIX_CONFIG=${NIX_CONFIG:-}" >> "$TEST_LOG"
if [ "$1" = print-dev-env ]; then
  echo 'export CACHE_VERSION=fresh'
fi
STUB
  chmod +x "$TEST_BIN_DIR/nix"
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
  # OS 判定。既定は Linux に固定する（実ホストの uname に委譲すると、Darwin の
  # CI ランナーで実行した場合に既存の Linux 前提テスト（--init none 等）が
  # macOS 分岐を通ってしまい壊れるため。macOS 分岐のテストでは個別に上書きする）
  stub_cmd_with_output uname Linux
  stub_real_cmd rm
  stub_real_cmd mv
  stub_cmd gh

  # chezmoi が配備する入力を用意し、キャッシュ生成は実際の lib を通す。
  local test_home="$BATS_TEST_TMPDIR/home" cmd
  mkdir -p "$test_home/.config/nix-devshell/lib"
  touch "$test_home/.config/nix-devshell/flake.nix"
  cp "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/refresh-cache.sh" \
    "$test_home/.config/nix-devshell/lib/refresh-cache.sh"
  for cmd in find cat tee mktemp date tail readlink perl; do
    stub_real_cmd "$cmd"
  done
  stub_hash_cmd
  # Nix installer 成功後の PATH 読込みでもホストの nix を使わない。
  cp "$TEST_BIN_DIR/nix" "$test_home/nix-adapter"
  cat >"$TEST_BIN_DIR/sh" <<'STUB'
#!/bin/bash
echo "sh $*" >> "$TEST_LOG"
if [[ "$*" == *--extra-conf* ]]; then
  /bin/mkdir -p "$HOME/.nix-profile/bin" "$HOME/.local/bin"
  /bin/cp "$HOME/nix-adapter" "$HOME/.nix-profile/bin/nix"
  /bin/cp "$HOME/nix-adapter" "$HOME/.local/bin/nix"
fi
STUB
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

@test "native flock に対応しない Perl は導入を始める前に停止する" {
  stub_cmd perl 1

  run_install

  assert_failure
  assert_output --partial 'Perl with native flock support is required'
  refute_log_contains 'chezmoi'
  refute_log_contains 'curl'
  refute_log_contains 'nix '
  refute_log_contains 'direnv'
}

@test "SHA-256 コマンドがない場合は導入を始める前に停止する" {
  mv "$TEST_BIN_DIR/$HASH_COMMAND" "$BATS_TEST_TMPDIR/held-hash-command"

  run_install

  assert_failure
  assert_output --partial 'sha256sum or shasum is required'
  refute_log_contains 'chezmoi'
  refute_log_contains 'curl'
  refute_log_contains 'nix '
  refute_log_contains 'direnv'
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

@test "Linux (uname 既定値) では linux プランナー + --init none を使う（回帰なし）" {
  unstub_cmd nix
  # setup() の既定 (stub_cmd_with_output uname Linux) をそのまま使う

  run_install

  assert_log_contains "install linux"
  refute_log_contains "install macos"
  assert_log_contains "--init none"
  assert_log_contains "cache.numtide.com"
}

@test "NIX_CONFIG env で flakes をスクリプトスコープに付与" {
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

@test "初回導入は実際の lib でキャッシュを生成して成功する" {
  run_install

  assert_success
  assert_output --partial "Dotfiles installed successfully!"
  run /bin/bash -c '. "$1"; printf "%s\n" "$CACHE_VERSION"' _ "$BATS_TEST_TMPDIR/home/.cache/nix-devshell-global-env.bash"
  assert_success
  assert_output fresh
}

@test "初回導入は生成失敗時に旧キャッシュを保持し後続処理と成功表示を止める" {
  local cache="$BATS_TEST_TMPDIR/home/.cache/nix-devshell-global-env.bash"
  mkdir -p "$(dirname "$cache")"
  echo 'export CACHE_VERSION=old' >"$cache"
  touch -t 202001010000 "$cache"
  cat >>"$TEST_BIN_DIR/nix" <<'STUB'
if [ "$1" = print-dev-env ]; then
  echo 'evaluation failed' >&2
  exit 23
fi
STUB

  run_install

  assert_failure
  [ "$(cat "$cache")" = 'export CACHE_VERSION=old' ]
  refute_log_contains 'direnv allow'
  refute_output --partial 'Dotfiles installed successfully!'
}

@test "初回導入は必須更新の lib が無ければ成功扱いにしない" {
  mv "$BATS_TEST_TMPDIR/home/.config/nix-devshell/lib/refresh-cache.sh" "$BATS_TEST_TMPDIR/unused-lib"

  run_install

  assert_failure
  refute_log_contains 'direnv allow'
  refute_output --partial 'Dotfiles installed successfully!'
}

@test "初回導入はユーザー環境の flake が配備されていなければ成功扱いにしない" {
  mv "$BATS_TEST_TMPDIR/home/.config/nix-devshell/flake.nix" "$BATS_TEST_TMPDIR/unused-flake"

  run_install

  assert_failure
  refute_output --partial 'Dotfiles installed successfully!'
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

@test "初回導入の必須更新は非 Nix 入力変更を反映し同じ入力を再評価しない" {
  run_install
  assert_success
  : >"$TEST_LOG"
  run_install
  assert_success
  refute_log_contains 'nix print-dev-env'

  printf 'package input\n' >"$BATS_TEST_TMPDIR/home/.config/nix-devshell/asset.json"
  : >"$TEST_LOG"
  run_install
  assert_success
  assert_log_contains 'nix print-dev-env'
  assert_log_contains 'direnv allow'
}

@test "macOS の初回導入は shasum だけの初期 PATH でも生成できる" {
  stub_cmd_with_output uname Darwin
  if [ "$HASH_COMMAND" = sha256sum ]; then
    mv "$TEST_BIN_DIR/sha256sum" "$BATS_TEST_TMPDIR/held-sha256sum"
  fi
  stub_real_cmd shasum
  run_install
  assert_success
  assert_log_contains 'shasum -a 256'
  assert_log_contains 'nix print-dev-env'
}

@test "必須更新の競合後に待機中の入力変更を反映して成功する" {
  check_deployment_cache_concurrency run_install "$BATS_TEST_TMPDIR/home" stable
}

@test "必須更新の競合後に入力が繰り返し変われば失敗して後続処理を止める" {
  check_deployment_cache_concurrency run_install "$BATS_TEST_TMPDIR/home" changing
  refute_log_contains 'direnv allow'
  refute_output --partial 'Dotfiles installed successfully!'
}

@test "必須更新の競合後に待機後の生成失敗で後続処理を止める" {
  check_deployment_cache_concurrency run_install "$BATS_TEST_TMPDIR/home" failure
  refute_log_contains 'direnv allow'
  refute_output --partial 'Dotfiles installed successfully!'
}

@test "初回導入は system perl 不在を配備前に検出する" {
  mv "$TEST_BIN_DIR/perl" "$BATS_TEST_TMPDIR/held-perl"
  run_install
  assert_failure
  assert_output --partial 'Error: perl is required but not installed.'
  refute_log_contains 'chezmoi init'
  refute_log_contains 'nix develop'
}
