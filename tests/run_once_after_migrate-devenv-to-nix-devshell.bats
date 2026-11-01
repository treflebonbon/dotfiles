#!/usr/bin/env bats

@test "旧 devenv は flake と独自の追加設定を保持して案内する" {
  local test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/devenv"
  printf '# independent config\n' >"$test_home/.config/devenv/flake.nix"
  printf '# personal additions\n' >"$test_home/.config/devenv/personal.nix"

  run env HOME="$test_home" bash "$BATS_TEST_DIRNAME/../run_once_after_migrate-devenv-to-nix-devshell.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *保持しました* ]]
  [ "$(cat "$test_home/.config/devenv/flake.nix")" = '# independent config' ]
  [ "$(cat "$test_home/.config/devenv/personal.nix")" = '# personal additions' ]
}
