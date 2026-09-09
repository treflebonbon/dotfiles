#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$HOME/state"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_ENV_FILE="$HOME/session-env.sh"
  export PATH="$HOME/.local/bin:$PATH"
  unset DEVSHELL_ENV_SESSION DEVSHELL_ENV_OUTPUT
  mkdir -p "$HOME/.local/bin" "$HOME/tools"
  ln -s "$CLI" "$HOME/.local/bin/devshell-env"
  PROJECT="$BATS_TEST_TMPDIR/project"
  git init -q "$PROJECT"
  printf 'fixture\n' >"$PROJECT/flake.nix"
  git -C "$PROJECT" add flake.nix
  git -C "$PROJECT" -c user.name=Test -c user.email=test@example.com commit -qm 'test: fixture'
  cat >"$HOME/.local/bin/nix" <<'EOF'
#!/bin/bash
printf 'init\n' >> "$HOME/initializations"
cat "$PWD/environment.sh"
EOF
  chmod +x "$HOME/.local/bin/nix"
  cat >"$PROJECT/environment.sh" <<'EOF'
export PROJECT_NAME=first
export FROM_HOOK='space and "quotes"'
export PATH="$HOME/tools:$PATH"
EOF
  cat >"$HOME/tools/project-tool" <<'EOF'
#!/bin/bash
printf '%s/%s\n' "$PROJECT_NAME" "$FROM_HOOK"
EOF
  chmod +x "$HOME/tools/project-tool"
}

hook() {
  local event="$1" directory="$2"
  local command
  command="$(jq -r --arg event "$event" '.hooks[$event][0].hooks[0].command' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl")"
  printf '%s' "$directory" >"$HOME/fixture-cwd"
  jq -nc --arg event "$event" --arg cwd "$directory" \
    '{session_id:"fixture-session",hook_event_name:$event,cwd:$cwd,new_cwd:$cwd,source:"startup"}' |
    bash -c "$command"
}

subsequent_bash() {
  jq -nc --arg cwd "$(cat "$HOME/fixture-cwd")" \
    '{session_id:"fixture-session",hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd}' |
    env -u CLAUDE_ENV_FILE "$CLI" claude-hook >"$HOME/last-pretool-output" 2>&1
  env -u CLAUDE_ENV_FILE bash --noprofile --norc -c 'source "$1"; eval "$2"' _ "$CLAUDE_ENV_FILE" "$1"
}

@test "managed SessionStart supplies trusted devShell tools to subsequent Bash only once" {
  "$CLI" trust "$PROJECT"
  run hook SessionStart "$PROJECT"
  [ "$status" -eq 0 ]
  run subsequent_bash 'project-tool; printf "envfile=%s\n" "${CLAUDE_ENV_FILE-unset}"'
  [ "$status" -eq 0 ]
  [ "$output" = $'first/space and "quotes"\nenvfile=unset' ]
  run subsequent_bash project-tool
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/initializations")" -eq 1 ]
}

@test "CwdChanged skips the same Git root and switches linked worktrees without old variables or paths" {
  "$CLI" trust "$PROJECT"
  git -C "$PROJECT" worktree add -qb task "$BATS_TEST_TMPDIR/worktree"
  printf 'export PROJECT_NAME=second\n' >"$BATS_TEST_TMPDIR/worktree/environment.sh"
  mkdir "$PROJECT/subdirectory"
  hook SessionStart "$PROJECT"
  run hook CwdChanged "$PROJECT/subdirectory"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/initializations")" -eq 1 ]
  run hook CwdChanged "$BATS_TEST_TMPDIR/worktree"
  [ "$status" -eq 0 ]
  run subsequent_bash 'printf "%s/%s\n" "$PROJECT_NAME" "${FROM_HOOK-unset}"; command -v project-tool || :'
  [ "$status" -eq 0 ]
  [ "$output" = 'second/unset' ]
  [ "$(wc -l < "$HOME/initializations")" -eq 2 ]
}

