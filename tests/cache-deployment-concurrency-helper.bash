# shellcheck shell=bash
# 配備入口と実際の更新 lib を、先行する背景更新・入力変更・失敗と重ねる。
check_deployment_cache_concurrency() {
  local runner="$1" test_home="$2" scenario="$3"
  local sync="$test_home/cache-sync" source="$test_home/.config/nix-devshell"
  local cache="$test_home/.cache/nix-devshell-global-env.bash"
  local lib="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/refresh-cache.sh"
  mkdir -p "$sync"
  printf '%s\n' "$scenario" >"$sync/scenario"
  printf 'initial-%s\n' "$scenario" >"$source/payload"
  if [ -f "$cache" ]; then cp "$cache" "$sync/old-cache"; fi
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
[ "$1" = print-dev-env ] || exit 0
role=${CACHE_TEST_ROLE:-client}
sync="$HOME/cache-sync"
scenario=$(cat "$sync/scenario")
value=$(cat "$HOME/.config/nix-devshell/payload")
printf '%s:%s\n' "$role" "$value" >>"$sync/evaluations"
: >"$sync/$role.entered"
if [ "$role" = leader ]; then
  for ((i=0; i<500; i++)); do
    [ ! -f "$sync/release" ] || break
    /bin/sleep 0.02
  done
  printf 'export CACHE_VERSION=%s\n' "$value"
  [ "$scenario" = stable ] || exit 23
elif [ "$scenario" = changing ]; then
  printf '%s-changed\n' "$value" >"$HOME/.config/nix-devshell/payload"
  printf 'export CACHE_VERSION=%s\n' "$value"
elif [ "$scenario" = failure ]; then
  printf 'export CACHE_VERSION=partial\n'
  exit 23
else
  printf 'export CACHE_VERSION=%s\n' "$value"
fi
STUB
  cat >"$TEST_BIN_DIR/perl" <<'STUB'
#!/bin/bash
: >"$HOME/cache-sync/${CACHE_TEST_ROLE:-client}.lock-request"
exec /usr/bin/perl "$@"
STUB
  chmod +x "$TEST_BIN_DIR/nix" "$TEST_BIN_DIR/perl"

  # shellcheck disable=SC2016 # $1 は起動した Bash で展開する。
  /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$test_home" TEST_LOG="$TEST_LOG" \
    CACHE_TEST_ROLE=leader /bin/bash -c '. "$1"; refresh_nix_devshell_cache' _ "$lib" \
    >"$sync/leader.output" 2>&1 3>&- &
  local leader=$! attempt
  for ((attempt = 0; attempt < 250; attempt++)); do
    [ ! -f "$sync/leader.entered" ] || break
    sleep 0.02
  done
  [ -f "$sync/leader.entered" ] || {
    kill "$leader"
    return 1
  }
  (
    for ((attempt = 0; attempt < 250; attempt++)); do
      if [ -f "$sync/client.lock-request" ]; then
        printf 'during-wait\n' >"$source/payload"
        touch "$sync/release"
        exit 0
      fi
      sleep 0.02
    done
    touch "$sync/release"
    exit 1
  ) 3>&- &
  local controller=$!

  "$runner"
  wait "$controller"
  wait "$leader"
  if [ "$scenario" = stable ]; then
    assert_success
    # 読み込みは別 process に閉じ、テストの環境をキャッシュで上書きしない。
    [ "$(/bin/bash -c '. "$1"; echo "$CACHE_VERSION"' _ "$cache")" = during-wait ]
  else
    assert_failure
    if [ -f "$sync/old-cache" ]; then
      cmp "$cache" "$sync/old-cache"
    else
      [ ! -e "$cache" ]
    fi
    local expected=1
    [ "$scenario" != changing ] || expected=2
    [ "$(grep -c '^client:' "$sync/evaluations")" = "$expected" ]
  fi
}
