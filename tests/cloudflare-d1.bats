#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

@test "D1 の固定読取り定義から許可列を1回だけ取得して private 記録を残す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_select
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の全体期限で通信中の処理を止め開始済みの不確実性を残す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_deadline
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の HTTP エラーを再試行せず匿名の失敗と private 記録を返す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_http_failure
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
