#!/usr/bin/env bats

load 'test_helper'

# SUT path (Task 2 で実装される)
readonly SUT="$BATS_TEST_DIRNAME/../run_once_before_setup-nix-system-conf.sh"

setup() {
  setup_test_env

  # FAKE FS (実 /etc/nix を触らないように)
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  export FAKE_ETC="$BATS_TEST_TMPDIR/etc/nix"
  mkdir -p "$FAKE_HOME/.config/nix" "$FAKE_ETC"

  # 実コマンドを TEST_BIN_DIR にラップ (log + 実行)
  stub_real_cmd grep
  stub_real_cmd cat
  stub_real_cmd rm
  stub_real_cmd mkdir
  stub_real_cmd touch
  stub_real_cmd tee
  stub_real_cmd whoami
  stub_real_cmd command
  stub_real_cmd mktemp

  # sudo: child process を log + 実行 (FAKE FS 上で動く)
  cat >"$TEST_BIN_DIR/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$TEST_LOG"
# tee の場合 stdin もログに保存
if [ "${1:-}" = "tee" ]; then
  shift
  # 引数 (-a path or path) は実コマンドに渡しつつ stdin も TEST_LOG にコピー
  TMP="$TEST_LOG.sudo-tee.$$"
  /bin/cat >"$TMP"
  echo '---sudo-tee-stdin-begin---' >> "$TEST_LOG"
  /bin/cat "$TMP" >> "$TEST_LOG"
  echo '---sudo-tee-stdin-end---' >> "$TEST_LOG"
  /usr/bin/tee "$@" <"$TMP"
  /bin/rm -f "$TMP"
else
  # touch / systemctl restart 等は no-op (実環境を触らない)
  exit 0
fi
STUB
  chmod +x "$TEST_BIN_DIR/sudo"
}

run_sut() {
  # PATH は $TEST_BIN_DIR のみ。sudo / tee / grep etc は stub。
  # NIX_CONF_PATH / NIX_CUSTOM_CONF_PATH を FAKE_ETC に向ける。
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    NIX_CONF_PATH="$FAKE_ETC/nix.conf" \
    NIX_CUSTOM_CONF_PATH="$FAKE_ETC/nix.custom.conf" \
    SYSTEMD_RUNTIME_DIR="${SYSTEMD_RUNTIME_DIR:-}" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash "$SUT"
}

@test "Nix 未インストール (NIX_CONF_PATH 不在) なら exit 0、sudo は呼ばれない" {
  # FAKE_ETC/nix.conf を作らない
  run_sut
  assert_success
  refute_log_contains "sudo"
}

@test "CUSTOM_CONF 不在なら sudo touch で作成される" {
  : >"$FAKE_ETC/nix.conf"
  run_sut
  assert_success
  assert_log_contains "sudo touch"
}

@test "nix.conf に !include 行が無ければ追加される" {
  : >"$FAKE_ETC/nix.conf" # 空ファイル (include 無し)
  run_sut
  assert_success
  grep -q '^!include nix\.custom\.conf$' "$FAKE_ETC/nix.conf"
}

@test "nix.conf に !include 行が既存なら追加されない (no-op)" {
  echo '!include nix.custom.conf' >"$FAKE_ETC/nix.conf"
  run_sut
  assert_success
  # 1 行だけ (重複追加されていない)
  count=$(grep -c '^!include nix\.custom\.conf$' "$FAKE_ETC/nix.conf")
  [ "$count" = "1" ]
}

@test "正常系: nix.custom.conf に期待設定が rewrite される" {
  : >"$FAKE_ETC/nix.conf"
  run_sut
  assert_success
  # tee 経由で書かれた stdin を確認
  assert_log_contains "trusted-users = root"
  assert_log_contains "extra-substituters = https://nix-community.cachix.org"
  assert_log_contains "extra-trusted-public-keys = nix-community.cachix.org-1:"
  assert_log_contains "extra-substituters = https://cache.numtide.com"
  assert_log_contains "download-buffer-size = 134217728"
  assert_log_contains "extra-experimental-features = nix-command flakes"
  # 実 file にも書かれている
  grep -q 'trusted-users = root' "$FAKE_ETC/nix.custom.conf"
  grep -q 'download-buffer-size = 134217728' "$FAKE_ETC/nix.custom.conf"
  grep -q 'extra-experimental-features = nix-command flakes' "$FAKE_ETC/nix.custom.conf"
}

@test "rewrite は idempotent (2 回実行しても結果同一)" {
  : >"$FAKE_ETC/nix.conf"
  run_sut
  assert_success
  HASH1=$(md5sum "$FAKE_ETC/nix.custom.conf" | awk '{print $1}')
  run_sut
  assert_success
  HASH2=$(md5sum "$FAKE_ETC/nix.custom.conf" | awk '{print $1}')
  [ "$HASH1" = "$HASH2" ]
}

@test "systemctl 利用可能 + nix-daemon active なら sudo systemctl restart が呼ばれる" {
  : >"$FAKE_ETC/nix.conf"
  export SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/run/systemd/system"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"
  # systemctl: command -v は成功、is-active は成功 (active)
  cat >"$TEST_BIN_DIR/systemctl" <<'STUB'
#!/bin/bash
echo "systemctl $*" >> "$TEST_LOG"
case "$1" in
  is-active) exit 0 ;;  # active
  *) exit 0 ;;
esac
STUB
  chmod +x "$TEST_BIN_DIR/systemctl"

  run_sut
  assert_success
  assert_log_contains "sudo systemctl restart nix-daemon"
}

@test "systemctl 不在なら restart は呼ばれず exit 0" {
  : >"$FAKE_ETC/nix.conf"
  # systemctl を stub しない (PATH に存在しない)
  run_sut
  assert_success
  refute_log_contains "systemctl"
}

@test "systemd 不在経路の nix-daemon spawn は出力を端末から切り離す (接続ログ漏れ防止)" {
  # regression: リダイレクト無しだと nix-daemon の
  # "accepted connection from pid ..., user ... (trusted)" が対話端末に漏れ続ける。
  # spawn 行が stdout/stderr をファイル/null へリダイレクトしていることを保証する。
  grep -Eq 'sudo "\$nix_daemon_bin".*>.*2>&1[[:space:]]*&' "$SUT"
}

@test "旧 user-level ~/.config/nix/nix.conf 残骸が削除される" {
  : >"$FAKE_ETC/nix.conf"
  echo "extra-substituters = https://stale.example" >"$FAKE_HOME/.config/nix/nix.conf"
  [ -f "$FAKE_HOME/.config/nix/nix.conf" ]

  run_sut
  assert_success
  [ ! -f "$FAKE_HOME/.config/nix/nix.conf" ]
}
