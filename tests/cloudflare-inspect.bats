#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/private_dot_local/bin/executable_cloudflare-inspect"
  export CF_TEST_LOG="$BATS_TEST_TMPDIR/calls.jsonl"
  export CF_TEST_RESPONSE="$BATS_TEST_TMPDIR/response.json"
  export CLOUDFLARE_API_TOKEN="DUMMY_CF_TOKEN"
  export CLOUDFLARE_ACCOUNT_ID="0123456789abcdef0123456789abcdef"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cat >"$BATS_TEST_TMPDIR/bin/cf" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
fixture = pathlib.Path(__file__).resolve().parent.parent
if sys.argv[1:] == ['--version']:
    assert 'CLOUDFLARE_API_TOKEN' not in os.environ
    print((fixture / 'version').read_text().strip() if (fixture / 'version').exists() else '1.0.0-beta.24')
    raise SystemExit(0)
assert os.environ['CF_SEND_TELEMETRY'] == 'false'
assert os.environ['CF_DELEGATION'] == '1'
assert os.environ['CLOUDFLARE_API_BASE_URL'] == 'https://api.cloudflare.com/client/v4'
if sys.argv[1:3] == ['cli', 'search']:
    assert 'CLOUDFLARE_API_TOKEN' not in os.environ
else:
    expected = (fixture / 'token').read_text() if (fixture / 'token').exists() else 'DUMMY_CF_TOKEN'
    assert os.environ['CLOUDFLARE_API_TOKEN'] == expected
    assert os.environ['CLOUDFLARE_ACCOUNT_ID'] == '0123456789abcdef0123456789abcdef'
assert 'NODE_OPTIONS' not in os.environ and 'DEBUG' not in os.environ
assert not pathlib.Path('cloudflare.config.ts').exists()
assert not any((parent / 'cloudflare.config.ts').exists() for parent in pathlib.Path.cwd().parents)
with (fixture / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\n')
if (fixture / 'fail').exists():
    print('DUMMY_CF_TOKEN DUMMY_SECRET', file=sys.stderr)
    raise SystemExit(1)
print((fixture / 'response.json').read_text())
PY
  chmod +x "$BATS_TEST_TMPDIR/bin/cf"
  printf '%s\n' '[{"name":"example","uuid":"db-id"}]' >"$CF_TEST_RESPONSE"
}

@test "Cloudflare の既知の機密項目と token の反映を表示しない" {
  printf '%s\n' '{"name":"example","vars":{"x":"DUMMY_SECRET"},"bindings":[{"text":"DUMMY_SECRET"}],"nested":{"environment_variables":{"x":"DUMMY_SECRET"},"client_secret":"DUMMY_SECRET"},"note":"DUMMY_CF_TOKEN"}' >"$CF_TEST_RESPONSE"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -eq 0 ]
  [[ "$output" != *DUMMY_SECRET* && "$output" != *DUMMY_CF_TOKEN* ]]
  [ "$(jq -r .name <<<"$output")" = example ]
}

@test "Cloudflare の token は JSON のエスケープ表記でも表示しない" {
  export CLOUDFLARE_API_TOKEN='DUMMY_"CF_TOKEN'
  printf '%s' "$CLOUDFLARE_API_TOKEN" >"$BATS_TEST_TMPDIR/token"
  printf '%s\n' '{"note":"DUMMY_\"CF_TOKEN"}' >"$CF_TEST_RESPONSE"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -eq 0 ]
  [ "$(jq -r .note <<<"$output")" = '[非表示]' ]
}

@test "Cloudflare の D1 一覧を指定 account の Read token で取得する" {
  run python3 -I "$SCRIPT" d1 list --per-page 20 --page 2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].name' <<<"$output")" = example ]
  run jq -se '.[0] == ["d1", "list", "--page=2", "--per-page=20"]' "$CF_TEST_LOG"
  [ "$status" -eq 0 ]
}

@test "Cloudflare の初期4操作は対象とページを検証して実行する" {
  local command
  for command in 'd1 list --name example' 'durable-objects namespaces list' 'r2 buckets list --direction asc' 'workers scripts search --name example'; do
    read -r -a arguments <<<"$command"
    run python3 -I "$SCRIPT" "${arguments[@]}"
    [ "$status" -eq 0 ]
  done
  [ "$(wc -l <"$CF_TEST_LOG")" -eq 4 ]
}

@test "Cloudflare の書込み・Logs・秘密値・未知の引数は CLI 実行前に拒否する" {
  local command reviewed
  for reviewed in '' '--reviewed'; do
    for command in 'd1 delete x' 'o11y telemetry query' 'deploy' 'auth login' 'workers scripts secrets get x' 'd1 list --force' 'd1 list --api-token DUMMY_CF_TOKEN' 'd1 list --page 0' 'r2 buckets list --per-page 101' 'r2 buckets list --direction drop' 'workers scripts search --config x' 'd1 query x'; do
      read -r -a arguments <<<"$command"
      run python3 -I "$SCRIPT" ${reviewed:+"$reviewed"} "${arguments[@]}"
      [ "$status" -ne 0 ]
      [[ "$output" != *DUMMY_CF_TOKEN* ]]
      [ ! -e "$CF_TEST_LOG" ]
    done
  done
}

