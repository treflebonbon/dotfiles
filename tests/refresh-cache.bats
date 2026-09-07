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
  stub_real_cmd sha256sum
  stub_real_cmd tail
  stub_real_cmd readlink
  stub_real_cmd perl
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
    WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-}" \
    NIX_DEVSHELL_CACHE_REQUIRED=1 \
    /bin/bash --noprofile --norc -c ". '$LIB' && refresh_nix_devshell_cache"
}

assert_cache_version() {
  run /bin/bash --noprofile --norc -c '
    . "$1"
    ensure_nix_devshell_env "$2"
    printf "%s\n" "$CACHE_VERSION"
  ' _ "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/ensure-env.sh" "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  assert_success
  assert_output "$1"
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

@test "ユーザー環境キャッシュは同じ入力を再評価せず時刻を保った非 Nix 変更を反映する" {
  local source="$FAKE_HOME/.config/nix-devshell"
  mkdir -p "$source/packages"
  printf '%s\n' old >"$source/packages/tool.mjs"
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
printf 'export CACHE_VERSION=%s\n' "$(cat packages/tool.mjs)"
STUB
  chmod +x "$TEST_BIN_DIR/nix"

  run_required_refresh
  assert_success
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'

  touch -r "$source/packages/tool.mjs" "$FAKE_HOME/original-time"
  printf '%s\n' fresh >"$source/packages/tool.mjs"
  touch -r "$FAKE_HOME/original-time" "$source/packages/tool.mjs"
  run_required_refresh
  assert_success
  assert_log_contains 'nix print-dev-env'
  run /bin/bash -c '. "$1"; printf "%s\n" "$CACHE_VERSION"' _ "$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  assert_output fresh
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
  assert_cache_version fresh
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
  assert_cache_version fresh
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

@test "キャッシュの保存先がディレクトリなら必須更新を成功扱いにしない" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  mkdir "$cache"

  run_required_refresh
  assert_failure
  [ -d "$cache" ]
  [ -z "$(find "$cache" -type f)" ]

  mv "$cache" "$FAKE_HOME/held-directory"
  run_required_refresh
  assert_success
  assert_cache_version fresh
}

@test "ソースの追加・削除・改名と空ディレクトリの変化を反映する" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local source="$FAKE_HOME/.config/nix-devshell"
  run_required_refresh
  assert_success

  local change
  for change in add rename delete directory; do
    case "$change" in
    add) printf 'payload\n' >"$source/asset with space.json" ;;
    rename) mv "$source/asset with space.json" "$source/asset" ;;
    delete) mv "$source/asset" "$FAKE_HOME/held-asset" ;;
    directory) mkdir "$source/empty" ;;
    esac
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    assert_log_contains 'nix print-dev-env'
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    refute_log_contains 'nix print-dev-env'
  done
}

@test "通常と WSL の選択差を反映し同じ選択では再評価しない" {
  # host の /proc に依存せず通常環境から開始する。
  cat >"$TEST_BIN_DIR/grep" <<'STUB'
#!/bin/bash
[[ "${*: -1}" != /proc/sys/kernel/osrelease ]] || exit 1
exec /bin/grep "$@"
STUB
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
echo "$0 $*" >> "$TEST_LOG"
if [[ "$*" == 'print-dev-env .#wsl' ]]; then
  echo 'export CACHE_VERSION=wsl'
else
  echo 'export CACHE_VERSION=default'
fi
STUB
  chmod +x "$TEST_BIN_DIR/nix"

  local selected
  for selected in default wsl default; do
    export WSL_DISTRO_NAME=""
    [ "$selected" != wsl ] || export WSL_DISTRO_NAME=Ubuntu
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    assert_log_contains 'nix print-dev-env'
    assert_cache_version "$selected"
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    refute_log_contains 'nix print-dev-env'
  done
}

@test "実行時の direnv 状態と Nix result link は再評価を誘発しない" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local source="$FAKE_HOME/.config/nix-devshell"
  run_required_refresh
  assert_success
  mkdir -p "$source/.direnv"
  printf 'generated\n' >"$source/.direnv/flake-profile"
  ln -s /nix/store/first "$source/result"
  ln -s /nix/store/second "$source/result-dev"
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'

  printf 'changed runtime\n' >"$source/.direnv/flake-profile"
  touch "$source/flake.nix"
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'
}

@test "旧形式を読み込めて必須更新後は入力が同じなら再評価しない" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  echo 'export CACHE_VERSION=legacy' >"$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  assert_cache_version legacy
  run_required_refresh
  assert_success
  assert_cache_version fresh
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'
}

