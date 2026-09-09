#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env"
  ADAPTER="$PROJECT_ROOT/private_dot_local/bin/executable_codex-worktree"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/bin" "$FIXTURE/home"
  git init -q "$FIXTURE/repo"
  git -C "$FIXTURE/repo" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm 'test: initialize repository'
  git -C "$FIXTURE/repo" worktree add -qb task "$FIXTURE/worktree"
  ln -s "$CLI" "$FIXTURE/bin/devshell-env"
}

cli() {
  env HOME="$FIXTURE/home" XDG_STATE_HOME="$FIXTURE/state" \
    PATH="$FIXTURE/bin:$PATH" "$CLI" "$@"
}

adapter() {
  env HOME="$FIXTURE/home" XDG_STATE_HOME="$FIXTURE/state" \
    PATH="$FIXTURE/bin:$PATH" bash -c 'cd "$1"; shift; exec "$@"' \
    _ "$FIXTURE/worktree" "$ADAPTER" "$@"
}

install_runtime_fixture() {
  cat >"$FIXTURE/bin/nix" <<EOF
#!/bin/bash
printf '%s\\n' "\$@" >> '$FIXTURE/nix-calls'
cat '$FIXTURE/nix-env'
printf '\\neval "\${shellHook:-}"\\n'
EOF
  cat >"$FIXTURE/nix-env" <<EOF
export PATH='$FIXTURE/tools:/path-not-set'
export PROJECT_255=from-flake
shellHook='export HOOK_255=from-hook'
EOF
  mkdir -p "$FIXTURE/tools"
  cat >"$FIXTURE/tools/project-tool" <<'EOF'
#!/bin/bash
printf 'tool=%s/%s\n' "$PROJECT_255" "$HOOK_255"
EOF
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
project-tool
printf 'arg=<%s>\n' "$@"
exit 23
EOF
  chmod +x "$FIXTURE/bin/nix" "$FIXTURE/bin/codex" "$FIXTURE/tools/project-tool"
  touch "$FIXTURE/worktree/flake.nix"
}

@test "trusted raw Codex receives devShell tools and hook variables with unchanged argv and exit code" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"

  run adapter --model 'model with spaces' 'prompt with spaces'

  [ "$status" -eq 23 ]
  [[ "$output" == *"tool=from-flake/from-hook"* ]]
  [[ "$output" == *"arg=<$FIXTURE/worktree>"* ]]
  [[ "$output" == *'arg=<default_permissions="dotfiles-secure">'* ]]
  [[ "$output" == *'arg=<model with spaces>'* ]]
  [[ "$output" == *'arg=<prompt with spaces>'* ]]
  [ -f "$FIXTURE/nix-calls" ]
}

@test "trust follows a repository's linked worktrees and untrust revokes it" {
  run cli status "$FIXTURE/worktree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"untrusted"* ]]

  run cli trust "$FIXTURE/repo"
  [ "$status" -eq 0 ]
  run cli status "$FIXTURE/worktree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trusted"* && "$output" != *"untrusted"* ]]

  run cli untrust "$FIXTURE/worktree"
  [ "$status" -eq 0 ]
  run cli status "$FIXTURE/repo"
  [[ "$output" == *"untrusted"* ]]
  [ -z "$(git -C "$FIXTURE/repo" status --porcelain)" ]
  [ -z "$(git -C "$FIXTURE/worktree" status --porcelain)" ]
}

@test "untrusted, revoked and flake-free worktrees launch for investigation without invoking Nix" {
  install_runtime_fixture
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
printf 'launched PROJECT_255=%s\n' "${PROJECT_255-unset}"
EOF
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"untrusted"* && "$output" == *"launched PROJECT_255=unset"* ]]
  [ ! -e "$FIXTURE/nix-calls" ]
  cli trust "$FIXTURE/repo"
  cli untrust "$FIXTURE/worktree"
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"untrusted"* ]]
  [ ! -e "$FIXTURE/nix-calls" ]
  cli trust "$FIXTURE/repo"
  mv "$FIXTURE/worktree/flake.nix" "$FIXTURE/worktree/absent.nix"
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"no flake.nix"* && "$output" == *"launched PROJECT_255=unset"* ]]
  [ ! -e "$FIXTURE/nix-calls" ]
}

