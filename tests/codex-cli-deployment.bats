#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  CACHE="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/lib" "$FAKE_HOME/.cache" "$FAKE_HOME/releases/first/bin"
  : >"$FAKE_HOME/.config/nix-devshell/flake.nix"
  printf 'first\n' >"$FAKE_HOME/.config/nix-devshell/version"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/lib/refresh-cache.sh" "$FAKE_HOME/.config/nix-devshell/lib/"
  cp "$PROJECT_ROOT/dot_bash_profile.tmpl" "$FAKE_HOME/.bash_profile"
  cp "$PROJECT_ROOT/dot_bashrc.tmpl" "$FAKE_HOME/.bashrc"
  stub_nix_cache_profile "$CACHE"
  for name in find grep mkdir mv rm tee cat dirname mktemp date tail readlink perl ln; do
    stub_real_cmd "$name"
  done
  stub_hash_cmd
  cat >"$FAKE_HOME/releases/first/bin/codex" <<'CLI'
#!/bin/sh
printf 'codex-cli first\n'
CLI
  chmod +x "$FAKE_HOME/releases/first/bin/codex"
  cat >"$TEST_BIN_DIR/nix" <<'NIX'
#!/bin/bash
printf 'nix %s\n' "$*" >>"$TEST_LOG"
printf 'export NIX_DEVSHELL_CODEX_BIN=%q\n' "$HOME/releases/$(cat "$HOME/.config/nix-devshell/version")/bin/codex"
NIX
  chmod +x "$TEST_BIN_DIR/nix"
}

deploy() {
  run env -i HOME="$FAKE_HOME" PATH="$TEST_BIN_DIR" TEST_LOG="$TEST_LOG" WSL_DISTRO_NAME=Ubuntu \
    /bin/bash "$PROJECT_ROOT/run_after_00-refresh-nix-devshell-cache.sh"
}

check_codex() {
  run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin TEST_LOG="$TEST_LOG" \
    /bin/bash --noprofile -lc '. "$HOME/.bash_profile"; codex --version'
  assert_success
  assert_output "codex-cli $1"
}

refresh() {
  run env -i HOME="$FAKE_HOME" PATH="$TEST_BIN_DIR" TEST_LOG="$TEST_LOG" WSL_DISTRO_NAME=Ubuntu \
    NIX_DEVSHELL_CACHE_REQUIRED="${1:-1}" \
    /bin/bash -c '. "$HOME/.config/nix-devshell/lib/refresh-cache.sh"; refresh_nix_devshell_cache'
}

select_second_version() {
  mkdir -p "$FAKE_HOME/releases/second/bin"
  printf '#!/bin/sh\nprintf "codex-cli second\\n"\n' >"$FAKE_HOME/releases/second/bin/codex"
  chmod +x "$FAKE_HOME/releases/second/bin/codex"
  printf 'second\n' >"$FAKE_HOME/.config/nix-devshell/version"
}

@test "配備した Codex を非対話ログインから起動できる" {
  deploy
  assert_success
  check_codex first
}

@test "pin 更新後の明示キャッシュ更新で選択版へ切り替わる" {
  deploy
  assert_success
  select_second_version

  refresh
  assert_success
  check_codex second
}

@test "最新キャッシュの背景更新でも欠けた入口を復旧する" {
  deploy
  assert_success
  rm "$FAKE_HOME/.local/bin/codex"
  : >"$TEST_LOG"

  refresh 0
  assert_success
  refute_log_contains 'nix print-dev-env'
  check_codex first
}

@test "公開と同時に作られたユーザーファイルも保持して配備を続行する" {
  cat >"$TEST_BIN_DIR/ln" <<'LINK'
#!/bin/bash
if [ "$3" = "$HOME/.local/bin/codex" ]; then
  printf 'user-owned\n' >"$3"
  exit 1
fi
exec /bin/ln "$@"
LINK

  deploy

  assert_success
  [ "$(cat "$FAKE_HOME/.local/bin/codex")" = user-owned ]
}

@test "公開と同時に作られたユーザーのリンクも警告して保持する" {
  cat >"$TEST_BIN_DIR/mv" <<'MOVE'
#!/bin/bash
/bin/mv "$@" || exit 1
if [ "$2" = "$HOME/.cache/nix-devshell-global-env.bash.codex" ]; then
  /bin/ln -s "$HOME/user-codex" "$HOME/.local/bin/codex"
fi
MOVE

  deploy

  assert_success
  assert_output --partial '公開中に作られた'
  [ "$(readlink "$FAKE_HOME/.local/bin/codex")" = "$FAKE_HOME/user-codex" ]
}

@test "ユーザーの通常ファイルとリンクを保持して警告し配備を続行する" {
  local entry="$FAKE_HOME/.local/bin/codex" kind target
  mkdir -p "$(dirname "$entry")"
  for kind in file executable link broken store; do
    case "$kind" in
    file | executable)
      printf 'user-owned\n' >"$entry"
      [ "$kind" != executable ] || chmod +x "$entry"
      ;;
    link)
      target="$FAKE_HOME/releases/first/bin/codex"
      ln -s "$target" "$entry"
      ;;
    broken)
      target="$FAKE_HOME/missing"
      ln -s "$target" "$entry"
      ;;
    store)
      target=/nix/store/user-codex/bin/codex
      ln -s "$target" "$entry"
      ;;
    esac

    deploy

    assert_success
    assert_output --partial '管理対象外'
    if [ -L "$entry" ]; then
      [ "$(readlink "$entry")" = "$target" ]
    else
      [ "$(cat "$entry")" = user-owned ]
    fi
    rm "$entry"
  done
}

@test "入口の更新失敗では旧 CLI を保持し必須更新は失敗して背景更新は続行し再実行で揃う" {
  deploy
  assert_success
  select_second_version
  cat >"$TEST_BIN_DIR/mv" <<'MOVE'
#!/bin/bash
case "$2" in *.codex) exit 23;; esac
exec /bin/mv "$@"
MOVE

  refresh 1
  assert_failure
  check_codex first
  refresh 0
  assert_success
  check_codex first
  grep -q 'Codex の公開に失敗' "$FAKE_HOME/.cache/nix-devshell-refresh.log"

  stub_real_cmd mv
  : >"$TEST_LOG"
  refresh
  assert_success
  refute_log_contains 'nix print-dev-env'
  check_codex second
}

@test "Nix 評価の失敗では公開済みの CLI を切り替えない" {
  deploy
  assert_success
  select_second_version
  printf '\nexit 23\n' >>"$TEST_BIN_DIR/nix"

  refresh

  assert_failure
  check_codex first
}

@test "未定義変数を参照する Nix キャッシュも必須配備で読み込める" {
  cat >>"$TEST_BIN_DIR/nix" <<'NIX'
printf '%s\n' ': "$PS1"'
NIX

  deploy

  assert_success
  check_codex first
}
