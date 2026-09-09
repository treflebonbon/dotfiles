#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/bin" "$FIXTURE/home"
  git init -q "$FIXTURE/repo"
  git -C "$FIXTURE/repo" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm 'test: initialize repository'
  git -C "$FIXTURE/repo" worktree add -qb task "$FIXTURE/worktree"
  touch "$FIXTURE/worktree/flake.nix"
  cat >"$FIXTURE/bin/nix" <<'EOF'
#!/bin/sh
printf 'export PROJECT_257=prepared\n'
EOF
  chmod +x "$FIXTURE/bin/nix"
}

with_env() {
  env HOME="$FIXTURE/home" XDG_STATE_HOME="$FIXTURE/state" PATH="$FIXTURE/bin:$PATH" \
    bash -c 'cd "$1"; shift; exec "$@"' _ "$FIXTURE/worktree" "$CLI" with-env -- "$@"
}

@test "with-env prepares the devShell before injecting dotenv and preserves arguments and exit status" {
  printf 'DUMMY_257=from-dotenv\n' >"$FIXTURE/worktree/.env"
  printf 'touch envrc-was-read\n' >"$FIXTURE/worktree/.envrc"

  run with_env bash -c 'printf "%s/%s/<%s>/<%s>\n" "$PROJECT_257" "$DUMMY_257" "$1" "$2"; exit 23' _ 'two words' ''

  [ "$status" -eq 23 ]
  [[ "$output" == *'prepared/from-dotenv/<two words>/<>'* ]]
  [ ! -e "$FIXTURE/worktree/envrc-was-read" ]
  [ -z "${DUMMY_257+x}" ]
}

@test "dotenv parsing preserves values, expands variables with caller precedence, and never executes shell text" {
  cat >"$FIXTURE/worktree/.env" <<'EOF'
EMPTY=
SINGLE='two words'
MULTI="first
second"
OVERRIDE=dotenv
EXPANDED=${OVERRIDE}/${SINGLE}/${MISSING:-fallback}
LITERAL=$OVERRIDE
COMMAND=$(touch must-not-run)
BARE
EOF
  export OVERRIDE=caller
  run with_env python3 -c '
import os, subprocess
assert os.environ["EMPTY"] == ""
assert os.environ["SINGLE"] == "two words"
assert os.environ["MULTI"] == "first\nsecond"
assert os.environ["OVERRIDE"] == "caller"
assert os.environ["EXPANDED"] == "caller/two words/fallback"
assert os.environ["LITERAL"] == "$OVERRIDE"
assert os.environ["COMMAND"] == "$(touch must-not-run)"
assert "BARE" not in os.environ
subprocess.run(["sh", "-c", "test \"$EMPTY/$SINGLE\" = \"/two words\""], check=True)
'
  [ "$status" -eq 0 ]
  [ ! -e "$FIXTURE/worktree/must-not-run" ]
}

@test "missing dotenv never searches parents or other worktrees and a subdirectory uses only its Git root" {
  printf 'DUMMY_257=parent\n' >"$FIXTURE/.env"
  printf 'DUMMY_257=main\n' >"$FIXTURE/repo/.env"
  mkdir "$FIXTURE/worktree/sub"
  printf 'DUMMY_257=subdirectory\n' >"$FIXTURE/worktree/sub/.env"
  run with_env sh -c 'test "${DUMMY_257-unset}" = unset'
  [ "$status" -eq 0 ]
  printf 'DUMMY_257=root\n' >"$FIXTURE/worktree/.env"
  run --separate-stderr env HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" \
    bash -c 'cd "$1/sub"; exec "$2" with-env -- printenv DUMMY_257 PWD' \
    _ "$FIXTURE/worktree" "$CLI"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = root ]
  [ "${lines[1]}" = "$FIXTURE/worktree/sub" ]
}

@test "invalid dotenv and unreadable existing files stop before the command without printing secret text" {
  local invalid
  for invalid in 'GOOD=before
INVALID="dummy' 'touch dummy' "'BAD=KEY'=dummy"; do
    printf '%s\n' "$invalid" >"$FIXTURE/worktree/.env"
    run with_env touch launched
    [ "$status" -ne 0 ]
    [ ! -e "$FIXTURE/worktree/launched" ]
    [[ "$output" == *'invalid root .env'* && "$output" != *dummy* ]]
  done
  printf 'DUMMY_257=unreadable\n' >"$FIXTURE/worktree/.env"
  chmod 000 "$FIXTURE/worktree/.env"
  run with_env touch launched
  chmod 600 "$FIXTURE/worktree/.env"
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/worktree/launched" ]
  [[ "$output" == *'cannot read root .env'* ]]
}

@test "dotenv rejects external and dangling symlinks, directories and FIFOs but accepts an internal file link" {
  local target
  mkdir "$FIXTURE/worktree/sub"
  printf 'DUMMY_257=internal\n' >"$FIXTURE/worktree/sub/values"
  printf 'DUMMY_257=external\n' >"$FIXTURE/external"
  for target in "$FIXTURE/external" ../repo/.env missing .; do
    ln -s "$target" "$FIXTURE/worktree/.env"
    run with_env touch launched
    mv "$FIXTURE/worktree/.env" "$FIXTURE/rejected-link"
    [ "$status" -ne 0 ]
    [ ! -e "$FIXTURE/worktree/launched" ]
  done
  mkdir "$FIXTURE/worktree/.env"
  run with_env touch launched
  mv "$FIXTURE/worktree/.env" "$FIXTURE/directory"
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/worktree/launched" ]
  mkfifo "$FIXTURE/worktree/.env"
  run with_env touch launched
  mv "$FIXTURE/worktree/.env" "$FIXTURE/fifo"
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/worktree/launched" ]
  ln -s sub/values "$FIXTURE/worktree/.env"
  run with_env sh -c 'test "$DUMMY_257" = internal'
  [ "$status" -eq 0 ]
}

