#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.config/nix-devshell/lib" "$FAKE_HOME/.cache" "$FAKE_HOME/runtime"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/lib/"{refresh-cache,ensure-env}.sh \
    "$FAKE_HOME/.config/nix-devshell/lib/"
  touch "$FAKE_HOME/.config/nix-devshell/flake.nix"
  sed "s#{{ .workspace_folder }}#$FAKE_HOME#g" "$PROJECT_ROOT/dot_bashrc.tmpl" >"$FAKE_HOME/bashrc"
  cp "$PROJECT_ROOT/dot_zshrc.tmpl" "$FAKE_HOME/zshrc"
  cat >"$TEST_BIN_DIR/nix" <<'STUB'
#!/bin/bash
# シェルの起動後に失敗させる。同期更新へ変わった場合も待機を有限にする。
for ((attempt = 0; attempt < 250; attempt++)); do
  if [ -f "$HOME/shell-ready" ]; then
    echo 'export CACHE_VERSION=partial'
    echo 'startup evaluation failed' >&2
    exit 23
  fi
  /bin/sleep 0.02
done
touch "$HOME/startup-waited-for-nix"
exit 24
STUB
  chmod +x "$TEST_BIN_DIR/nix"
}

check_startup() {
  local shell_bin="$1" rc="$2" old_cache="$3"
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  if [ "$old_cache" = 1 ]; then
    # zsh は PATH と plugin の変数を取り込む。PATH の印で両 adapter を検証する。
    printf 'export PATH="%s/old-tools:$PATH"\n' "$FAKE_HOME" >"$cache"
    touch -t 202001010000 "$cache"
  fi

  run timeout 15 /usr/bin/env -i PATH="$TEST_BIN_DIR:/usr/bin:/bin" HOME="$FAKE_HOME" \
    NIX_PROFILES=test SHELL="$shell_bin" XDG_RUNTIME_DIR="$FAKE_HOME/runtime" \
    TERM=xterm TEST_LOG="$TEST_LOG" "$shell_bin" -i -c '
      . "$1"
      printf "PATH=%s\nSHELL=%s\n" "$PATH" "$SHELL"
      touch "$HOME/shell-ready"
      # 背景更新の失敗を観測してから、起動したシェルで後続コマンドを実行する。
      for attempt in {1..250}; do
        if grep -q "cache refresh failed" "$HOME/.cache/nix-devshell-refresh.log" 2>/dev/null; then
          echo shell-continued
          exit 0
        fi
        sleep 0.02
      done
      exit 1
    ' _ "$FAKE_HOME/$rc"

  assert_success
  assert_line 'shell-continued'
  assert_line "SHELL=$shell_bin"
  [ ! -e "$FAKE_HOME/startup-waited-for-nix" ]
  if [ "$old_cache" = 1 ]; then
    assert_output --partial "$FAKE_HOME/old-tools:"
    [ "$(cat "$cache")" = "export PATH=\"$FAKE_HOME/old-tools:\$PATH\"" ]
  else
    [ ! -e "$cache" ]
  fi
}

@test "bash は旧キャッシュを利用し背景更新の失敗後も起動を続ける" {
  check_startup /bin/bash bashrc 1
}

@test "bash はキャッシュ不在でも生成完了を待たず起動する" {
  check_startup /bin/bash bashrc 0
}

@test "zsh は旧キャッシュを利用し背景更新の失敗後も起動を続ける" {
  local zsh_bin
  zsh_bin="$(command -v zsh)" || skip 'zsh not installed in this environment'
  check_startup "$zsh_bin" zshrc 1
}

@test "zsh はキャッシュ不在でも生成完了を待たず起動する" {
  local zsh_bin
  zsh_bin="$(command -v zsh)" || skip 'zsh not installed in this environment'
  check_startup "$zsh_bin" zshrc 0
}
