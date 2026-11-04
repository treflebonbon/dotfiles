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
  [ "$output" = 1.0.0-beta.24 ]
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
