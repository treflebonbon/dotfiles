#!/usr/bin/env bats
# local-skills/worktree-gc/scripts/worktree-gc.sh の is_older_than_days が
# GNU/BSD 両方の stat で正しく mtime を取得できるかを検証する（issue #42）。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../local-skills/worktree-gc/scripts/worktree-gc.sh"

setup() {
  setup_test_env
}

# BSD/macOS の stat（`-f FORMAT`）のみ受け付け、GNU の `-c` は拒否するスタブ。
# mtime は 2001-09-09 (epoch 1000000000) 固定 — どんな --age-days 閾値より
# 確実に「古い」ことを保証する。
stub_bsd_stat() {
  cat >"$TEST_BIN_DIR/stat" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [ "$1" = "-c" ]; then
  echo "stat: illegal option -- c" >&2
  exit 1
fi
if [ "$1" = "-f" ]; then
  echo "1000000000"
  exit 0
fi
exit 1
STUB_EOF
  chmod +x "$TEST_BIN_DIR/stat"
}

run_is_older_than_days() {
  local path="$1" days="$2"
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash -c "
      $(extract_function "$SRC" is_older_than_days)
      is_older_than_days '$path' '$days'
    "
}

@test "BSD stat (-f) でも古いパスを古いと判定する" {
  stub_bsd_stat
  run_is_older_than_days "/tmp/whatever" 7
  assert_success
}

@test "GNU stat (-c) では従来通り古いパスを古いと判定する（回帰なし）" {
  stub_real_cmd stat
  stub_real_cmd date
  local old_path="$BATS_TEST_TMPDIR/old-dir"
  mkdir -p "$old_path"
  touch -d '2001-09-09' "$old_path"
  run_is_older_than_days "$old_path" 7
  assert_success
}
