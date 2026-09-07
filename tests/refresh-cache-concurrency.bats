#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  LIB="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/refresh-cache.sh"
  export FAKE_HOME="$BATS_TEST_TMPDIR/home" SYNC_DIR="$BATS_TEST_TMPDIR/sync"
  mkdir -p "$FAKE_HOME/.config/nix-devshell" "$FAKE_HOME/.cache" "$SYNC_DIR"
  printf '{}\n' >"$FAKE_HOME/.config/nix-devshell/flake.nix"
  printf 'fresh\n' >"$FAKE_HOME/.config/nix-devshell/payload"
  CACHE="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf 'export CACHE_VERSION=old\n' >"$CACHE"
  PIDS=()
  local cmd
  for cmd in find grep mkdir mv rm tee cat dirname mktemp date tail readlink perl; do
    stub_real_cmd "$cmd"
  done
  stub_hash_cmd
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
role=$UPDATE_ROLE
attempt=1
while [ -f "$SYNC_DIR/$role.entered.$attempt" ]; do ((attempt++)); done
value=$(cat payload)
printf '%s\n' "$role:$attempt:$value" >>"$SYNC_DIR/evaluations"
: >"$SYNC_DIR/$role.entered.$attempt"
for ((i=0; i<500; i++)); do
  if [ -f "$SYNC_DIR/$role.release.$attempt" ]; then
    printf 'export CACHE_VERSION=%s\n' "$value"
    : >"$SYNC_DIR/$role.finished.$attempt"
    exit 0
  fi
  /bin/sleep 0.02
done
exit 99
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  cat >"$TEST_BIN_DIR/perl" <<'STUB'
#!/bin/bash
: >"$SYNC_DIR/$UPDATE_ROLE.lock-request"
exec /usr/bin/perl "$@"
STUB
  chmod +x "$TEST_BIN_DIR/perl"
}

teardown() {
  # テスト所有の更新だけを終える。adapter の待機も解除する。
  local role attempt pid
  touch "$SYNC_DIR/first.return" "$SYNC_DIR/first.check-release"
  for role in first second third; do
    for attempt in 1 2 3; do touch "$SYNC_DIR/$role.release.$attempt"; done
  done
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}

wait_for_file() {
  local attempt
  for ((attempt = 0; attempt < 250; attempt++)); do
    [ ! -f "$1" ] || return 0
    sleep 0.02
  done
  printf 'Timed out waiting for %s\n' "$1" >&2
  return 1
}

start_refresh() {
  local role="$1" required="$2"
  /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$FAKE_HOME" TEST_LOG="$TEST_LOG" \
    SYNC_DIR="$SYNC_DIR" UPDATE_ROLE="$role" NIX_DEVSHELL_CACHE_REQUIRED="$required" \
    /bin/bash -c '
      . "$1"
      : >"$SYNC_DIR/$UPDATE_ROLE.started"
      if refresh_nix_devshell_cache; then result=0; else result=$?; fi
      printf "%s\n" "$result" >"$SYNC_DIR/$UPDATE_ROLE.status"
      exit "$result"
    ' _ "$LIB" >"$SYNC_DIR/$role.output" 2>&1 3>&- &
  PIDS+=("$!")
  wait_for_file "$SYNC_DIR/$role.started"
}

