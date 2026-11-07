#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

@test "R2 の限定参照は確認前に定義を読まず、help はローカルで表示する" {
  local script="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/cloudflare-cli/cloudflare-inspect.py"
  run env -u CLOUDFLARE_R2_ACCESS_KEY_ID -u CLOUDFLARE_R2_SECRET_ACCESS_KEY -u CLOUDFLARE_R2_SESSION_TOKEN \
    python3 -I "$script" r2 objects list --definition /nonexistent/DUMMY_PRIVATE --sha256 dummy
  [ "$status" -eq 2 ]
  [[ "$output" == *操作ごとの確認* ]]
  [[ "$output" != *DUMMY_PRIVATE* ]]

  run env -u CLOUDFLARE_R2_ACCESS_KEY_ID -u CLOUDFLARE_R2_SECRET_ACCESS_KEY -u CLOUDFLARE_R2_SESSION_TOKEN \
    python3 -I "$script" --reviewed r2 objects list --help
  [ "$status" -eq 0 ]
  [[ "$output" == *--definition* ]]
  [[ "$output" == *--sha256* ]]
  [[ "$output" == *--limit* ]]
}

@test "R2 は固定 query の先頭 page だけを呼び、許可項目を private に保存する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_fixed_request_and_projection
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_child_environment_keeps_only_r2_credentials_proxy_ca_and_locale
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "R2 の固定定義と一時資格情報 scope を送信前に照合する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_official_empty_or_omitted_object_paths_and_rejects_credential_mismatch_before_http
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_credential_values_are_not_recorded_before_scope_validation
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_definition_hash_shape_and_bounds_fail_before_http
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_private_definition_file_boundaries
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "R2 は complete/truncated page と厳格な XML のみを受理する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_empty_and_truncated_pages_do_not_store_continuation_tokens
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_invalid_xml_transport_encoding_and_metadata_never_store_items
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_unknown_xml_encoding_preserves_attempt_and_classifies_http_error
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "R2 の transport は redirect/retry をせず、中断時の pending とエラー分類を記録する" {
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_real_transport_stub_never_redirects_retries_or_leaks_error_bodies
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  run python3 -I "$BATS_TEST_DIRNAME/helpers/cloudflare-r2.py" "$BATS_TEST_TMPDIR" R2.test_deadline_kills_local_stub_and_leaves_pending_attempt_record
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
