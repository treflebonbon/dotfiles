#!/usr/bin/env bats
# dot_bashrc.tmpl の _nix_devshell_global_reload が GNU/BSD 両方の stat で
# 正しく mtime を取得できるかを検証する（issue #42）。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../dot_bashrc.tmpl"

setup() {
  setup_test_env
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.cache"
  : >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
}

# BSD/macOS の stat（`-f FORMAT`）のみ受け付け、GNU の `-c` は拒否するスタブ
stub_bsd_stat() {
  cat >"$TEST_BIN_DIR/stat" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [ "$1" = "-c" ]; then
  echo "stat: illegal option -- c" >&2
  exit 1
fi
if [ "$1" = "-f" ]; then
  echo "1700000000"
  exit 0
fi
exit 1
STUB_EOF
  chmod +x "$TEST_BIN_DIR/stat"
}

run_reload() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash -c "
      ensure_nix_devshell_env() { echo \"ensure_nix_devshell_env \$*\" >> \"\$TEST_LOG\"; }
      _nix_devshell_prune_zed_env() { echo _nix_devshell_prune_zed_env >> \"\$TEST_LOG\"; }
      $(extract_function "$SRC" _nix_devshell_global_reload)
      _nix_devshell_global_reload
    "
}

@test "BSD stat (-f) でも global reload が発火する" {
  stub_bsd_stat
  run_reload
  assert_success
  assert_log_contains "ensure_nix_devshell_env"
}

@test "GNU stat (-c) では従来通り global reload が発火する（回帰なし）" {
  stub_real_cmd stat
  run_reload
  assert_success
  assert_log_contains "ensure_nix_devshell_env"
}
