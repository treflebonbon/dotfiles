#!/usr/bin/env bats

load 'test_helper'

readonly LIB="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/refresh-cache.sh"

setup() {
  setup_test_env

  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.config/nix-devshell" "$FAKE_HOME/.cache"
  : >"$FAKE_HOME/.config/nix-devshell/flake.nix"
  : >"$FAKE_HOME/.config/nix-devshell/flake.lock"

  stub_real_cmd find
  stub_real_cmd grep
  stub_real_cmd mkdir
  stub_real_cmd mv
  stub_real_cmd rm
  stub_real_cmd touch
  stub_real_cmd tee
  stub_real_cmd cat
  stub_real_cmd dirname
  stub_real_cmd mktemp
  stub_real_cmd date
}

run_refresh() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash --noprofile --norc -c ". '$LIB' && refresh_nix_devshell_cache"
}

run_required_refresh() {
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR" \
    HOME="$FAKE_HOME" \
    TEST_LOG="$TEST_LOG" \
    NIX_DEVSHELL_CACHE_REQUIRED=1 \
    /bin/bash --noprofile --norc -c ". '$LIB' && refresh_nix_devshell_cache"
}

@test "lib を source して関数が定義される" {
  run /bin/bash -c ". '$LIB' && declare -F refresh_nix_devshell_cache >/dev/null"
  assert_success
}

@test "\$DIR が無ければ exit 0 + 副作用なし" {
  rm -rf "$FAKE_HOME/.config/nix-devshell"
  stub_cmd nix
  run_refresh
  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "nix コマンドが PATH に無ければ exit 0" {
  run_refresh
  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "必須更新はキャッシュがあっても flake の欠落で失敗する" {
  stub_cmd nix
  echo 'export CACHE_VERSION=old' >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  mv "$FAKE_HOME/.config/nix-devshell/flake.nix" "$FAKE_HOME/unused-flake"

  run_required_refresh

  assert_failure
  [ "$(cat "$FAKE_HOME/.cache/nix-devshell-global-env.bash")" = 'export CACHE_VERSION=old' ]
}

@test ".git/ がコミット 0 件なら silent 削除し stdout に通知" {
  stub_cmd nix
  cat >"$TEST_BIN_DIR/git" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [[ "$*" == *"rev-parse --verify HEAD"* ]]; then
  exit 1
fi
exit 0
STUB
  chmod +x "$TEST_BIN_DIR/git"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/.git/objects"

  run_refresh

  assert_success
  [ ! -d "$FAKE_HOME/.config/nix-devshell/.git" ]
  echo "$output" | grep -q "removed untracked .git/"
}

@test ".git/ にコミットあれば削除せず警告し refresh を skip" {
  stub_cmd nix
  cat >"$TEST_BIN_DIR/git" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [[ "$*" == *"rev-parse --verify HEAD"* ]]; then
  exit 0
fi
exit 0
STUB
  chmod +x "$TEST_BIN_DIR/git"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/.git/objects"

  run_refresh

  assert_success
  [ -d "$FAKE_HOME/.config/nix-devshell/.git" ]
  echo "$output" | grep -q "has user commits"
  refute_log_contains "nix print-dev-env"
}

@test "cache が flake.lock より新しければ no-op" {
  stub_cmd nix
  : >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  touch -d '2020-01-01' "$FAKE_HOME/.config/nix-devshell/flake.lock"
  run_refresh
  assert_success
  refute_log_contains "nix print-dev-env"
}

@test "cache 不在なら nix print-dev-env が呼ばれ cache が書かれる" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
echo 'export PATH=/nix/store/fake/bin:$PATH'
STUB
  chmod +x "$TEST_BIN_DIR/nix"

  run_refresh

  assert_success
  assert_log_contains "nix print-dev-env"
  grep -q '/nix/store/fake/bin' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  echo "$output" | grep -q "cache refreshed"
}

@test "cache 生成時に nix の SHELL/BASH を保存しない" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
echo "BASH='/nix/store/fake-bash/bin/bash'"
echo "SHELL='/nix/store/fake-bash/bin/bash'"
echo "export SHELL"
echo 'export PATH=/nix/store/fake/bin:$PATH'
STUB
  chmod +x "$TEST_BIN_DIR/nix"

  run_refresh

  assert_success
  if grep -q "^BASH=" "$FAKE_HOME/.cache/nix-devshell-global-env.bash"; then
    return 1
  fi
  if grep -q "^SHELL=" "$FAKE_HOME/.cache/nix-devshell-global-env.bash"; then
    return 1
  fi
  grep -q '/nix/store/fake/bin' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
}