@test "Cloudflare の確認済み追加参照は --reviewed でも Read 操作に限る" {
  local database=01234567-89ab-cdef-0123-456789abcdef
  run python3 -I "$SCRIPT" d1 get "$database"
  [ "$status" -ne 0 ]
  [ ! -e "$CF_TEST_LOG" ]
  run python3 -I "$SCRIPT" --reviewed d1 get "$database" --fields name
  [ "$status" -eq 0 ]
  run jq -se '.[0] == ["d1", "get", "01234567-89ab-cdef-0123-456789abcdef", "--fields=name"]' "$CF_TEST_LOG"
  [ "$status" -eq 0 ]
}

@test "Cloudflare の CLI 検索は固定語彙だけを認証情報なしで使う" {
  run python3 -I "$SCRIPT" cli search 'customer.example.com DUMMY_CF_TOKEN'
  [ "$status" -ne 0 ]
  [[ "$output" != *DUMMY_CF_TOKEN* ]]
  [ ! -e "$CF_TEST_LOG" ]
  run python3 -I "$SCRIPT" cli search 'd1 databases'
  [ "$status" -eq 0 ]
}

@test "Cloudflare のプロジェクト設定・endpoint・Node の注入を引き継がない" {
  printf '%s\n' 'throw new Error("must not execute")' >"$BATS_TEST_TMPDIR/cloudflare.config.ts"
  cd "$BATS_TEST_TMPDIR"
  export NODE_OPTIONS='--require=/must-not-load' DEBUG=1 CLOUDFLARE_API_BASE_URL=https://untrusted.invalid CF_DELEGATION=0 TMPDIR="$BATS_TEST_TMPDIR"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -eq 0 ]
}

@test "Cloudflare の token・account がない場合は保存済み認証へ切り替えない" {
  run env -u CLOUDFLARE_API_TOKEN python3 -I "$SCRIPT" d1 list
  [ "$status" -ne 0 ]
  [ ! -e "$CF_TEST_LOG" ]
  run env CLOUDFLARE_ACCOUNT_ID=bad python3 -I "$SCRIPT" d1 list
  [ "$status" -ne 0 ]
  [ ! -e "$CF_TEST_LOG" ]
}

@test "Cloudflare の版不一致・失敗・不正 JSON は秘密値を表示しない" {
  printf '%s\n' wrong >"$BATS_TEST_TMPDIR/version"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -ne 0 ]
  [ ! -e "$CF_TEST_LOG" ]
  printf '%s\n' 1.0.0-beta.24 >"$BATS_TEST_TMPDIR/version"
  printf '%s\n' 'not JSON DUMMY_CF_TOKEN DUMMY_SECRET' >"$CF_TEST_RESPONSE"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -ne 0 ]
  [[ "$output" != *DUMMY_CF_TOKEN* && "$output" != *DUMMY_SECRET* ]]
  touch "$BATS_TEST_TMPDIR/fail"
  run python3 -I "$SCRIPT" d1 list
  [ "$status" -ne 0 ]
  [[ "$output" != *DUMMY_CF_TOKEN* && "$output" != *DUMMY_SECRET* ]]
}

@test "Cloudflare の検査入口を許可し reviewed を確認、生 CLI を拒否する" {
  local command expected
  for command in 'cloudflare-inspect d1 list' 'cloudflare-inspect --reviewed d1 get db' 'cf d1 list' 'cloudflare d1 list' 'command cf d1 list' 'env cloudflare d1 list' '/usr/bin/cf d1 list'; do
    case "$command" in
    'cloudflare-inspect --reviewed'*) expected=prompt ;;
    'cloudflare-inspect '*) expected=allow ;;
    *) expected=forbidden ;;
    esac
    read -r -a arguments <<<"$command"
    run --separate-stderr codex execpolicy check --rules "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" -- "${arguments[@]}"
    [ "$status" -eq 0 ]
    [ "$(jq -r .decision <<<"$output")" = "$expected" ]
  done
}

@test "Claude の共通設定と repo 設定は Cloudflare の同じ権限境界を保つ" {
  local settings="$BATS_TEST_TMPDIR/claude-settings.json"
  mkdir -p "$BATS_TEST_TMPDIR/home"
  printf '{}\n' >"$BATS_TEST_TMPDIR/chezmoi.yaml"
  env HOME="$BATS_TEST_TMPDIR/home" chezmoi --source "$PROJECT_ROOT" --destination "$BATS_TEST_TMPDIR/home" \
    --config "$BATS_TEST_TMPDIR/chezmoi.yaml" execute-template \
    <"$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" >"$settings"
  local file
  for file in "$settings" "$PROJECT_ROOT/.claude/settings.json"; do
    run jq -e '
      (.permissions.allow | index("Bash(cloudflare-inspect:*)") != null)
      and (.permissions.ask | index("Bash(cloudflare-inspect --reviewed:*)") != null)
      and (.permissions.deny | index("Bash(cf:*)") != null)
      and (.permissions.deny | index("Bash(cloudflare:*)") != null)
      and (.permissions.deny | index("Bash(command cf:*)") != null)
      and (.permissions.deny | index("Bash(env cloudflare:*)") != null)
    ' "$file"
    [ "$status" -eq 0 ]
  done
}
