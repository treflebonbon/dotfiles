#!/usr/bin/env bats

# pre-commit の shfmt は staged file だけを整形するため、触られていない file の整形のずれをここで検出する。
@test "every tracked .sh and .bash file is shfmt-formatted" {
  cd "$BATS_TEST_DIRNAME/.."
  mapfile -t files < <(git ls-files '*.sh' '*.bash' ':!:.agents/skills/**' ':!:private_dot_config/bash/bash-preexec.sh')
  [ "${#files[@]}" -gt 0 ]
  run shfmt -l "${files[@]}"
  [ -z "$output" ] || { printf 'shfmt -w で整形する:\n%s\n' "$output"; false; }
}