@test "nix print-dev-env が失敗したら cache 温存・stderr 案内・log 追記" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
echo "error: flake evaluation failed at packages/waza.nix" >&2
exit 1
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  # shellcheck disable=SC2016
  echo 'export PATH=/nix/store/old/bin:$PATH' >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  touch -d '2020-01-01' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  touch -d '2030-01-01' "$FAKE_HOME/.config/nix-devshell/flake.lock"

  run_refresh

  assert_success
  grep -q '/nix/store/old/bin' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  echo "$output" | grep -q "see .*nix-devshell-refresh.log"
  grep -q "flake evaluation failed" "$FAKE_HOME/.cache/nix-devshell-refresh.log"
}

@test "required refresh は nix print-dev-env 失敗時に fail closed し cache を温存する" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "error: flake evaluation failed" >&2
exit 1
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  echo 'export PATH=/nix/store/old/bin:$PATH' >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  touch -d '2020-01-01' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  touch -d '2030-01-01' "$FAKE_HOME/.config/nix-devshell/flake.lock"

  run_required_refresh

  assert_failure
  grep -q '/nix/store/old/bin' "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
}

@test "fail-open: 失敗しても return 0" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
exit 1
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  touch -d '2030-01-01' "$FAKE_HOME/.config/nix-devshell/flake.lock"

  run_refresh

  assert_success
}

@test "ユーザー環境キャッシュは pipefail によらず Nix の失敗出力を採用しない" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo 'export CACHE_VERSION=partial'
echo 'evaluation failed after partial output' >&2
exit 23
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf '%s\n' 'export CACHE_VERSION=old' >"$cache"
  touch -d '2020-01-01' "$cache"

  local required pipefail
  for required in 0 1; do
    for pipefail in +o -o; do
      run /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$FAKE_HOME" TEST_LOG="$TEST_LOG" \
        NIX_DEVSHELL_CACHE_REQUIRED="$required" \
        /bin/bash --noprofile --norc -c '
          . "$1"
          set -eu
          set "$2" pipefail
          before=$SHELLOPTS
          if refresh_nix_devshell_cache; then result=0; else result=$?; fi
          [ "$before" = "$SHELLOPTS" ] || exit 99
          exit "$result"
        ' _ "$LIB" "$pipefail"
      [ "$status" -eq "$required" ]
      [ "$(cat "$cache")" = 'export CACHE_VERSION=old' ]
      assert_output --partial 'failed'
      grep -q 'evaluation failed after partial output' "$FAKE_HOME/.cache/nix-devshell-refresh.log"
    done
  done
}

@test "ユーザー環境キャッシュは壊れた生成結果を保持せず次の更新で復旧する" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
cat "$HOME/candidate"
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf '%s\n' 'export CACHE_VERSION=old' >"$cache"
  touch -d '2020-01-01' "$cache"

  local candidate
  for candidate in "export CACHE_VERSION='" ''; do
    printf '%s' "$candidate" >"$FAKE_HOME/candidate"
    run_required_refresh
    assert_failure
    [ "$(cat "$cache")" = 'export CACHE_VERSION=old' ]
  done

  printf '%s\n' 'export CACHE_VERSION=fresh' >"$FAKE_HOME/candidate"
  run_required_refresh
  assert_success
  [ "$(cat "$cache")" = 'export CACHE_VERSION=fresh' ]
}

@test "ユーザー環境キャッシュの置換失敗は必須更新を失敗させ再実行できる" {
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo 'export CACHE_VERSION=fresh'
STUB
  chmod +x "$TEST_BIN_DIR/nix"
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf '%s\n' 'export CACHE_VERSION=old' >"$cache"
  touch -d '2020-01-01' "$cache"
  stub_cmd mv 1

  run_required_refresh
  assert_failure
  [ "$(cat "$cache")" = 'export CACHE_VERSION=old' ]

  stub_real_cmd mv
  run_required_refresh
  assert_success
  [ "$(cat "$cache")" = 'export CACHE_VERSION=fresh' ]
}

@test "一時ファイルを準備できない更新は旧キャッシュを保持する" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  echo 'export CACHE_VERSION=old' >"$cache"
  touch -t 202001010000 "$cache"
  touch "$FAKE_HOME/blocked"

  local required
  for required in 0 1; do
    run /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$FAKE_HOME" TEST_LOG="$TEST_LOG" \
      NIX_DEVSHELL_CACHE_REQUIRED="$required" /bin/bash -ec '
        . "$1"
        refresh_nix_devshell_cache "$HOME/.config/nix-devshell" "$2" "$HOME/blocked/refresh.log"
      ' _ "$LIB" "$cache"

    [ "$status" -eq "$required" ]
    [ "$(cat "$cache")" = 'export CACHE_VERSION=old' ]
  done
}
