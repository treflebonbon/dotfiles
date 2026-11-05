#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  cd "$BATS_TEST_TMPDIR/project"
}

@test "固定版 cf は project 内の別版へ実行を委譲しない" {
  mkdir -p node_modules/cf/bin
  printf '%s\n' '{"name":"cf","version":"0.0.0","bin":{"cf":"bin/cf"}}' >node_modules/cf/package.json
  printf '%s\n' '#!/usr/bin/env node' 'console.log("UNTRUSTED_LOCAL_CF")' >node_modules/cf/bin/cf
  run --separate-stderr cf --version
  [ "$status" -eq 0 ]
  [ "$output" = 1.0.0-beta.25 ]
}

@test "Nix の検査 helper は認証情報なしで同梱 CLI の版を返す" {
  run --separate-stderr env -u CLOUDFLARE_API_TOKEN -u CLOUDFLARE_ACCOUNT_ID cloudflare-inspect --version
  [ "$status" -eq 0 ]
  [ "$output" = 1.0.0-beta.25 ]
}

@test "固定版 cf の schema は確認済み参照操作を GET として定義する" {
  local entry command path
  for entry in \
    'd1 list|/accounts/{account_id}/d1/database' \
    'durable-objects namespaces list|/accounts/{account_id}/workers/durable_objects/namespaces' \
    'r2 buckets list|/accounts/{account_id}/r2/buckets' \
    'workers scripts search|/accounts/{account_id}/workers/scripts-search' \
    'd1 get|/accounts/{account_id}/d1/database/{database_id}'; do
    command=${entry%%|*}
    path=${entry#*|}
    read -r -a arguments <<<"$command"
    run --separate-stderr cf schema "${arguments[@]}"
    [ "$status" -eq 0 ]
    run jq -e --arg path "$path" '.httpMethod == "GET" and .hasRequestBody == false and .path == $path' <<<"$output"
    [ "$status" -eq 0 ]
  done
}

@test "固定版 cf の過去ログ検索は固定した POST endpoint と JSON body を使う" {
  run --separate-stderr cf schema o11y telemetry query
  [ "$status" -eq 0 ]
  run jq -e '.httpMethod == "POST" and .hasRequestBody == true and .path == "/accounts/{account_id}/workers/observability/telemetry/query"' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "Nix の検査 helper は PATH 上の偽 cf ではなく同梱 CLI を使う" {
  mkdir -p untrusted
  cat >untrusted/cf <<'SH'
#!/bin/sh
printf '%s\n' 'UNTRUSTED_CF_MUST_NOT_RUN'
exit 1
SH
  chmod +x untrusted/cf
  run --separate-stderr env PATH="$PWD/untrusted:$PATH" cloudflare-inspect cli search 'd1 databases'
  [ "$status" -eq 0 ]
  [[ "$output" != *UNTRUSTED_CF_MUST_NOT_RUN* ]]
  run jq -e 'type == "array" and length > 0' <<<"$output"
  [ "$status" -eq 0 ]
}