@test "背景更新は競合時に評価も待機も追加せず旧キャッシュを読める" {
  start_refresh first 0
  wait_for_file "$SYNC_DIR/first.entered.1"
  start_refresh second 0
  wait_for_file "$SYNC_DIR/second.status"
  [ "$(cat "$SYNC_DIR/second.status")" = 0 ]
  [ ! -e "$SYNC_DIR/second.entered.1" ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output old

  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.status"
  [ "$(cat "$SYNC_DIR/first.status")" = 0 ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output fresh
}

@test "評価中の入力変更は古い結果を採用せず最新入力で一度だけ再試行する" {
  start_refresh first 1
  wait_for_file "$SYNC_DIR/first.entered.1"
  printf 'latest\n' >"$FAKE_HOME/.config/nix-devshell/payload"
  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.entered.2"
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output old

  touch "$SYNC_DIR/first.release.2"
  wait_for_file "$SYNC_DIR/first.status"
  [ "$(cat "$SYNC_DIR/first.status")" = 0 ]
  [ ! -e "$SYNC_DIR/first.entered.3" ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output latest
  [ "$(cat "$SYNC_DIR/evaluations")" = $'first:1:fresh\nfirst:2:latest' ]
}

@test "必須更新は先行更新を待ち同じ入力の結果を再利用する" {
  start_refresh first 0
  wait_for_file "$SYNC_DIR/first.entered.1"
  start_refresh second 1
  wait_for_file "$SYNC_DIR/second.lock-request"
  [ ! -e "$SYNC_DIR/second.status" ]
  [ ! -e "$SYNC_DIR/second.entered.1" ]

  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.status"
  wait_for_file "$SYNC_DIR/second.status"
  [ "$(cat "$SYNC_DIR/second.status")" = 0 ]
  [ "$(cat "$SYNC_DIR/evaluations")" = 'first:1:fresh' ]
}

@test "再試行中にも入力が変われば旧キャッシュを保持し二回で停止する" {
  local required
  cp "$CACHE" "$SYNC_DIR/old-cache"
  for required in 0 1; do
    local role=first
    [ "$required" = 0 ] || role=second
    start_refresh "$role" "$required"
    wait_for_file "$SYNC_DIR/$role.entered.1"
    printf 'changed-%s-1\n' "$role" >"$FAKE_HOME/.config/nix-devshell/payload"
    touch "$SYNC_DIR/$role.release.1"
    wait_for_file "$SYNC_DIR/$role.entered.2"
    printf 'changed-%s-2\n' "$role" >"$FAKE_HOME/.config/nix-devshell/payload"
    touch "$SYNC_DIR/$role.release.2"
    wait_for_file "$SYNC_DIR/$role.status"
    [ "$(cat "$SYNC_DIR/$role.status")" = "$required" ]
    [ ! -e "$SYNC_DIR/$role.entered.3" ]
    cmp "$CACHE" "$SYNC_DIR/old-cache"
  done

  touch "$SYNC_DIR/third.release.1"
  start_refresh third 1
  wait_for_file "$SYNC_DIR/third.status"
  [ "$(cat "$SYNC_DIR/third.status")" = 0 ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output changed-second-2
}

@test "評価中の更新 process 終了は旧キャッシュを保持し次回更新を妨げない" {
  start_refresh first 1
  wait_for_file "$SYNC_DIR/first.entered.1"
  kill -KILL "${PIDS[0]}"
  wait "${PIDS[0]}" 2>/dev/null || true
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output old

  printf 'after-kill\n' >"$FAKE_HOME/.config/nix-devshell/payload"
  touch "$SYNC_DIR/second.release.1"
  start_refresh second 1
  wait_for_file "$SYNC_DIR/second.status"
  [ "$(cat "$SYNC_DIR/second.status")" = 0 ]
  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.finished.1"
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output after-kill
  run find "$FAKE_HOME/.cache" -type f \( -name '*.tmp.*' -o -name '*.err.*' \)
  assert_output ''
}

@test "必須更新はロック待機後に入力を再確認して必要な評価を行う" {
  cat >"$TEST_BIN_DIR/mv" <<'STUB'
#!/bin/bash
/bin/mv "$@" || exit
if [ "$UPDATE_ROLE" = first ]; then
  : >"$SYNC_DIR/first.adopted"
  for ((i=0; i<500; i++)); do
    [ ! -f "$SYNC_DIR/first.return" ] || exit 0
    /bin/sleep 0.02
  done
  exit 99
fi
STUB
  start_refresh first 1
  wait_for_file "$SYNC_DIR/first.entered.1"
  start_refresh second 1
  wait_for_file "$SYNC_DIR/second.lock-request"
  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.adopted"
  printf 'changed-while-waiting\n' >"$FAKE_HOME/.config/nix-devshell/payload"
  touch "$SYNC_DIR/first.return"

  wait_for_file "$SYNC_DIR/second.entered.1"
  [ "$(cat "$SYNC_DIR/evaluations")" = $'first:1:fresh\nsecond:1:changed-while-waiting' ]
  touch "$SYNC_DIR/second.release.1"
  wait_for_file "$SYNC_DIR/second.status"
  [ "$(cat "$SYNC_DIR/second.status")" = 0 ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output changed-while-waiting
}

check_pre_adoption_termination() {
  mv "$TEST_BIN_DIR/$HASH_COMMAND" "$FAKE_HOME/$HASH_COMMAND"
  cat >"$TEST_BIN_DIR/$HASH_COMMAND" <<'STUB'
#!/bin/bash
if [ "$UPDATE_ROLE" = first ] && [ -f "$SYNC_DIR/first.finished.1" ]; then
  : >"$SYNC_DIR/first.checking"
  for ((i=0; i<500; i++)); do
    [ ! -f "$SYNC_DIR/first.check-release" ] || break
    /bin/sleep 0.02
  done
fi
STUB
  printf 'exec "%s" "$@"\n' "$FAKE_HOME/$HASH_COMMAND" >>"$TEST_BIN_DIR/$HASH_COMMAND"
  chmod +x "$TEST_BIN_DIR/$HASH_COMMAND"
  start_refresh first 1
  wait_for_file "$SYNC_DIR/first.entered.1"
  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.checking"
  kill -TERM "${PIDS[0]}"
  wait "${PIDS[0]}" 2>/dev/null || true
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output old

  touch "$SYNC_DIR/second.release.1"
  start_refresh second 1
  wait_for_file "$SYNC_DIR/second.status"
  [ "$(cat "$SYNC_DIR/second.status")" = 0 ]
  touch "$SYNC_DIR/first.check-release"
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output fresh
}

@test "採用前の指紋確認中に更新 process が終了しても候補を採用しない" {
  check_pre_adoption_termination
}

@test "shasum のみの環境でも採用前の終了と次回更新を検証できる" {
  if [ "$HASH_COMMAND" = sha256sum ]; then
    mv "$TEST_BIN_DIR/sha256sum" "$FAKE_HOME/held-sha256sum"
  fi
  HASH_COMMAND=shasum
  stub_real_cmd shasum
  check_pre_adoption_termination
  assert_log_contains 'shasum -a 256'
  refute_log_contains 'sha256sum'
}

@test "失敗した評価の間に入力が変わった場合も最新入力で再試行する" {
  # 同期点・出力はそのままに、最初の評価だけ非0終了にする。
  sed -i 's/exit 0/[ "$attempt" != 1 ] || exit 23; exit 0/' "$TEST_BIN_DIR/nix"
  start_refresh first 1
  wait_for_file "$SYNC_DIR/first.entered.1"
  printf 'recovered\n' >"$FAKE_HOME/.config/nix-devshell/payload"
  touch "$SYNC_DIR/first.release.1"
  wait_for_file "$SYNC_DIR/first.entered.2"
  touch "$SYNC_DIR/first.release.2"
  wait_for_file "$SYNC_DIR/first.status"
  [ "$(cat "$SYNC_DIR/first.status")" = 0 ]
  run /bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$CACHE"
  assert_output recovered
}