@test "Nix and shellHook preparation failures stop the formal entry before launching the command" {
  printf '#!/bin/sh\nexit 41\n' >"$FIXTURE/bin/nix"
  run with_env touch launched
  [ "$status" -ne 0 ]
  [[ "$output" == *'Nix preparation failed (41)'* ]]
  [ ! -e "$FIXTURE/worktree/launched" ]
  cat >"$FIXTURE/bin/nix" <<'EOF'
#!/bin/sh
printf 'export PARTIAL_257=wrong\nexit 42\n'
EOF
  run with_env touch launched
  [ "$status" -ne 0 ]
  [[ "$output" == *'shellHook preparation failed (42)'* ]]
  [ ! -e "$FIXTURE/worktree/launched" ]
}

@test "with-env selects this root's WSL or explicit output despite inherited direnv selection" {
  cat >"$FIXTURE/bin/nix" <<EOF
#!/bin/sh
printf '%s\\n' "\$@" >'$FIXTURE/selection'
printf 'export PATH="/project/bin:\$PATH"\n'
EOF
  touch "$FIXTURE/worktree/.wsl-browser-free"
  export WSL_DISTRO_NAME=fixture DIRENV_ROOT="$FIXTURE/repo" IN_NIX_SHELL=impure
  run with_env sh -c 'case "$PATH" in /project/bin:*) exit 0;; *) exit 1;; esac'
  [ "$status" -eq 0 ]
  [[ "$(tail -1 "$FIXTURE/selection")" == "git+file://$FIXTURE/worktree#wsl" ]]
  export DEVSHELL_ENV_OUTPUT=custom
  run with_env true
  [ "$status" -eq 0 ]
  [[ "$(tail -1 "$FIXTURE/selection")" == "git+file://$FIXTURE/worktree#custom" ]]
}

@test "public Nix app injects only at runtime and keeps dummy values out of Nix outputs and caches" {
  [ "${WITH_ENV_REAL_NIX:-0}" = 1 ] || skip "opt in with WITH_ENV_REAL_NIX=1; requires real Nix and nixpkgs"
  local nixpkgs system app input_source dotenv_dummy inherited_dummy
  nixpkgs="$(nix eval --offline --impure --raw --expr "(builtins.getFlake (toString $PROJECT_ROOT)).inputs.nixpkgs.outPath")"
  system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  cat >"$FIXTURE/worktree/flake.nix" <<EOF
{
  inputs.nixpkgs.url = "path:$nixpkgs";
  outputs = { nixpkgs, ... }: {
    devShells.$system.default = let pkgs = import nixpkgs { system = "$system"; }; in pkgs.mkShell {
      packages = [ pkgs.hello ];
      PROJECT_257 = "real-nix";
      shellHook = ''
        test -z "''\${DOTENV_257+x}"
        test -z "''\${INHERITED_257+x}"
        export HOOK_257=real-hook
      '';
    };
  };
}
EOF
  git -C "$FIXTURE/worktree" add flake.nix
  dotenv_dummy="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  inherited_dummy="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  printf 'DOTENV_257=%s\n' "$dotenv_dummy" >"$FIXTURE/worktree/.env"
  printf 'touch envrc-was-read\n' >"$FIXTURE/worktree/.envrc"
  cat >"$FIXTURE/observer.py" <<'EOF'
import os
from pathlib import Path
import subprocess
import sys

subprocess.run(["hello"], check=True)
assert os.environ["PROJECT_257"] == "real-nix"
assert os.environ["HOOK_257"] == "real-hook"
assert os.environ["DOTENV_257"] == sys.argv[1]
assert os.environ["INHERITED_257"] == sys.argv[2]
assert not Path("envrc-was-read").exists()
subprocess.run(["sh", "-c", 'test "$DOTENV_257" = "$1"', "_", sys.argv[1]], check=True)
sys.exit(23)
EOF
  export INHERITED_257="$inherited_dummy" XDG_CACHE_HOME="$FIXTURE/cache"
  run env HOME="$FIXTURE/home" bash -c 'cd "$1"; shift; exec nix run --no-write-lock-file "$1#with-env" -- python3 "$2" "$3" "$4"' \
    _ "$FIXTURE/worktree" "$PROJECT_ROOT" "$FIXTURE/observer.py" "$dotenv_dummy" "$inherited_dummy"
  [ "$status" -eq 23 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 23 ]
  [[ "$output" == *'Hello, world!'* ]]
  nix print-dev-env --no-write-lock-file "$FIXTURE/worktree" >"$FIXTURE/nix-output"
  nix derivation show "$FIXTURE/worktree#devShells.$system.default" >"$FIXTURE/derivation.json"
  app="$(nix eval --raw "$PROJECT_ROOT#apps.$system.with-env.program")"
  input_source="$(nix flake metadata --no-write-lock-file --json "$FIXTURE/worktree" | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
  [ ! -e "$input_source/.env" ]
  ! rg -a -q -F -e "$dotenv_dummy" -e "$inherited_dummy" \
    "$FIXTURE/nix-output" "$FIXTURE/derivation.json" "$FIXTURE/cache" "$FIXTURE/home" "${app%/bin/with-env}" "$input_source"
}
