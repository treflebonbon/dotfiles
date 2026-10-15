#!/usr/bin/env bats

setup_file() {
  if [ ! -e /tmp/codex ] && [ ! -L /tmp/codex ]; then
    mkdir -m 700 /tmp/codex
  fi
  [ -d /tmp/codex ] && [ ! -L /tmp/codex ] && [ -O /tmp/codex ]
}

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHARED_TMP="$(mktemp -d /tmp/codex/test.XXXXXX)"
  FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
  WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  SESSION_TMP="$BATS_TEST_TMPDIR/session-tmp"
  mkdir -p "$FIXTURE_HOME/.codex" "$WORKSPACE" "$SESSION_TMP"
  chezmoi --source "$PROJECT_ROOT" execute-template \
    -f "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$FIXTURE_HOME/.codex/config.toml"
}

teardown() {
  rm -rf -- "$SHARED_TMP" "${OUTSIDE_TMP:-$SHARED_TMP}"
}

@test "Codex shares /tmp/codex outside its session TMPDIR and denies other /tmp files" {
  OUTSIDE_TMP="$(mktemp -d /tmp/codex-outside.XXXXXX)"
  printf 'outside-public\n' >"$OUTSIDE_TMP/public.txt"
  printf 'original\n' >"$SHARED_TMP/shared.txt"

  run env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" TMPDIR="$SESSION_TMP" \
    codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- sh -c '
      set -eu
      test "$(cat "$1/shared.txt")" = original
      if cat "$2/public.txt" 2>/dev/null; then exit 1; fi
      if (printf overwritten >"$2/public.txt") 2>/dev/null; then exit 1; fi
      printf "updated\n" >"$1/shared.txt"
      printf "created\n" >"$1/new.txt"
      test "$(cat "$1/new.txt")" = created
      rm "$1/new.txt"
      test ! -e "$1/new.txt"
    ' _ "$SHARED_TMP" "$OUTSIDE_TMP"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$SHARED_TMP/shared.txt")" = updated ]
  [ ! -e "$SHARED_TMP/new.txt" ]
  [ "$(cat "$OUTSIDE_TMP/public.txt")" = outside-public ]
}

@test "Codex protects sensitive /tmp/codex filenames while public examples remain usable" {
  mkdir "$SHARED_TMP/nested"
  local path
  local paths=(
    .env .env.local .envrc.local .env.example.local .environment
    nested/.env private.key certificate.pem credentials.json secrets.json
  )
  for path in "${paths[@]}"; do
    printf 'dummy-secret\n' >"$SHARED_TMP/$path"
  done

  for path in "${paths[@]}"; do
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
}

session_start_command() {
  python3 - "$PROJECT_ROOT/private_dot_config/codex/hooks.json" "$1" <<'PYHOOK'
import json
import sys
from pathlib import Path
hooks = json.loads(Path(sys.argv[1]).read_text())
command = hooks["hooks"]["SessionStart"][0]["hooks"][0]["command"]
print(command.replace("/tmp/codex", sys.argv[2]))
PYHOOK
}

@test "Codex SessionStart creates a private shared directory and preserves existing files" {
  local shared="$BATS_TEST_TMPDIR/shared"
  local command
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [ -d "$shared" ]
  [ -z "$output" ]
  python3 - "$shared" <<'PYMODE'
import stat
import sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o700
PYMODE
  printf kept >"$shared/public.txt"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$shared/public.txt")" = kept ]
}

@test "Codex SessionStart stops for a symlink or file at the shared directory path" {
  local target="$BATS_TEST_TMPDIR/target"
  local shared="$BATS_TEST_TMPDIR/shared"
  local command
  mkdir "$target"
  chmod 755 "$target"
  ln -s "$target" "$shared"
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue":false'* ]]
  [ -L "$shared" ]
  python3 - "$target" <<'PYMODE'
import stat
import sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o755
PYMODE
  shared="$BATS_TEST_TMPDIR/file"
  printf kept >"$shared"
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue":false'* ]]
  [ "$(cat "$shared")" = kept ]
}
