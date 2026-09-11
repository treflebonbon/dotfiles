#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers/raw-codex

teardown() { raw_cleanup; }

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

@test "with-env preserves caller Git settings without exposing them to preparation" {
  cat >"$FIXTURE/bin/nix" <<'EOF'
#!/bin/sh
test -z "${GIT_AUTHOR_NAME+x}${GIT_SSH_COMMAND+x}${GIT_CONFIG_COUNT+x}" || exit 40
printf 'test -z "${GIT_AUTHOR_NAME+x}${GIT_SSH_COMMAND+x}${GIT_CONFIG_COUNT+x}"\n'
printf 'export GIT_AUTHOR_NAME=from-hook\n'
EOF
  printf 'GIT_AUTHOR_NAME=from-dotenv\n' >"$FIXTURE/worktree/.env"
  export GIT_AUTHOR_NAME='Caller Author' GIT_AUTHOR_EMAIL=caller@example.com
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=review.fixture GIT_CONFIG_VALUE_0=caller-config
  export GIT_SSH_COMMAND='ssh -o BatchMode=yes'
  run with_env python3 -c '
import os, subprocess
assert os.environ["GIT_SSH_COMMAND"] == "ssh -o BatchMode=yes"
assert subprocess.check_output(["git", "config", "review.fixture"], text=True).strip() == "caller-config"
assert subprocess.check_output(["git", "var", "GIT_AUTHOR_IDENT"], text=True).startswith("Caller Author <caller@example.com>")
'
  [ "$status" -eq 0 ]
}

@test "with-env discovers the current root independently of inherited Git selectors" {
  printf 'DUMMY_257=current-root\n' >"$FIXTURE/worktree/.env"
  printf 'DUMMY_257=other-root\n' >"$FIXTURE/repo/.env"
  export GIT_DIR="$FIXTURE/repo/.git" GIT_COMMON_DIR="$FIXTURE/repo/.git" GIT_WORK_TREE="$FIXTURE/repo"
  run with_env python3 -c '
import os
assert os.environ["DUMMY_257"] == "current-root"
assert os.environ["GIT_DIR"] == os.environ["GIT_COMMON_DIR"] == os.environ["GIT_WORK_TREE"] + "/.git"
'
  [ "$status" -eq 0 ]
}

@test "with-env accepts separate Git directories with absolute or relative gitfiles" {
  git init -q --separate-git-dir "$FIXTURE/metadata" "$FIXTURE/separate"
  touch "$FIXTURE/separate/flake.nix"
  printf 'DUMMY_257=separate\n' >"$FIXTURE/separate/.env"
  local target
  for target in "$FIXTURE/metadata" ../metadata; do
    printf 'gitdir: %s\n' "$target" >"$FIXTURE/separate/.git"
    run env HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" \
      bash -c 'cd "$1"; shift; exec "$@"' _ "$FIXTURE/separate" "$CLI" with-env -- \
      sh -c 'test "$PROJECT_257/$DUMMY_257" = prepared/separate'
    [ "$status" -eq 0 ]
  done
  run env HOME="$FIXTURE/home" XDG_STATE_HOME="$FIXTURE/state" "$CLI" trust "$FIXTURE/separate"
  [ "$status" -ne 0 ]
  run env PATH="$FIXTURE/bin:$PATH" bash -c 'cd "$1"; exec "$2" codex' _ "$FIXTURE/separate" "$CLI"
  [ "$status" -ne 0 ]
  [[ "$output" == *'not a linked Git worktree'* ]]
}

@test "with-env accepts a submodule and reads only its own root dotenv" {
  git init -q "$FIXTURE/parent"
  git -C "$FIXTURE/parent" -c protocol.file.allow=always submodule add -q "$FIXTURE/repo" child
  touch "$FIXTURE/parent/child/flake.nix"
  printf 'DUMMY_257=parent\n' >"$FIXTURE/parent/.env"
  printf 'DUMMY_257=child\n' >"$FIXTURE/parent/child/.env"
  run env HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" \
    bash -c 'cd "$1"; shift; exec "$@"' _ "$FIXTURE/parent/child" "$CLI" with-env -- \
    sh -c 'test "$PROJECT_257/$DUMMY_257" = prepared/child'
  [ "$status" -eq 0 ]
}