@test "switch restores inherited values in memory and preserves another hook's edits" {
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  mkdir "$BATS_TEST_TMPDIR/outside"
  run env PROJECT_NAME=inherited FROM_HOOK=baseline bash --noprofile --norc -c '
    source "$1"
    export FROM_HOOK=other-hook OTHER_HOOK=kept PATH="/other-hook:$PATH"
    jq -nc --arg cwd "$3" "{session_id:\"fixture-session\",hook_event_name:\"CwdChanged\",cwd:\$cwd,new_cwd:\$cwd}" | "$2" claude-hook
    jq -nc --arg cwd "$3" "{session_id:\"fixture-session\",hook_event_name:\"PreToolUse\",tool_name:\"Bash\",cwd:\$cwd}" | env -u CLAUDE_ENV_FILE "$2" claude-hook
    source "$1"
    printf "observed=%s/%s/%s\n" "$PROJECT_NAME" "$FROM_HOOK" "$OTHER_HOOK"
    case "$PATH" in /other-hook:*) ;; *) exit 10;; esac
    command -v project-tool && exit 11
    :
  ' _ "$CLAUDE_ENV_FILE" "$CLI" "$BATS_TEST_TMPDIR/outside"
  [ "$status" -eq 0 ]
  [[ "$output" == *"observed=inherited/other-hook/kept"* ]]
  [ "$(wc -l < "$HOME/initializations")" -eq 1 ]
}

@test "explicit reload connects ordinary Bash to its session and applies flake edits to the next Bash" {
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  printf 'export PROJECT_NAME=reloaded\n' >"$PROJECT/environment.sh"
  run subsequent_bash 'printf "%s\n" "$PROJECT_NAME"'
  [ "$output" = first ]
  run subsequent_bash "cd '$PROJECT' && devshell-env reload"
  [ "$status" -eq 0 ]
  run subsequent_bash 'printf "%s/%s\n" "$PROJECT_NAME" "${FROM_HOOK-unset}"'
  [ "$output" = reloaded/unset ]
  [ "$(wc -l < "$HOME/initializations")" -eq 2 ]
  run "$CLI" reload
  [ "$status" -ne 0 ]
  [[ "$output" == *"managed Claude Bash session"* ]]
}

@test "unregistered, flake-free and invalid targets clear the old environment without evaluating Nix" {
  "$CLI" trust "$PROJECT"
  git init -q "$BATS_TEST_TMPDIR/untrusted"
  touch "$BATS_TEST_TMPDIR/untrusted/flake.nix"
  git -C "$PROJECT" worktree add -qb empty "$BATS_TEST_TMPDIR/no-flake"
  mv "$BATS_TEST_TMPDIR/no-flake/flake.nix" "$BATS_TEST_TMPDIR/no-flake/absent.nix"
  mkdir "$BATS_TEST_TMPDIR/outside"
  local target
  for target in untrusted no-flake outside; do
    hook SessionStart "$PROJECT"
    run hook CwdChanged "$BATS_TEST_TMPDIR/$target"
    [ "$status" -eq 0 ]
    run subsequent_bash 'printf "%s\n" "${PROJECT_NAME-unset}"; command -v project-tool || :'
    [ "$status" -eq 0 ]
    [ "$output" = unset ]
  done
  [ "$(wc -l < "$HOME/initializations")" -eq 3 ]
  hook SessionStart "$PROJECT"
  "$CLI" untrust "$PROJECT"
  run hook CwdChanged "$PROJECT"
  run subsequent_bash 'printf "%s\n" "${PROJECT_NAME-unset}"'
  [ "$output" = unset ]
  [ "$(wc -l < "$HOME/initializations")" -eq 4 ]
}

@test "the synchronous Bash hook uses current cwd even without a CwdChanged event" {
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  git -C "$PROJECT" worktree add -qb task "$BATS_TEST_TMPDIR/task"
  printf 'export PROJECT_NAME=entered\n' >"$BATS_TEST_TMPDIR/task/environment.sh"
  run hook PreToolUse "$BATS_TEST_TMPDIR/task"
  [ "$status" -eq 0 ]
  run subsequent_bash 'printf "%s/%s\n" "$PROJECT_NAME" "${FROM_HOOK-unset}"'
  [ "$output" = entered/unset ]
  [ "$(wc -l < "$HOME/initializations")" -eq 2 ]
}