@test "検査・置換の失敗では旧キャッシュと対応入力情報を一緒に保持する" {
  local source="$FAKE_HOME/.config/nix-devshell" cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  stub_cmd_with_output nix 'export CACHE_VERSION=old'
  run_required_refresh
  assert_success
  cp "$cache" "$FAKE_HOME/accepted-cache"

  local failure
  for failure in syntax empty rename fingerprint; do
    printf '%s\n' "$failure" >"$source/asset"
    case "$failure" in
    syntax) stub_cmd_with_output nix "export CACHE_VERSION='" ;;
    empty) stub_cmd nix ;;
    rename)
      stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
      stub_cmd mv 1
      ;;
    fingerprint) stub_cmd sha256sum 1 ;;
    esac
    run_required_refresh
    assert_failure
    cmp "$cache" "$FAKE_HOME/accepted-cache"
    assert_cache_version old

    stub_real_cmd mv
    stub_real_cmd sha256sum
    mv "$source/asset" "$FAKE_HOME/held-asset"
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    refute_log_contains 'nix print-dev-env'
  done

  printf 'latest\n' >"$source/asset"
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  run_required_refresh
  assert_success
  assert_cache_version fresh
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'
}

@test "初回生成に shasum を使えて sha256sum へ切り替わっても再評価しない" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  mv "$TEST_BIN_DIR/sha256sum" "$FAKE_HOME/held-sha256sum"
  stub_real_cmd shasum
  run_required_refresh
  assert_success
  assert_cache_version fresh
  mv "$FAKE_HOME/held-sha256sum" "$TEST_BIN_DIR/sha256sum"
  : >"$TEST_LOG"
  run_required_refresh
  assert_success
  refute_log_contains 'nix print-dev-env'
}

@test "指紋の依存欠損は必須更新を失敗させ背景更新は旧環境を利用できる" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  run_required_refresh
  assert_success
  mv "$TEST_BIN_DIR/sha256sum" "$FAKE_HOME/held-sha256sum"
  : >"$TEST_LOG"
  run_required_refresh
  assert_failure
  refute_log_contains 'nix print-dev-env'
  run_refresh
  assert_success
  assert_cache_version fresh
}

@test "dotfile・改行を含む名前・実行権限・symlink の変更も入力として比較する" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local source="$FAKE_HOME/.config/nix-devshell" change
  run_required_refresh
  assert_success
  for change in hidden newline executable symlink retarget; do
    case "$change" in
    hidden) printf 'hidden\n' >"$source/.asset" ;;
    newline) printf 'data\n' >"$source/"$'line\nbreak' ;;
    executable) chmod +x "$source/.asset" ;;
    symlink) ln -s .asset "$source/package-input" ;;
    retarget)
      mv "$source/package-input" "$FAKE_HOME/held-link"
      ln -s flake.nix "$source/package-input"
      ;;
    esac
    : >"$TEST_LOG"
    run_required_refresh
    assert_success
    assert_log_contains 'nix print-dev-env'
  done

  : >"$TEST_LOG"
  run /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$FAKE_HOME" TEST_LOG="$TEST_LOG" \
    /bin/bash -c '
      . "$1"
      set -euf
      shopt -s nullglob failglob dotglob
      export GLOBIGNORE="*.nix"
      IFS=$(printf "\n\t")
      before="$SHELLOPTS:$BASHOPTS:$GLOBIGNORE"
      NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache
      [ "$before" = "$SHELLOPTS:$BASHOPTS:$GLOBIGNORE" ]
    ' _ "$LIB"
  assert_success
  refute_log_contains 'nix print-dev-env'
}

@test "入力情報付きキャッシュを既存の zsh 起動から取り込める" {
  local zsh_bin
  zsh_bin=$(command -v zsh) || skip 'zsh not installed'
  stub_real_cmd bash
  stub_cmd_with_output nix 'export ZSH_AUTOSUGGESTIONS_SHARE=$HOME/plugin.zsh'
  echo 'echo plugin-loaded >> "$TEST_LOG"' >"$FAKE_HOME/plugin.zsh"
  run_required_refresh
  assert_success

  run /usr/bin/env -i PATH="$TEST_BIN_DIR" HOME="$FAKE_HOME" TEST_LOG="$TEST_LOG" \
    "$zsh_bin" -c '. "$1"; true' _ "$BATS_TEST_DIRNAME/../dot_zshrc.tmpl"
  assert_success
  assert_log_contains plugin-loaded
}

@test "ロックの依存や保存先の不備では旧キャッシュを保護し復旧後に更新できる" {
  stub_cmd_with_output nix 'export CACHE_VERSION=fresh'
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  printf 'export CACHE_VERSION=old\n' >"$cache"
  mv "$TEST_BIN_DIR/perl" "$FAKE_HOME/held-perl"
  run_required_refresh
  assert_failure
  refute_log_contains 'nix print-dev-env'
  run_refresh
  assert_success
  assert_cache_version old

  mv "$FAKE_HOME/held-perl" "$TEST_BIN_DIR/perl"
  mkdir "$cache.lock"
  run_required_refresh
  assert_failure
  assert_cache_version old
  mv "$cache.lock" "$FAKE_HOME/held-lock-directory"
  run_required_refresh
  assert_success
  assert_cache_version fresh
}
