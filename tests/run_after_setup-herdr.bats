#!/usr/bin/env bats

# Bats gives each test its own subshell and setup environment.
# shellcheck disable=SC2030,SC2031

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CHEZMOI_SOURCE_DIR="$BATS_TEST_TMPDIR/source tree"
  export TEST_PLUGIN_STATE="$BATS_TEST_TMPDIR/state.json"
  export TEST_LINK_LOG="$BATS_TEST_TMPDIR/link.log"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  mkdir -p "$HOME/.config/nix-devshell/lib" "$BATS_TEST_TMPDIR/bin"
  printf 'ensure_nix_devshell_env() { :; }\n' >"$HOME/.config/nix-devshell/lib/ensure-env.sh"
  git init -q -b main "$CHEZMOI_SOURCE_DIR"
  cp -R "$PROJECT_ROOT/.herdr" "$CHEZMOI_SOURCE_DIR/.herdr"
  printf '{"result":{"plugins":[]}}\n' >"$TEST_PLUGIN_STATE"
  cat >"$BATS_TEST_TMPDIR/bin/herdr" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "$2" = list ]; then
  [ "${TEST_LIST_FAIL:-0}" = 0 ] || exit 24
  cat "$TEST_PLUGIN_STATE"
else
  [ "${TEST_LINK_FAIL:-0}" = 0 ] || exit 25
  printf '%s\n' "$@" >>"$TEST_LINK_LOG"
  enabled=true
  [ "${4:-}" != --disabled ] || enabled=false
  jq -n --arg root "$3" --argjson enabled "$enabled" \
    '{result:{plugins:[{plugin_id:"dotfiles.copy-env",plugin_root:$root,enabled:$enabled}]}}' >"$TEST_PLUGIN_STATE"
fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/herdr"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

run_setup() {
  run "${HERDR_SETUP_BASH:-bash}" "$PROJECT_ROOT/run_after_setup-herdr.sh"
}

set_existing() {
  jq -n --arg root "$1" --argjson enabled "$2" \
    '{result:{plugins:[{plugin_id:"dotfiles.copy-env",plugin_root:$root,enabled:$enabled}]}}' >"$TEST_PLUGIN_STATE"
}

@test "initial registration uses source path with spaces and repeated apply is a no-op" {
  run_setup
  [ "$status" -eq 0 ]
  [ "$(jq -r '.result.plugins[0].plugin_root' "$TEST_PLUGIN_STATE")" = "$CHEZMOI_SOURCE_DIR/.herdr" ]
  [ "$(jq -r '.result.plugins[0].enabled' "$TEST_PLUGIN_STATE")" = true ]
  run_setup
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TEST_LINK_LOG")" -eq 3 ]
}

@test "manual disable stays disabled without relinking" {
  set_existing "$CHEZMOI_SOURCE_DIR/.herdr" false
  run_setup
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_LINK_LOG" ]
  [ "$(jq -r '.result.plugins[0].enabled' "$TEST_PLUGIN_STATE")" = false ]
}

@test "source relocation preserves both enabled and disabled state" {
  for enabled in true false; do
    set_existing "$BATS_TEST_TMPDIR/old source/.herdr" "$enabled"
    run_setup
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.plugins[0].enabled' "$TEST_PLUGIN_STATE")" = "$enabled" ]
    [ "$(jq -r '.result.plugins[0].plugin_root' "$TEST_PLUGIN_STATE")" = "$CHEZMOI_SOURCE_DIR/.herdr" ]
  done
}

@test "listing and linking failures are propagated and retry can succeed" {
  export TEST_LIST_FAIL=1
  run_setup
  [ "$status" -eq 24 ]
  [ ! -e "$TEST_LINK_LOG" ]
  export TEST_LIST_FAIL=0 TEST_LINK_FAIL=1
  run_setup
  [ "$status" -eq 25 ]
  export TEST_LINK_FAIL=0
  run_setup
  [ "$status" -eq 0 ]
}

