#!/usr/bin/env bats

load 'test_helper'

readonly LIB="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/lib/ensure-env.sh"

setup() {
  setup_test_env
  export FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.cache"
}

@test "ensure-env preserves interactive shell identity from nix print-dev-env cache" {
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  cat >"$cache" <<'CACHE'
BASH='/nix/store/fake-bash/bin/bash'
SHELL='/nix/store/fake-bash/bin/bash'
export SHELL
export PATH='/nix/store/fake-bash/bin:/nix/store/tool/bin:/usr/bin:/bin'
CACHE

  run /usr/bin/env -i \
    HOME="$FAKE_HOME" \
    SHELL="/bin/bash" \
    PATH="/usr/bin:/bin" \
    /bin/bash -c ". '$LIB' && ensure_nix_devshell_env '$cache' && printf 'SHELL=%s\nBASH=%s\nPATH=%s\n' \"\$SHELL\" \"\$BASH\" \"\$PATH\""

  assert_success
  assert_line "SHELL=/bin/bash"
  assert_line "BASH=/bin/bash"
  assert_output --partial "/nix/store/tool/bin"
}

@test "ensure-env repairs inherited nix-store SHELL when runtime bash is usable" {
  local cache="$FAKE_HOME/.cache/nix-devshell-global-env.bash"
  cat >"$cache" <<'CACHE'
SHELL='/nix/store/fake-bash/bin/bash'
export SHELL
CACHE

  run /usr/bin/env -i \
    HOME="$FAKE_HOME" \
    SHELL="/nix/store/old-bash/bin/bash" \
    PATH="/usr/bin:/bin" \
    /bin/bash -c ". '$LIB' && ensure_nix_devshell_env '$cache' && printf 'SHELL=%s\nBASH=%s\n' \"\$SHELL\" \"\$BASH\""

  assert_success
  assert_line "SHELL=/bin/bash"
  assert_line "BASH=/bin/bash"
}
