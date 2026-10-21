#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REVIEWER="$PROJECT_ROOT/private_dot_local/bin/executable_codex-reviewer"
  BIN="$BATS_TEST_TMPDIR/bin"
  LAUNCHED="$BATS_TEST_TMPDIR/codex-argv"
  mkdir -p "$BIN"
  cat >"$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$LAUNCHED"
EOF
  chmod +x "$BIN/codex"
  REPO="$BATS_TEST_TMPDIR/repo.d"
  WORKTREE="$BATS_TEST_TMPDIR/review.d"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=test@example.com -c user.name=Test commit -q --allow-empty -m init
  git -C "$REPO" worktree add -q "$WORKTREE"
  REPO="$(cd "$REPO" && pwd -P)"
  WORKTREE="$(cd "$WORKTREE" && pwd -P)"
}

reviewer() {
  run env PATH="$BIN:$PATH" bash -c 'cd "$1" && shift && exec "$@"' _ "$1" "$REVIEWER" "${@:2}"
}

@test "linked worktree launches Codex with read-only access to its exact Git metadata" {
  reviewer "$WORKTREE/" -m some-model "review prompt"

  [ "$status" -eq 0 ]
  mapfile -t argv <"$LAUNCHED"
  [ "${argv[0]}" = "-C" ]
  [ "${argv[1]}" = "$WORKTREE" ]
  [ "${argv[2]}" = "-c" ]
  [ "${argv[3]}" = 'default_permissions="dotfiles-secure"' ]
  [ "${argv[4]}" = "-c" ]
  [ "${argv[5]}" = "permissions.dotfiles-secure.filesystem={\"$REPO/.git/worktrees/review.d\"=\"read\",\"$REPO/.git\"=\"read\"}" ]
  [ "${argv[6]}" = "-m" ]
  [ "${argv[7]}" = "some-model" ]
  [ "${argv[8]}" = "review prompt" ]
  [ "${#argv[@]}" -eq 9 ]
}

@test "--peer grants the same Git metadata read through the dotfiles-peer profile" {
  reviewer "$WORKTREE" --peer --disable apps

  [ "$status" -eq 0 ]
  mapfile -t argv <"$LAUNCHED"
  [ "${argv[3]}" = 'default_permissions="dotfiles-peer"' ]
  [ "${argv[5]}" = "permissions.dotfiles-peer.filesystem={\"$REPO/.git/worktrees/review.d\"=\"read\",\"$REPO/.git\"=\"read\"}" ]
  [ "${argv[6]}" = "--disable" ]
  [ "${argv[7]}" = "apps" ]
  [ "${#argv[@]}" -eq 8 ]
}

@test "arguments that can replace the reviewer boundary are rejected without launching Codex" {
  local case
  local -a cases=(
    -C/tmp --cd=/tmp -s --sandbox=danger-full-access --add-dir=/tmp --worktree
    -Pother --permissions-profile=other -pother --profile=other
    --dangerously-bypass-approvals-and-sandbox --yolo --ignore-user-config --ignore-rules
    --approve-for-me --remote=ws://x --remote-auth-token-env=X
    -cdefault_permissions=x --config=permissions.dotfiles-secure.filesystem={}
    "-c|permissions.x={}" "--config|sandbox_mode=\"danger-full-access\""
    "-c|sandbox_workspace_write.network_access=true" "-c|profile=\"other\"" "-c|profiles.x={}"
  )
  for case in "${cases[@]}"; do
    IFS='|' read -r -a argv <<<"$case"
    reviewer "$WORKTREE" "${argv[@]}"
    [ "$status" -eq 1 ] || { echo "accepted: $case"; return 1; }
    [[ "$output" == "codex-reviewer: "* ]]
    [ ! -e "$LAUNCHED" ]
  done
}

@test "other config overrides and arguments after -- reach Codex unchanged" {
  reviewer "$WORKTREE" -c 'model_reasoning_effort="high"' -- --sandbox

  [ "$status" -eq 0 ]
  mapfile -t argv <"$LAUNCHED"
  [ "${argv[6]}" = "-c" ]
  [ "${argv[7]}" = 'model_reasoning_effort="high"' ]
  [ "${argv[8]}" = "--" ]
  [ "${argv[9]}" = "--sandbox" ]
}

@test "primary checkout fails closed without launching Codex" {
  reviewer "$REPO" prompt

  [ "$status" -eq 1 ]
  [[ "$output" == "codex-reviewer: "* ]]
  [ ! -e "$LAUNCHED" ]
}

@test "non-Git directory fails closed without launching Codex" {
  mkdir "$BATS_TEST_TMPDIR/plain"
  reviewer "$BATS_TEST_TMPDIR/plain" prompt

  [ "$status" -eq 1 ]
  [[ "$output" == "codex-reviewer: "* ]]
  [ ! -e "$LAUNCHED" ]
}

@test "worktree whose Git dir back-pointer is broken fails closed without launching Codex" {
  echo "$BATS_TEST_TMPDIR/elsewhere/.git" >"$REPO/.git/worktrees/review.d/gitdir"
  reviewer "$WORKTREE" prompt

  [ "$status" -eq 1 ]
  [[ "$output" == "codex-reviewer: "* ]]
  [ ! -e "$LAUNCHED" ]
}