@test "trust rejects forged membership, symlink pointers and unresolved metadata but accepts physical aliases" {
  cli trust "$FIXTURE/repo"
  ln -s "$FIXTURE/worktree" "$FIXTURE/alias"
  run cli status "$FIXTURE/alias"
  [ "$status" -eq 0 ]
  [[ "$output" != *"untrusted"* ]]
  mkdir "$FIXTURE/forged"
  cp "$FIXTURE/worktree/.git" "$FIXTURE/forged/.git"
  run cli status "$FIXTURE/forged"
  [ "$status" -ne 0 ]
  mv "$FIXTURE/forged/.git" "$FIXTURE/saved-pointer"
  ln -s "$FIXTURE/worktree/.git" "$FIXTURE/forged/.git"
  run cli trust "$FIXTURE/forged"
  [ "$status" -ne 0 ]
  mv "$FIXTURE/repo/.git/worktrees" "$FIXTURE/repo/.git/unresolved"
  run cli status "$FIXTURE/worktree"
  [ "$status" -ne 0 ]
}

@test "another clone and a replaced common directory do not inherit registration" {
  cli trust "$FIXTURE/repo"
  git clone -q "$FIXTURE/repo" "$FIXTURE/clone"
  run cli status "$FIXTURE/clone"
  [[ "$output" == *"untrusted"* ]]
  mv "$FIXTURE/repo/.git" "$FIXTURE/old-git"
  cp -a "$FIXTURE/old-git" "$FIXTURE/repo/.git"
  run cli status "$FIXTURE/worktree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"untrusted"* ]]
}

@test "trust refuses to store registration inside a repository" {
  run env XDG_STATE_HOME="$FIXTURE/worktree/state" "$CLI" trust "$FIXTURE/worktree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside repositories"* ]]
  [ ! -e "$FIXTURE/worktree/state" ]
}

@test "Nix and shellHook failures discard partial environment and retain the investigation launch" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
printf 'launched PROJECT_255=%s inherited=%s\n' "${PROJECT_255-unset}" "$ORDINARY_255"
EOF
  printf '#!/bin/bash\nprintf "fixture Nix failure" >&2\nexit 7\n' >"$FIXTURE/bin/nix"
  export ORDINARY_255=kept
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nix preparation failed (7)"* ]]
  [[ "$output" == *"launched PROJECT_255=unset inherited=kept"* ]]
  install_runtime_fixture
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
printf 'launched PROJECT_255=%s inherited=%s\n' "${PROJECT_255-unset}" "$ORDINARY_255"
EOF
  printf '\nshellHook="export PARTIAL_255=discard; false"\n' >>"$FIXTURE/nix-env"
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"shellHook preparation failed"* ]]
  [[ "$output" == *"launched PROJECT_255=unset inherited=kept"* ]]
}

@test "Nix initialization cannot replace the executable, working root or permission and Git boundaries" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  cat >"$FIXTURE/tools/codex" <<'EOF'
#!/bin/bash
printf 'shadow codex launched\n'
EOF
  chmod +x "$FIXTURE/tools/codex"
  cat >>"$FIXTURE/nix-env" <<EOF
shellHook='cd /; export HOME=/wrong CODEX_HOME=/wrong CODEX_PERMISSION_PROFILE=unrestricted XDG_CONFIG_HOME=/wrong GIT_DIR=/wrong GIT_COMMON_DIR=/wrong GIT_WORK_TREE=/wrong TMPDIR=/wrong; export PROJECT_255=from-hook'
EOF
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
printf 'root=%s home=%s codex-home=%s profile=%s xdg=%s git=%s tmp=%s\n' "$PWD" "$HOME" "$CODEX_HOME" "${CODEX_PERMISSION_PROFILE-unset}" "$XDG_CONFIG_HOME" "${GIT_DIR-unset}/${GIT_COMMON_DIR-unset}/${GIT_WORK_TREE-unset}" "$TMPDIR"
project-tool
printf 'arg=<%s>\n' "$@"
EOF
  export CODEX_HOME="$FIXTURE/codex" XDG_CONFIG_HOME="$FIXTURE/config"
  export GIT_DIR="$FIXTURE/repo/.git" GIT_COMMON_DIR="$FIXTURE/repo/.git" GIT_WORK_TREE="$FIXTURE/repo"
  export CODEX_PERMISSION_PROFILE=unrestricted
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" != *"shadow codex"* ]]
  [[ "$output" == *"root=$FIXTURE/worktree home=$FIXTURE/home codex-home=$FIXTURE/codex profile=unset xdg=$FIXTURE/config git=unset/unset/unset tmp=/tmp"* ]]
  [[ "$output" == *"tool=from-hook/"* ]]
  [[ "$output" == *"arg=<permissions.dotfiles-secure.filesystem={\"$FIXTURE/repo/.git/worktrees/worktree\"=\"write\",\"$FIXTURE/repo/.git\"=\"write\"}>"* ]]
}

