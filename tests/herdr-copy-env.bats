#!/usr/bin/env bats

# Each Bats test runs independently; event changes intentionally stay local.
# shellcheck disable=SC2030,SC2031

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MANIFEST="$PROJECT_ROOT/.herdr/herdr-plugin.toml"
  SOURCE_TREE="$BATS_TEST_TMPDIR/source tree"
  WORKTREE="$BATS_TEST_TMPDIR/new worktree"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git init -q -b main "$SOURCE_TREE"
  cp "$PROJECT_ROOT/.gitignore" "$SOURCE_TREE/.gitignore"
  git -C "$SOURCE_TREE" add .gitignore
  git -C "$SOURCE_TREE" -c user.name=Test -c user.email=test@example.invalid \
    commit -qm 'test: seed dummy repository'
  git -C "$SOURCE_TREE" worktree add -q -b test/copy-env "$WORKTREE"
  mkdir -p "$SOURCE_TREE/.herdr"
  export HERDR_PLUGIN_ROOT="$SOURCE_TREE/.herdr"
  export HERDR_PLUGIN_EVENT_JSON
  HERDR_PLUGIN_EVENT_JSON=$(jq -nc --arg source "$SOURCE_TREE" --arg target "$WORKTREE" '
    {event: "worktree.created", data: {
      workspace: {worktree: {repo_root: $source}},
      worktree: {path: $target, is_linked_worktree: true}
    }}
  ')
  export TEST_CWD_RESULT="$BATS_TEST_TMPDIR/cwd"
  printf 'DUMMY_ENV=copy-only\n' >"$SOURCE_TREE/.env"
  printf 'DUMMY_ALIAS=do-not-copy\n' >"$SOURCE_TREE/.env.local"
}

run_copy_env() {
  run python3 - "$MANIFEST" <<'PY'
import subprocess
import sys
import tomllib

with open(sys.argv[1], "rb") as file:
    manifest = tomllib.load(file)
command = next(event["command"] for event in manifest["events"]
               if event["on"] == "worktree.created")
# Observe the final shell cwd after the actual command, keeping its errexit flags.
command[-1] += '\npwd -P > "$TEST_CWD_RESULT"\n'
sys.exit(subprocess.run(command).returncode)
PY
}

@test "Herdr event copies only root .env independently and finishes in the new worktree" {
  run_copy_env

  [ "$status" -eq 0 ]
  cmp "$SOURCE_TREE/.env" "$WORKTREE/.env"
  [ ! -L "$WORKTREE/.env" ]
  [ ! -e "$WORKTREE/.env.local" ]
  [ "$(cat "$TEST_CWD_RESULT")" = "$WORKTREE" ]
  git -C "$WORKTREE" check-ignore -q .env
  [[ "$output" != *copy-only* ]]
  printf 'DUMMY_ENV=changed-target\n' >"$WORKTREE/.env"
  [ "$(cat "$SOURCE_TREE/.env")" = 'DUMMY_ENV=copy-only' ]
}

@test "Herdr event copies for repositories other than the one containing the linked manifest" {
  export HERDR_PLUGIN_ROOT="$BATS_TEST_TMPDIR/other repo/.herdr"
  mkdir -p "$HERDR_PLUGIN_ROOT"

  run_copy_env

  [ "$status" -eq 0 ]
  cmp "$SOURCE_TREE/.env" "$WORKTREE/.env"
}

@test "Herdr event refuses a destination belonging to another repository" {
  local other="$BATS_TEST_TMPDIR/unrelated checkout"
  git init -q -b main "$other"
  cp "$PROJECT_ROOT/.gitignore" "$other/.gitignore"
  git -C "$other" add .gitignore
  git -C "$other" -c user.name=Test -c user.email=test@example.invalid \
    commit -qm 'test: seed unrelated repository'
  git -C "$other" worktree add -q -b test/unrelated "$other-linked"
  HERDR_PLUGIN_EVENT_JSON=$(jq --arg target "$other-linked" '.data.worktree.path = $target' <<<"$HERDR_PLUGIN_EVENT_JSON")

  run_copy_env

  [ "$status" -ne 0 ]
  [ ! -e "$other-linked/.env" ]
}

@test "Herdr event refuses an existing destination .env without changing it" {
  printf 'DUMMY_ENV=existing\n' >"$WORKTREE/.env"

  run_copy_env

  [ "$status" -ne 0 ]
  [ "$(cat "$WORKTREE/.env")" = 'DUMMY_ENV=existing' ]
}