@test "with-env rejects invalid gitfiles and metadata retargeted during preparation" {
  git init -q --separate-git-dir "$FIXTURE/metadata" "$FIXTURE/separate"
  touch "$FIXTURE/separate/flake.nix"
  mv "$FIXTURE/separate/.git" "$FIXTURE/gitfile"
  ln -s "$FIXTURE/gitfile" "$FIXTURE/separate/.git"
  run env PATH="$FIXTURE/bin:$PATH" bash -c 'cd "$1"; exec "$2" with-env -- touch launched' \
    _ "$FIXTURE/separate" "$CLI"
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/separate/launched" ]
  mv "$FIXTURE/separate/.git" "$FIXTURE/rejected-gitfile-link"
  local pointer
  for pointer in 'gitdir: /missing' 'invalid pointer'; do
    printf '%s\n' "$pointer" >"$FIXTURE/separate/.git"
    run env PATH="$FIXTURE/bin:$PATH" bash -c 'cd "$1"; exec "$2" with-env -- touch launched' \
      _ "$FIXTURE/separate" "$CLI"
    [ "$status" -ne 0 ]
    [ ! -e "$FIXTURE/separate/launched" ]
  done
  cp "$FIXTURE/gitfile" "$FIXTURE/separate/.git"
  cat >"$FIXTURE/bin/nix" <<EOF
#!/bin/sh
printf 'printf "gitdir: %s\\\\n" > .git\\n' '$FIXTURE/repo/.git'
EOF
  run env HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" \
    bash -c 'cd "$1"; exec "$2" with-env -- touch launched' _ "$FIXTURE/separate" "$CLI"
  [ "$status" -ne 0 ]
  [[ "$output" == *'changed during preparation'* ]]
  [[ "$output" != *'devshell-env: ready;'* ]]
  [ ! -e "$FIXTURE/separate/launched" ]
}

@test "raw Codex reuses the isolated prepared devShell without injecting host dotenv" {
  raw_fixture
  raw_admit flake.nix task.sh
  run raw_run sandbox -- with-env --prepared -- bash -c 'test "$PUBLIC_VAR/$HOOK_VAR" = normal/ready; test -z "${RAW_DUMMY_SECRET+x}"'
  raw_assert_status 0
  [ "$(wc -l < "$RAW_BASE/work/hook-calls")" -eq 1 ]
}

@test "the normal entry prepares again even when it inherits a prepared context" {
  raw_fixture
  cat > "$RAW_BASE/work/task.sh" <<'SH'
set -eu
printf '{ outputs = _: throw "reprepare required"; }' > flake.nix
with-env -- bash -c 'touch launched'
SH
  raw_admit flake.nix task.sh
  run raw_run sandbox -- bash task.sh
  raw_assert_status 1
  [[ "$output" == *'Nix preparation failed'* ]]
  [ ! -e "$RAW_BASE/work/launched" ]
}

@test "prepared entry refuses to execute without successful adapter preparation" {
  run env -u DEVSHELL_ENV_CONTEXT "$CLI" with-env --prepared -- touch "$FIXTURE/launched"
  [ "$status" -ne 0 ]
  [[ "$output" == *'no prepared devShell'* ]]
  [ ! -e "$FIXTURE/launched" ]
}

@test "with-env rejects a prepared context after root, output, flake or lock changes" {
  raw_fixture
  cat > "$RAW_BASE/work/task.sh" <<'SH'
set -eu
original=$DEVSHELL_ENV_CONTEXT
for change in output flake lock; do
  case "$change" in
    output) export DEVSHELL_ENV_OUTPUT=custom;;
    flake) unset DEVSHELL_ENV_OUTPUT; printf changed >> flake.nix;;
    lock) printf changed > flake.lock;;
  esac
  if with-env --prepared -- touch launched; then exit 1; fi
