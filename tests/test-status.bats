#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$BATS_TEST_TMPDIR"
  mkdir -p tmp/test-run.old tmp/test-run.new
  printf '1..2\nok 1 a\nok 2 b\n' >tmp/test-run.old/tap.log
  printf '1..2\nok 1 a\n' >tmp/test-run.new/tap.log
}

@test "開始が新しい実行を選ぶ（古い実行が後から終わって更新時刻が新しくなっても）" {
  printf '100\n' >tmp/test-run.old/started
  printf '200\n' >tmp/test-run.new/started
  printf '0\n' >tmp/test-run.old/exit-code
  touch -d '+1 minute' tmp/test-run.old
  run -0 "$PROJECT_ROOT/scripts/test-status.sh"
  [ "${lines[0]}" = "tmp/test-run.new: 実行中" ]
  [ "${lines[1]}" = "成功 1 / 失敗 0 / スキップ 0 / 計画 2" ]
}

@test "started のない実行だけなら更新時刻で選ぶ" {
  printf '0\n' >tmp/test-run.old/exit-code
  touch -d '-1 minute' tmp/test-run.new
  run -0 "$PROJECT_ROOT/scripts/test-status.sh"
  [ "${lines[0]}" = "tmp/test-run.old: 完了 (exit 0)" ]
}