@test "Herdr event refuses a symlink source instead of following it" {
  mv "$SOURCE_TREE/.env" "$BATS_TEST_TMPDIR/external-env"
  ln -s "$BATS_TEST_TMPDIR/external-env" "$SOURCE_TREE/.env"

  run_copy_env

  [ "$status" -ne 0 ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event refuses a destination where .env is not ignored by Git" {
  printf '# no dotenv exclusions\n' >"$WORKTREE/.gitignore"

  run_copy_env

  [ "$status" -ne 0 ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event rejects relative source and destination paths" {
  cd "$BATS_TEST_TMPDIR" || return
  HERDR_PLUGIN_EVENT_JSON=$(jq '.data.workspace.worktree.repo_root = "source tree" | .data.worktree.path = "new worktree"' <<<"$HERDR_PLUGIN_EVENT_JSON")

  run_copy_env

  [ "$status" -ne 0 ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event rejects missing paths and malformed JSON without copying" {
  local original="$HERDR_PLUGIN_EVENT_JSON" field
  for field in '.data.workspace.worktree.repo_root' '.data.worktree.path'; do
    HERDR_PLUGIN_EVENT_JSON=$(jq "del($field)" <<<"$original")
    run_copy_env
    [ "$status" -ne 0 ]
    [ ! -e "$WORKTREE/.env" ]
  done
  HERDR_PLUGIN_EVENT_JSON='not JSON'
  run_copy_env
  [ "$status" -ne 0 ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event requires event JSON but not plugin root" {
  local original="$HERDR_PLUGIN_EVENT_JSON"
  unset HERDR_PLUGIN_EVENT_JSON
  run_copy_env
  [ "$status" -ne 0 ]
  export HERDR_PLUGIN_EVENT_JSON="$original"
  unset HERDR_PLUGIN_ROOT
  run_copy_env
  [ "$status" -eq 0 ]
  cmp "$SOURCE_TREE/.env" "$WORKTREE/.env"
}

@test "Herdr event skips missing .env without falling back to .env.local" {
  mv "$SOURCE_TREE/.env" "$BATS_TEST_TMPDIR/retained-env"

  run_copy_env

  [ "$status" -eq 0 ]
  [ ! -e "$WORKTREE/.env" ]
  [[ "$output" == *'skipped (source .env absent)'* ]]
  [[ "$output" != *do-not-copy* ]]
}

@test "Herdr event refuses dangling symlinks and directories as source .env" {
  mv "$SOURCE_TREE/.env" "$BATS_TEST_TMPDIR/retained-env"
  ln -s "$BATS_TEST_TMPDIR/missing" "$SOURCE_TREE/.env"
  run_copy_env
  [ "$status" -ne 0 ]
  mv "$SOURCE_TREE/.env" "$BATS_TEST_TMPDIR/dangling-link"
  mkdir "$SOURCE_TREE/.env"
  run_copy_env
  [ "$status" -ne 0 ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event refuses a destination symlink and preserves its target" {
  printf 'DUMMY_ENV=external\n' >"$BATS_TEST_TMPDIR/external-env"
  ln -s "$BATS_TEST_TMPDIR/external-env" "$WORKTREE/.env"

  run_copy_env

  [ "$status" -ne 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/external-env")" = 'DUMMY_ENV=external' ]
}

@test "Herdr event preserves copy failure instead of succeeding after cd" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 74\n' >"$BATS_TEST_TMPDIR/bin/cp"
  chmod +x "$BATS_TEST_TMPDIR/bin/cp"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  run_copy_env

  [ "$status" -eq 74 ]
  [ ! -e "$TEST_CWD_RESULT" ]
  [ ! -e "$WORKTREE/.env" ]
}

@test "Herdr event reports a failed final cd" {
  export BASH_ENV="$BATS_TEST_TMPDIR/bash-env" FAILING_CWD="$WORKTREE"
  cat >"$BASH_ENV" <<'SH'
cd() {
  [ "${@: -1}" != "$FAILING_CWD" ] || return 75
  builtin cd "$@"
}
SH

  run_copy_env

  [ "$status" -eq 75 ]
  [ ! -e "$TEST_CWD_RESULT" ]
}

@test "Herdr event creates .env readable and writable only by its owner" {
  chmod 644 "$SOURCE_TREE/.env"

  run_copy_env

  [ "$status" -eq 0 ]
  python3 - "$WORKTREE/.env" <<'PY'
from pathlib import Path
import stat
import sys
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o600
PY
}

@test "repo-local Herdr manifest is excluded from chezmoi home deployment" {
  local os
  for os in linux darwin; do
    run chezmoi managed --source "$PROJECT_ROOT" \
      --cache "$BATS_TEST_TMPDIR/cache" \
      --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
      --override-data "{\"chezmoi\":{\"os\":\"$os\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *'.bashrc'* ]]
    [[ "$output" != *'.herdr'* ]]
  done
}