@test "failed initialization discards partial changes and explicit reload can recover" {
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  printf 'export PROJECT_NAME=partial\nexit 17\n' >"$PROJECT/environment.sh"
  run subsequent_bash "cd '$PROJECT' && devshell-env reload"
  [ "$status" -ne 0 ]
  [[ "$output" == *"shellHook preparation failed (17)"* ]]
  run subsequent_bash 'printf "%s\n" "${PROJECT_NAME-unset}"'
  [ "$output" = unset ]
  printf 'export PROJECT_NAME=recovered\n' >"$PROJECT/environment.sh"
  run subsequent_bash "cd '$PROJECT' && devshell-env reload"
  [ "$status" -eq 0 ]
  run subsequent_bash 'printf "%s\n" "$PROJECT_NAME"'
  [ "$output" = recovered ]
  printf '#!/bin/bash\nprintf "nix fixture failure\\n" >&2\nexit 18\n' >"$HOME/.local/bin/nix"
  run hook SessionStart "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nix preparation failed (18)"* ]]
  run subsequent_bash 'printf "%s\n" "${PROJECT_NAME-unset}"'
  [ "$output" = unset ]
}

@test "inherited and derived dummy secrets never enter the session files or Nix environment" {
  export DUMMY_SECRET=sentinel-inherited-256 PROJECT_NAME=sentinel-collision-256
  printf 'sentinel-dotenv-256\n' >"$PROJECT/.env"
  printf 'touch envrc-was-read\n' >"$PROJECT/.envrc"
  cat >>"$PROJECT/environment.sh" <<'EOF'
export DERIVED_SECRET="prefix-${DUMMY_SECRET-unset}"
export DERIVED_COLLISION="prefix-${PROJECT_NAME-unset}"
export DEVSHELL_ENV_SESSION=/wrong CLAUDE_CONFIG_DIR=/wrong
EOF
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  run subsequent_bash 'printf "%s/%s\n" "$DERIVED_SECRET" "$DERIVED_COLLISION"; test "$DUMMY_SECRET" = sentinel-inherited-256'
  [ "$status" -eq 0 ]
  [ "$output" = prefix-unset/prefix-first ]
  ! rg -a -q 'sentinel-inherited-256|sentinel-collision-256|sentinel-dotenv-256' "$CLAUDE_CONFIG_DIR" "$XDG_STATE_HOME" "$CLAUDE_ENV_FILE"
  [ ! -e "$PROJECT/envrc-was-read" ]
  run subsequent_bash "cd '$PROJECT' && devshell-env reload"
  [ "$status" -eq 0 ]
  ! rg -a -q 'sentinel-inherited-256|sentinel-collision-256|sentinel-dotenv-256' "$CLAUDE_CONFIG_DIR" "$CLAUDE_ENV_FILE"
}

@test "a delayed CwdChanged cannot replace the environment chosen by a newer Bash hook" {
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  git -C "$PROJECT" worktree add -qb task "$BATS_TEST_TMPDIR/task"
  printf 'export PROJECT_NAME=current\n' >"$BATS_TEST_TMPDIR/task/environment.sh"
  hook PreToolUse "$BATS_TEST_TMPDIR/task"
  jq -nc --arg cwd "$PROJECT" \
    '{session_id:"fixture-session",hook_event_name:"CwdChanged",cwd:$cwd,new_cwd:$cwd}' |
    "$CLI" claude-hook
  run env -u CLAUDE_ENV_FILE bash --noprofile --norc -c 'source "$1"; printf "%s\n" "$PROJECT_NAME"' _ "$CLAUDE_ENV_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = current ]
  [ "$(wc -l < "$HOME/initializations")" -eq 2 ]
}

@test "zsh applies and restores values with shell syntax without evaluating their contents" {
  command -v zsh >/dev/null || skip "zsh is required for the alternate Claude Bash backend"
  cat >>"$PROJECT/environment.sh" <<'EOF'
export name='ordinary flake name'
export value='$(touch should-not-run); "literal"'
EOF
  "$CLI" trust "$PROJECT"
  hook SessionStart "$PROJECT"
  run zsh -f -c '
    export name=baseline
    source "$1"
    test "$name" = "ordinary flake name" || exit 1
    test "$value" = '\''$(touch should-not-run); "literal"'\'' || exit 2
    jq -nc --arg cwd "$3" "{session_id:\"fixture-session\",hook_event_name:\"PreToolUse\",cwd:\$cwd}" | env -u CLAUDE_ENV_FILE "$2" claude-hook
    source "$1"
    test "$name" = baseline || exit 3
    test "${value-unset}" = unset || exit 4
    test ! -e should-not-run
  ' _ "$CLAUDE_ENV_FILE" "$CLI" "$HOME"
  [ "$status" -eq 0 ]
}