@test "WSL selection uses the validated root, respects explicit output and preserves inherited tools" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  mkdir "$FIXTURE/worktree/sub"
  touch "$FIXTURE/worktree/.wsl-browser-free"
  export WSL_DISTRO_NAME=fixture DIRENV_ROOT="$FIXTURE/repo"
  export IN_NIX_SHELL=impure NIX_BUILD_TOP=/old-direnv-root
  run adapter
  [ "$status" -eq 23 ]
  [[ "$output" == *"tool=from-flake/from-hook"* ]]
  [ "$(tail -n 1 "$FIXTURE/nix-calls")" = "git+file://$FIXTURE/worktree#wsl" ]
  export DEVSHELL_ENV_OUTPUT=custom
  run adapter
  [ "$status" -eq 23 ]
  [ "$(tail -n 1 "$FIXTURE/nix-calls")" = "git+file://$FIXTURE/worktree#custom" ]
  unset DEVSHELL_ENV_OUTPUT WSL_DISTRO_NAME
  mv "$FIXTURE/worktree/.wsl-browser-free" "$FIXTURE/worktree/inactive-marker"
  run adapter
  [ "$(tail -n 1 "$FIXTURE/nix-calls")" = "git+file://$FIXTURE/worktree#default" ]
}

@test "one launch runs shellHook once and a restart reflects flake changes without reading envrc" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  printf 'touch "%s/envrc-read"\n' "$FIXTURE" >"$FIXTURE/worktree/.envrc"
  printf '\nshellHook=\x27printf "run\\n" >> "%s/hook-calls"; export HOOK_255=first\x27\n' "$FIXTURE" >>"$FIXTURE/nix-env"
  run adapter
  [ "$status" -eq 23 ]
  [[ "$output" == *"tool=from-flake/first"* ]]
  [ "$(wc -l <"$FIXTURE/hook-calls")" -eq 1 ]
  printf '\nshellHook="export HOOK_255=edited"\n' >>"$FIXTURE/nix-env"
  run adapter
  [ "$status" -eq 23 ]
  [[ "$output" == *"tool=from-flake/edited"* ]]
  [ ! -e "$FIXTURE/envrc-read" ]
}

@test "inherited secrets never enter Nix or shellHook snapshots while the child keeps its inherited environment" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  cat >"$FIXTURE/bin/nix" <<EOF
#!/bin/bash
/usr/bin/env > '$FIXTURE/nix-snapshot'
cat '$FIXTURE/nix-env'
printf '\\neval "\${shellHook:-}"\\n'
EOF
  cat >>"$FIXTURE/nix-env" <<EOF
shellHook='/usr/bin/env > "$FIXTURE/hook-snapshot"; export DERIVED_255="prefix-\${DUMMY_SECRET_255-unset}"'
EOF
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
if [ "$DUMMY_SECRET_255" = sentinel-inherited-255 ]; then printf 'inherited secret retained\n'; fi
printf 'derived=%s\n' "$DERIVED_255"
EOF
  printf 'DUMMY_DOTENV_255=sentinel-dotenv-255\n' >"$FIXTURE/worktree/.env"
  export DUMMY_SECRET_255=sentinel-inherited-255
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"inherited secret retained"* && "$output" == *"derived=prefix-unset"* ]]
  [[ "$output" != *"sentinel-"* ]]
  ! rg -q 'sentinel-inherited-255|sentinel-dotenv-255' "$FIXTURE/nix-snapshot" "$FIXTURE/hook-snapshot" "$FIXTURE/state" "$FIXTURE/home"
}

@test "metadata changed by initialization rejects launch instead of falling back to investigation" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  cat >>"$FIXTURE/nix-env" <<EOF
shellHook='printf "/missing\\n" > "$FIXTURE/repo/.git/worktrees/worktree/gitdir"'
EOF
  cat >"$FIXTURE/bin/codex" <<EOF