done
git init -q "$TMPDIR/other"
(cd "$TMPDIR/other"; if with-env --prepared -- true; then exit 1; fi)
printf CONTEXT_REFUSED
SH
  raw_admit flake.nix task.sh
  run raw_run sandbox -- bash task.sh
  raw_assert_status 0
  [[ "$output" == *CONTEXT_REFUSED* && "$output" == *'restart the session'* ]]
  [ ! -e "$RAW_BASE/work/launched" ]
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
        test -z "''\${GIT_AUTHOR_NAME+x}"
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
assert os.environ["GIT_AUTHOR_NAME"] == sys.argv[2]
assert not Path("envrc-was-read").exists()
subprocess.run(["sh", "-c", 'test "$DOTENV_257" = "$1"', "_", sys.argv[1]], check=True)
sys.exit(23)
EOF
  export INHERITED_257="$inherited_dummy" GIT_AUTHOR_NAME="$inherited_dummy" XDG_CACHE_HOME="$FIXTURE/cache"
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

  git init -q --separate-git-dir "$FIXTURE/metadata" "$FIXTURE/separate"
  git init -q "$FIXTURE/parent"
  git -C "$FIXTURE/parent" -c protocol.file.allow=always submodule add -q "$FIXTURE/repo" child
  local directory
  for directory in "$FIXTURE/separate" "$FIXTURE/parent/child"; do
    cp "$FIXTURE/worktree/flake.nix" "$directory/flake.nix"
    cp "$FIXTURE/worktree/.env" "$directory/.env"
    git -C "$directory" add flake.nix
    run env HOME="$FIXTURE/home" bash -c 'cd "$1"; shift; exec nix run --no-write-lock-file "$1#with-env" -- python3 "$2" "$3" "$4"' \
      _ "$directory" "$PROJECT_ROOT" "$FIXTURE/observer.py" "$dotenv_dummy" "$inherited_dummy"
    [ "$status" -eq 23 ] || printf '%s\n' "$output" >&3
    [ "$status" -eq 23 ]
    [[ "$output" == *'Hello, world!'* ]]
  done
}

@test "real raw Codex confines dotenv and Git metadata while executing the public with-env entry" {
  raw_fixture
  cat > "$RAW_BASE/work/task.sh" <<'SH'
set -eu
with-env --prepared -- bash -c 'test -z "${RAW_DUMMY_SECRET+x}"; test -z "$(cat .env 2>/dev/null || true)"; printf public > result.txt; git add result.txt'
if cat ../repo/.env >/dev/null 2>&1; then exit 1; fi
printf RAW_WITH_ENV_OK
SH
  raw_admit flake.nix task.sh
  export RAW_DUMMY_SECRET=dummy-inherited-secret
  run raw_run sandbox -- bash task.sh
  raw_assert_status 0
  [[ "$output" == *RAW_WITH_ENV_OK* ]]
  [ "$(git -C "$RAW_BASE/work" diff --cached --name-only)" = result.txt ]
}


@test "the actual public Nix app package remains secret-free inside the raw runtime" {
  [ "${WITH_ENV_REAL_NIX:-0}" = 1 ] || skip "opt in with WITH_ENV_REAL_NIX=1; builds the public app inside the dedicated store"
  run python3 "$PROJECT_ROOT/tests/helpers/with-env-preflight.py"
  raw_assert_status 0
  [[ "$output" == *'Evidence:'* ]]
}

@test "chezmoi deployed with-env runs under isolated Python without its source checkout" {
  local source="$FIXTURE/source" config="$FIXTURE/chezmoi.yaml"
  mkdir -p "$source/private_dot_local/bin" "$source/private_dot_local/share/devshell-env"
  cp "$CLI" "$source/private_dot_local/bin/executable_devshell-env"
  cp "$PROJECT_ROOT/private_dot_local/share/devshell-env/devshell_environment.py" \
    "$source/private_dot_local/share/devshell-env/"
  cp "$PROJECT_ROOT/.chezmoiignore" "$source/.chezmoiignore"
  mkdir -p "$source/private_dot_local/share/devshell-env/__pycache__"
  printf 'stale bytecode\n' >"$source/private_dot_local/share/devshell-env/__pycache__/stale.pyc"
  printf '{}\n' >"$config"
  env HOME="$FIXTURE/home" chezmoi --source "$source" --destination "$FIXTURE/home" \
    --config "$config" --persistent-state "$FIXTURE/chezmoi-state.boltdb" apply
  [ ! -e "$FIXTURE/home/.local/share/devshell-env/__pycache__/stale.pyc" ]
  mv "$source" "$FIXTURE/retired-source"
  printf 'raise RuntimeError("untrusted import")\n' >"$FIXTURE/worktree/devshell_environment.py"
  run env HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" PYTHONPATH="$FIXTURE/worktree" \
    bash -c 'cd "$1"; exec python3 -I "$2" with-env -- sh -c '\''test "$PROJECT_257" = prepared'\' \
    _ "$FIXTURE/worktree" "$FIXTURE/home/.local/bin/devshell-env"
  [ "$status" -eq 0 ]
}
