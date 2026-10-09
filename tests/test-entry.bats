#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  BUN_BIN="$(command -v bun)"
  export RUN_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$RUN_ROOT/scripts"
  cp "$BATS_TEST_DIRNAME/../package.json" "$RUN_ROOT/"
  if [ -f "$BATS_TEST_DIRNAME/../scripts/test.sh" ]; then
    cp "$BATS_TEST_DIRNAME/../scripts/test.sh" "$RUN_ROOT/scripts/"
  fi
  ln -s "$(command -v python3)" "$TEST_BIN_DIR/python3"
  ln -s "$(command -v with-env)" "$TEST_BIN_DIR/with-env"
  stub_cmd bun
  cat >"$TEST_BIN_DIR/bats" <<'STUB_EOF'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
printf '%s\n' "${BATS_STUB_TAP-$'1..1\nok 1 fixture'}"
exit "${BATS_STUB_STATUS:-0}"
STUB_EOF
  chmod +x "$TEST_BIN_DIR/bats"
  cd "$RUN_ROOT"
}

run_entry() {
  run /usr/bin/env PATH="$TEST_BIN_DIR:$PATH" "$BUN_BIN" run test
}

@test "テスト入口は隔離 Python の dotenv 不足を install より前に拒否する" {
  # symlink 先の Python を変更せず、fixture の PATH だけ差し替える。
  mv "$TEST_BIN_DIR/python3" "$TEST_BIN_DIR/python3-real"
  stub_cmd python3 1
  run_entry
  assert_failure
  assert_output --partial "テスト環境が不完全"
  assert_log_contains "python3 -I -"
  refute_log_contains "bun install"
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 1 ]
  [ -s "${logs[0]%/tap.log}/setup.log" ]
}

@test "テスト入口は Nix store 外の with-env を install より前に拒否する" {
  mv "$TEST_BIN_DIR/with-env" "$TEST_BIN_DIR/with-env-real"
  stub_cmd with-env
  run_entry
  assert_failure
  assert_output --partial "with-env"
  refute_log_contains "bun install"
  refute_log_contains "/bats "
}

@test "テスト入口は TAP ログと終了コードを保存する" {
  run_entry
  assert_success
  assert_log_contains "bun install --frozen-lockfile"
  assert_log_contains "bats --tap --print-output-on-failure tests/"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "${#logs[@]}" -eq 1 ]
  [ "$(cat "${logs[0]}")" = $'1..1\nok 1 fixture' ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 0 ]
}

@test "テスト入口は Bats の失敗をログ保存で成功に変えない" {
  export BATS_STUB_STATUS=9
  run_entry
  assert_failure 9
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 9 ]
}

@test "テスト入口は Bats が正常終了しても未完了の TAP を拒否する" {
  export BATS_STUB_TAP=$'1..2\nok 1 fixture'
  run_entry
  assert_failure 1
  assert_output --partial "TAP が未完了または不正"
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]}")" = "$BATS_STUB_TAP" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 1 ]
}

@test "テスト入口は計画と結果番号が不整合な TAP を拒否する" {
  local tap
  for tap in \
    '' \
    $'ok 1 fixture' \
    $'1..1\n1..1\nok 1 fixture' \
    $'1..1\nok 1 fixture\nok 2 extra' \
    $'1..2\nok 1 fixture\nok 1 duplicate' \
    $'1..2\nok 1 fixture\nok 3 gap' \
    $'1..2\nok 2 reordered\nok 1 fixture'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_failure 1
    assert_output --partial "TAP が未完了または不正"
  done
}

@test "テスト入口は正常終了でも TAP の失敗と中断宣言を拒否する" {
  local tap
  for tap in $'1..1\nnot ok 1 failed' $'1..1\nok 1 fixture\nBail out! interrupted'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_failure 1
    assert_output --partial "TAP が未完了または不正"
  done
}

@test "テスト入口はスキップと診断を含む完了 TAP と対象ゼロ件を受け入れる" {
  local tap
  for tap in $'1..2\nok 1 fixture\n# ok 999 diagnostic\nok 2 optional # skip 未設定' '1..0'; do
    export BATS_STUB_TAP="$tap"
    run_entry
    assert_success
  done
}

@test "テスト入口は frozen install の失敗後に Bats を実行しない" {
  stub_cmd bun 7
  run_entry
  assert_failure 7
  refute_log_contains "/bats "
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ -f "${logs[0]}" ]
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 7 ]
  [ -s "${logs[0]%/tap.log}/environment" ]
}

@test "テスト入口は停止シグナルを成功として記録しない" {
  cat >"$TEST_BIN_DIR/bats" <<'STUB_EOF'
#!/bin/bash
printf '1..1\n'
kill -TERM "$PPID"
STUB_EOF
  run_entry
  assert_failure 143
  local logs=("$RUN_ROOT"/tmp/test-run.*/tap.log)
  [ "$(cat "${logs[0]%/tap.log}/exit-code")" = 143 ]
}