@test "malformed list responses never trigger registration" {
  for state in 'invalid' '{}' '{"result":{"plugins":[{}]}}'; do
    printf '%s\n' "$state" >"$TEST_PLUGIN_STATE"
    run_setup
    [ "$status" -ne 0 ]
    [ ! -e "$TEST_LINK_LOG" ]
  done
}

@test "linked task source is refused before registration" {
  git -C "$CHEZMOI_SOURCE_DIR" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm 'test: seed'
  git -C "$CHEZMOI_SOURCE_DIR" worktree add -qb test/task "$BATS_TEST_TMPDIR/task"
  export CHEZMOI_SOURCE_DIR="$BATS_TEST_TMPDIR/task"
  run_setup
  [ "$status" -ne 0 ]
  [[ "$output" == *'primary Git checkout'* ]]
  [ ! -e "$TEST_LINK_LOG" ]
}

@test "missing environment library fails visibly" {
  mv "$HOME/.config/nix-devshell/lib/ensure-env.sh" "$HOME/retained-lib"
  run_setup
  [ "$status" -ne 0 ]
  [[ "$output" == *'required environment library'* ]]
}

@test "chezmoi executes registration with its actual source environment on every apply" {
  cp "$PROJECT_ROOT/run_after_setup-herdr.sh" "$CHEZMOI_SOURCE_DIR/"
  printf '.herdr\n.herdr/**\n' >"$CHEZMOI_SOURCE_DIR/.chezmoiignore"
  for _ in 1 2; do
    printf '{"result":{"plugins":[]}}\n' >"$TEST_PLUGIN_STATE"
    run env -u CHEZMOI_SOURCE_DIR chezmoi --source "$CHEZMOI_SOURCE_DIR" \
      --destination "$HOME" --config "$BATS_TEST_TMPDIR/chezmoi.toml" \
      --cache "$BATS_TEST_TMPDIR/cache" --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state" apply
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.plugins[0].enabled' "$TEST_PLUGIN_STATE")" = true ]
  done
  [ "$(wc -l <"$TEST_LINK_LOG")" -eq 6 ]
}

@test "missing Herdr after loading the environment fails visibly" {
  mkdir "$BATS_TEST_TMPDIR/empty-bin"
  printf 'ensure_nix_devshell_env() { export PATH="%s"; }\n' "$BATS_TEST_TMPDIR/empty-bin" >"$HOME/.config/nix-devshell/lib/ensure-env.sh"
  run_setup
  [ "$status" -ne 0 ]
  [[ "$output" == *'required command is missing: herdr'* ]]
}

@test "real Herdr registration and global worktree events" {
  [ "${HERDR_COPY_ENV_REAL:-0}" = 1 ] || skip "opt in with HERDR_COPY_ENV_REAL=1; starts an isolated Herdr server"
  # setup installs a fake CLI; the live probe needs the original PATH.
  PATH="${PATH#*:}" run python3 "$PROJECT_ROOT/tests/helpers/herdr-copy-env-live.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "live helper reaps servers after stop and termination failures" {
  run python3 -B "$PROJECT_ROOT/tests/helpers/herdr-copy-env-cleanup.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

# Reproduce with HERDR_SETUP_BASH=/absolute/path/to/bash-3.2 bats tests/run_after_setup-herdr.bats.
@test "Bash 3.2 registers empty arguments and preserves disabled relocation" {
  [ -n "${HERDR_SETUP_BASH:-}" ] || skip "opt in with HERDR_SETUP_BASH pointing to Bash 3.2"
  run "$HERDR_SETUP_BASH" -c 'test "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" = 3.2'
  [ "$status" -eq 0 ]
  run_setup
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TEST_LINK_LOG")" -eq 3 ]
  set_existing "$BATS_TEST_TMPDIR/old source/.herdr" false
  run_setup
  [ "$status" -eq 0 ]
  [ "$(jq -r '.result.plugins[0].enabled' "$TEST_PLUGIN_STATE")" = false ]
  [ "$(wc -l <"$TEST_LINK_LOG")" -eq 7 ]
}
