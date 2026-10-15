#!/usr/bin/env bats

load helpers/codex-home

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHARED_TMP="$(mktemp -d /tmp/codex-shared.XXXXXX)"
  FIXTURE_HOME="$CODEX_TEST_HOME_ROOT/$BATS_TEST_NUMBER/home"
  WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  SESSION_TMP="$BATS_TEST_TMPDIR/session-tmp"
  mkdir -p "$FIXTURE_HOME/.codex" "$WORKSPACE" "$SESSION_TMP"
  chezmoi --source "$PROJECT_ROOT" execute-template \
    -f "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$FIXTURE_HOME/.codex/config.toml"
}

teardown() {
  if [ -d "$SHARED_TMP/locked" ]; then
    chmod 700 "$SHARED_TMP/locked"
  fi
  rm -rf -- "$SHARED_TMP"
}

@test "Codex can use shared /tmp files outside its session TMPDIR" {
  printf 'original\n' >"$SHARED_TMP/shared.txt"

  run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
    codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- sh -c '
      set -eu
      test "$(cat "$1/shared.txt")" = original
      printf "updated\n" >"$1/shared.txt"
      printf "created\n" >"$1/new.txt"
      test "$(cat "$1/new.txt")" = created
      rm "$1/new.txt"
      test ! -e "$1/new.txt"
    ' _ "$SHARED_TMP"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$SHARED_TMP/shared.txt")" = updated ]
  [ ! -e "$SHARED_TMP/new.txt" ]
}

@test "Codex protects sensitive /tmp filenames while public examples remain usable" {
  mkdir "$SHARED_TMP/nested" "$SHARED_TMP/locked"
  printf 'dummy-secret\n' >"$SHARED_TMP/locked/private.key"
  chmod 000 "$SHARED_TMP/locked"
  local path
  for path in .env nested/.env private.key certificate.pem credentials.json secrets.json; do
    printf 'dummy-secret\n' >"$SHARED_TMP/$path"
  done

  for path in .env nested/.env private.key certificate.pem credentials.json secrets.json; do
    run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- cat "$SHARED_TMP/$path"
    [ "$status" -ne 0 ]
    [[ "$output" != *dummy-secret* ]]

    run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- \
      sh -c 'printf overwritten >"$1"' _ "$SHARED_TMP/$path"
    [ "$status" -ne 0 ]
    [ "$(cat "$SHARED_TMP/$path")" = dummy-secret ]
  done

  for path in .envrc .env.example; do
    printf 'public\n' >"$SHARED_TMP/$path"
    run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- \
      sh -c 'set -eu; test "$(cat "$1")" = public; printf updated >"$1"' _ "$SHARED_TMP/$path"
    [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
    [ "$status" -eq 0 ]
    [ "$(cat "$SHARED_TMP/$path")" = updated ]
  done

  run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
    codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- chmod 700 "$SHARED_TMP/locked"
  [ "$status" -ne 0 ]
}
