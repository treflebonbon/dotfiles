#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PATH="$TEST_BIN_DIR:$PATH"
  stub_real_cmd find
  stub_real_cmd dirname
  stub_real_cmd stat
  stub_real_cmd rm
  stub_real_cmd mkdir
}

init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
}

@test "codex repo state reports ignored untracked zero-byte .codex files without changing them" {
  local repo="$BATS_TEST_TMPDIR/ghq/github.com/example/ignored"
  init_repo "$repo"
  printf '.codex\n' >"$repo/.gitignore"
  : >"$repo/.codex"

  run "$PROJECT_ROOT/private_dot_local/bin/executable_codex-repo-state" "$BATS_TEST_TMPDIR/ghq"

  assert_success
  assert_output --partial "DRY-RUN fix ignored untracked 0-byte file: $repo/.codex"
  [ -f "$repo/.codex" ]
  [ ! -d "$repo/.codex/environments" ]
}

@test "codex repo state skips tracked .codex files" {
  local repo="$BATS_TEST_TMPDIR/ghq/github.com/example/tracked"
  init_repo "$repo"
  : >"$repo/.codex"
  git -C "$repo" add .codex
  git -C "$repo" -c user.email=test@example.com -c user.name=Test commit -q -m 'test: track codex file'

  run "$PROJECT_ROOT/private_dot_local/bin/executable_codex-repo-state" --apply "$BATS_TEST_TMPDIR/ghq"

  assert_success
  assert_output --partial "SKIP tracked .codex file: $repo/.codex"
  [ -f "$repo/.codex" ]
}

@test "codex repo state warns when .codex is not ignored" {
  local repo="$BATS_TEST_TMPDIR/ghq/github.com/example/unignored"
  init_repo "$repo"
  : >"$repo/.codex"

  run "$PROJECT_ROOT/private_dot_local/bin/executable_codex-repo-state" "$BATS_TEST_TMPDIR/ghq"

  assert_success
  assert_output --partial "DRY-RUN fix unignored untracked 0-byte file: $repo/.codex"
  assert_output --partial "WARN add .codex to .gitignore: $repo"
}

@test "codex repo state repairs untracked zero-byte .codex files when apply is explicit" {
  local repo="$BATS_TEST_TMPDIR/ghq/github.com/example/repair"
  init_repo "$repo"
  printf '.codex\n' >"$repo/.gitignore"
  : >"$repo/.codex"

  run "$PROJECT_ROOT/private_dot_local/bin/executable_codex-repo-state" --apply "$BATS_TEST_TMPDIR/ghq"

  assert_success
  assert_output --partial "FIXED ignored untracked 0-byte file: $repo/.codex"
  [ -d "$repo/.codex/environments" ]
}

@test "codex repo state leaves existing .codex directories alone" {
  local repo="$BATS_TEST_TMPDIR/ghq/github.com/example/directory"
  init_repo "$repo"
  mkdir -p "$repo/.codex/environments"

  run "$PROJECT_ROOT/private_dot_local/bin/executable_codex-repo-state" --apply "$BATS_TEST_TMPDIR/ghq"

  assert_success
  assert_output --partial "OK .codex directory: $repo/.codex"
  [ -d "$repo/.codex/environments" ]
}
