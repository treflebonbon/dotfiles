#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

@test "D1 の限定参照は確認前に定義を読まず、help はローカルで表示する" {
  local script="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/cloudflare-cli/cloudflare-inspect.py"
  run env -u CLOUDFLARE_API_TOKEN -u CLOUDFLARE_ACCOUNT_ID python3 -I "$script" d1 read --definition /nonexistent/DUMMY_PRIVATE
  [ "$status" -eq 2 ]
  [[ "$output" == *操作ごとの確認* ]]
  [[ "$output" != *DUMMY_PRIVATE* ]]
  run env -u CLOUDFLARE_API_TOKEN -u CLOUDFLARE_ACCOUNT_ID python3 -I "$script" --reviewed d1 read --help
  [ "$status" -eq 0 ]
  [[ "$output" == *--definition* ]]
  [[ "$output" == *--sha256* ]]
}

@test "D1 の固定読取り定義から許可列を1回だけ取得して private 記録を残す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_select
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の期限通知が遅れても開始済みの HTTP を0試行と報告しない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_delayed_deadline_notice
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の bind は SQL にならず、存在しない列を文字列として成功させない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_sql_boundaries
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 は private ファイル・保存先・JSON の境界を送信前に検査する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_private_boundaries
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の transport は proxy と CA を扱い endpoint・debug の上書きを使わない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_transport_environment
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の EXPLAIN は専用 schema と件数制限で検証し計画を公開しない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_explain
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の上限到達を完了と推定せず token の反映を保存しない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_limit_and_redaction
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の不正な定義・hash・bind・列・件数を送信前に拒否する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_invalid_definition
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の送信前後の保存失敗を成功や架空の試行数にしない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_storage_failure
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の未知 schema・非0の rows_written・不正な統計を成功にしない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_invalid_response
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の実 transport は redirect を追わず失敗する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_redirect
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の proxy 認証 challenge を再送せず private な失敗を返す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_proxy_challenge
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の全体期限で通信中の処理を止め開始済みの不確実性を残す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_deadline
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 は親の通知処理が遅れても期限を過ぎた HTTP を開始しない" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_expired_before_request
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "D1 の HTTP エラーを再試行せず匿名の失敗と private 記録を返す" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-d1.py" "$BATS_TEST_TMPDIR" D1.test_http_failure
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
