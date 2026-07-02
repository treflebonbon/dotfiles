#!/usr/bin/env bats

load 'test_helper'

readonly SUT="$BATS_TEST_DIRNAME/../run_after_00-refresh-nix-devshell-cache.sh"

setup() {
  setup_test_env

  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/lib" "$FAKE_HOME/.cache"
  : >"$FAKE_HOME/.config/nix-devshell/flake.nix"
  : >"$FAKE_HOME/.config/nix-devshell/flake.lock"

  cp "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/refresh-cache.sh" \
    "$FAKE_HOME/.config/nix-devshell/lib/refresh-cache.sh"

  stub_real_cmd find
  stub_real_cmd grep
  stub_real_cmd mkdir
  stub_real_cmd mv
  stub_real_cmd rm
  stub_real_cmd touch
  stub_real_cmd cat
  stub_real_cmd dirname
  stub_real_cmd mktemp
  stub_real_cmd date
}

run_sut() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash "$SUT"
}

@test "lib が無ければ何もせず exit 0" {
  rm -f "$FAKE_HOME/.config/nix-devshell/lib/refresh-cache.sh"
  stub_cmd nix

  run_sut

  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "nix が PATH に無ければ lib 経由で何もせず exit 0" {
  run_sut
  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "~/.config/nix-devshell が無ければ lib 経由で何もせず exit 0" {
  rm -rf "$FAKE_HOME/.config/nix-devshell"
  stub_cmd nix

  run_sut

  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "lib を source して refresh_nix_devshell_cache を呼ぶ" {
  cat >"$FAKE_HOME/.config/nix-devshell/lib/refresh-cache.sh" <<'STUB'
#!/usr/bin/env bash
refresh_nix_devshell_cache() {
  echo "REFRESH_CALLED" >> "$TEST_LOG"
}
STUB
  stub_cmd nix

  run_sut

  assert_success
  assert_log_contains "REFRESH_CALLED"
}

@test "lib 経由で nix print-dev-env が呼ばれ cache が更新される" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
echo 'export PATH=/nix/store/fresh/bin:$PATH'
STUB
  chmod +x "$TEST_BIN_DIR/nix"

  run_sut

  assert_success
  assert_log_contains "nix print-dev-env"
  grep -q '/nix/store/fresh/bin' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
}
