#!/usr/bin/env bats

load 'test_helper'

@test "キャッシュ更新後のプロンプトで作業中の PATH と仮想環境を上書きしない" {
  setup_test_env
  local test_home="$BATS_TEST_TMPDIR/home" source="$BATS_TEST_DIRNAME/.."
  mkdir -p "$test_home/.config/nix-devshell/lib" "$test_home/.cache" "$test_home/project-tools"
  cp "$source/private_dot_config/nix-devshell/lib/ensure-env.sh" "$test_home/.config/nix-devshell/lib/"
  printf 'export PATH=/usr/bin:/bin\n' >"$test_home/.cache/nix-devshell-global-env.bash"
  sed "s#{{ .workspace_folder }}#$test_home#g" "$source/dot_bashrc.tmpl" >"$test_home/bashrc"
  stub_cmd nix
  run env -i HOME="$test_home" PATH="$TEST_BIN_DIR:/usr/bin:/bin" TEST_LOG="$TEST_LOG" \
    NIX_PROFILES=fixture TERM=dumb /bin/bash --noprofile --norc -ic '
      . "$HOME/bashrc"
      PATH="$HOME/project-tools:$PATH"
      export VIRTUAL_ENV="$HOME/venv"
      printf "export PATH=/usr/bin:/bin\nexport VIRTUAL_ENV=wrong\n" >"$HOME/.cache/nix-devshell-global-env.bash"
      eval "${PROMPT_COMMAND:-:}"
      [[ "$PATH" == "$HOME/project-tools:/usr/bin:/bin" ]]
      [[ "$VIRTUAL_ENV" == "$HOME/venv" ]]
    '
  assert_success
}
