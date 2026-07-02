#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  export TEST_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$TEST_HOME/.nix-profile/share/nix-direnv"
  : >"$TEST_LOG"
}

write_fake_nix_direnv() {
  local flake_status="${1:-0}"
  local nix_status="${2:-0}"

  cat >"$TEST_HOME/.nix-profile/share/nix-direnv/direnvrc" <<EOF
use_flake() {
  printf 'use_flake:%s\n' "\$*" >>"\$TEST_LOG"
  return $flake_status
}

use_nix() {
  printf 'use_nix:%s\n' "\$*" >>"\$TEST_LOG"
  return $nix_status
}
EOF
}

@test "use_flake normalizes long nix-shell TMPDIR after original function succeeds" {
  write_fake_nix_direnv

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; export TMPDIR="/tmp/nix-shell.abc/nix-shell.def/nix-shell.ghi"; use_flake . --impure; printf "%s" "$TMPDIR"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp" ]
  grep -q 'use_flake:. --impure' "$TEST_LOG"
}

@test "use_nix normalizes long nix-shell TMPDIR after original function succeeds" {
  write_fake_nix_direnv

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; export TMPDIR="/tmp/nix-shell.abc/nix-shell.def"; use_nix shell.nix -A dev; printf "%s" "$TMPDIR"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp" ]
  grep -q 'use_nix:shell.nix -A dev' "$TEST_LOG"
}

@test "wrappers preserve non nix-shell TMPDIR values" {
  write_fake_nix_direnv

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; export TMPDIR="/tmp/project-cache"; use_flake .; printf "%s" "$TMPDIR"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/project-cache" ]
}

@test "direnvrc can be sourced repeatedly without losing TMPDIR normalization" {
  write_fake_nix_direnv

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; source "$1"; export TMPDIR="/tmp/nix-shell.abc/nix-shell.def"; use_flake .; printf "%s" "$TMPDIR"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp" ]
  grep -q 'use_flake:.' "$TEST_LOG"
}

@test "use_flake failure returns before TMPDIR normalization" {
  write_fake_nix_direnv 42 0

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; export TMPDIR="/tmp/nix-shell.abc/nix-shell.def"; use_flake .; rc=$?; printf "%s" "$TMPDIR"; exit "$rc"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 42 ]
  [ "$output" = "/tmp/nix-shell.abc/nix-shell.def" ]
  grep -q 'use_flake:.' "$TEST_LOG"
}

@test "use_nix failure returns before TMPDIR normalization" {
  write_fake_nix_direnv 0 37

  run env HOME="$TEST_HOME" TEST_LOG="$TEST_LOG" bash -c 'source "$1"; export TMPDIR="/tmp/nix-shell.abc/nix-shell.def"; use_nix shell.nix; rc=$?; printf "%s" "$TMPDIR"; exit "$rc"' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 37 ]
  [ "$output" = "/tmp/nix-shell.abc/nix-shell.def" ]
  grep -q 'use_nix:shell.nix' "$TEST_LOG"
}

@test "direnvrc can be sourced when nix-direnv direnvrc is absent" {
  rm -f "$TEST_HOME/.nix-profile/share/nix-direnv/direnvrc"

  run env HOME="$TEST_HOME" bash -c 'source "$1"; declare -f use_flake; declare -f use_nix' _ "$PROJECT_ROOT/private_dot_config/direnv/direnvrc"

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
}