#!/bin/bash
touch '$FIXTURE/launched'
EOF
  run adapter
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/launched" ]
  [[ "$output" == *"codex-worktree:"* ]]
}

@test "invalid launch arguments are rejected before a trusted flake is evaluated" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  run adapter --config 'default_permissions="unrestricted"'
  [ "$status" -ne 0 ]
  [ ! -e "$FIXTURE/nix-calls" ]
}

@test "devShell data search paths reach the child while runtime state directories stay inherited" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  cat >>"$FIXTURE/nix-env" <<EOF
export XDG_DATA_DIRS='$FIXTURE/tools/share'
export XDG_STATE_HOME=/wrong
EOF
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
printf 'data=%s state=%s\n' "$XDG_DATA_DIRS" "$XDG_STATE_HOME"
EOF
  run adapter
  [ "$status" -eq 0 ]
  [[ "$output" == *"data=$FIXTURE/tools/share state=$FIXTURE/state"* ]]
}

@test "a relative launcher PATH cannot change the selected Codex when normalizing a subdirectory to its root" {
  install_runtime_fixture
  cli trust "$FIXTURE/repo"
  mkdir "$FIXTURE/worktree/sub"
  cat >"$FIXTURE/worktree/sub/codex" <<'EOF'
#!/bin/bash
printf 'selected caller executable\n'
EOF
  cat >"$FIXTURE/worktree/codex" <<'EOF'
#!/bin/bash
printf 'wrong root executable\n'
EOF
  chmod +x "$FIXTURE/worktree/sub/codex" "$FIXTURE/worktree/codex"
  run env HOME="$FIXTURE/home" XDG_STATE_HOME="$FIXTURE/state" \
    PATH=".:$FIXTURE/bin:$PATH" bash -c 'cd "$1"; exec "$2"' \
    _ "$FIXTURE/worktree/sub" "$ADAPTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"selected caller executable"* ]]
  [[ "$output" != *"wrong root executable"* ]]
}

@test "real Nix prepares the worktree tool and runs shellHook once without saving inherited secrets" {
  [ "${DEVSHELL_ENV_REAL_NIX:-0}" = 1 ] || skip "opt in with DEVSHELL_ENV_REAL_NIX=1; requires real Nix and cached nixpkgs"
  local nixpkgs system
  nixpkgs="$(nix eval --offline --impure --raw --expr "(builtins.getFlake (toString $PROJECT_ROOT)).inputs.nixpkgs.outPath")"
  system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  cat >"$FIXTURE/worktree/flake.nix" <<EOF
{
  inputs.nixpkgs.url = "path:$nixpkgs";
  outputs = { nixpkgs, ... }: {
    devShells.$system.default = let pkgs = import nixpkgs { system = "$system"; }; in pkgs.mkShell {
      packages = [ pkgs.hello ];
      PROJECT_255 = "real-nix";
      shellHook = ''
        printf 'run\\n' >> hook-calls
        export HOOK_255=real-hook
        export DERIVED_255="prefix-''\${DUMMY_SECRET_255-unset}"
      '';
    };
  };
}
EOF
  # Nix's Git source includes tracked files; dotenv remains untracked and is never imported.
  git -C "$FIXTURE/worktree" add flake.nix
  printf 'dotenv=sentinel-dotenv-255\n' >"$FIXTURE/worktree/.env"
  printf 'touch envrc-was-read\n' >"$FIXTURE/worktree/.envrc"
  cat >"$FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
set -eu
hello
[ "$PROJECT_255/$HOOK_255/$DERIVED_255" = 'real-nix/real-hook/prefix-unset' ]
[ "$DUMMY_SECRET_255" = sentinel-inherited-255 ]
[ "$(wc -l < hook-calls)" -eq 1 ]
[ ! -e envrc-was-read ]
[ ! -e flake.lock ]
printf 'real devShell passed\n'
EOF
  chmod +x "$FIXTURE/bin/codex"
  cli trust "$FIXTURE/repo"
  export DUMMY_SECRET_255=sentinel-inherited-255 XDG_CACHE_HOME="$FIXTURE/cache"
  run adapter
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [[ "$output" == *"real devShell passed"* ]]
  ! rg -a -q 'sentinel-inherited-255|sentinel-dotenv-255' "$FIXTURE/state" "$FIXTURE/cache" "$FIXTURE/home"
}
