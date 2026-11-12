#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO="$BATS_TEST_TMPDIR/repo"
  CALLS="$BATS_TEST_TMPDIR/calls"
  git init -q "$REPO"
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  cd "$REPO"
  : >"$CALLS"
  # 実 Bats は走らせず、どのコマンドが呼ばれたかだけを記録する。
  printf '#!/usr/bin/env bash\necho full >>"%s"\nexit "${FULL_STATUS:-0}"\n' "$CALLS" >"$BATS_TEST_TMPDIR/full"
  printf '#!/usr/bin/env bash\necho docs >>"%s"\nexit "${DOCS_STATUS:-0}"\n' "$CALLS" >"$BATS_TEST_TMPDIR/docs"
  chmod +x "$BATS_TEST_TMPDIR/full" "$BATS_TEST_TMPDIR/docs"
  export DOTFILES_PRE_PUSH_FULL_CMD="$BATS_TEST_TMPDIR/full"
  export DOTFILES_PRE_PUSH_DOCS_CMD="$BATS_TEST_TMPDIR/docs"
  ZERO=0000000000000000000000000000000000000000
  HEAD_SHA=$(git rev-parse HEAD)
  git update-ref refs/remotes/origin/main "$HEAD_SHA"
}

push_refs() {
  # git が pre-push hook の stdin へ渡す形: <local ref> <local sha> <remote ref> <remote sha>
  printf 'refs/heads/topic %s refs/heads/topic %s\n' "$1" "$ZERO" | "$PROJECT_ROOT/scripts/pre-push.sh" origin url
}

change_bash_entry() {
  mkdir -p private_dot_local/bin
  printf '#!/bin/bash\n' >private_dot_local/bin/executable_codex-repo-state
  git add .
  git -c user.name=t -c user.email=t@example.com commit -qm 'test: change repo state'
}

@test "runtime-sensitive changes cannot be recorded without Bash 3.2" {
  change_bash_entry

  run -1 env -u TEST_COMPAT_BASH "$PROJECT_ROOT/scripts/pre-push.sh" record

  [[ "$output" == *TEST_COMPAT_BASH* ]]
  [ ! -s "$(git rev-parse --git-path tested-trees)" ]
}

@test "renaming a runtime-sensitive path still requires its runtime" {
  change_bash_entry
  git update-ref refs/remotes/origin/main HEAD
  git mv private_dot_local/bin/executable_codex-repo-state moved-script
  git -c user.name=t -c user.email=t@example.com commit -qm 'test: rename repo state'

  run -1 env -u TEST_COMPAT_BASH "$PROJECT_ROOT/scripts/pre-push.sh" record

  [[ "$output" == *TEST_COMPAT_BASH* ]]
  [ ! -s "$(git rev-parse --git-path tested-trees)" ]
}

@test "runtime-sensitive changes reject a newer Bash before starting the full suite" {
  change_bash_entry
  printf '#!/bin/sh\nprintf 5.3\n' >"$BATS_TEST_TMPDIR/new-bash"
  chmod +x "$BATS_TEST_TMPDIR/new-bash"

  DOCS_STATUS=2 run -1 env TEST_COMPAT_BASH="$BATS_TEST_TMPDIR/new-bash" \
    "$PROJECT_ROOT/scripts/pre-push.sh" < <(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$(git rev-parse HEAD)" "$ZERO")

  [[ "$output" == *'Bash 3.2'* ]]
  [ ! -s "$CALLS" ]
}

@test "runtime gate refuses skipped or missing tests even when Bats succeeds" {
  change_bash_entry
  local bin="$BATS_TEST_TMPDIR/bin" mode
  mkdir -p "$bin"
  printf '#!/bin/sh\nprintf 3.2\n' >"$bin/bash32"
  cat >"$bin/bats" <<'SH'
#!/bin/sh
printf '1..1\n'
if [ "$RUNTIME_TAP_MODE" = skip ]; then
  printf 'ok 1 codex repo state works without inherited Git variables # skip 未指定\n'
else
  printf 'ok 1 unrelated test\n'
fi
SH
  chmod +x "$bin/bash32" "$bin/bats"
  for mode in skip missing; do
    run -1 env PATH="$bin:$PATH" TEST_COMPAT_BASH="$bin/bash32" RUNTIME_TAP_MODE="$mode" \
      "$PROJECT_ROOT/scripts/pre-push.sh" record
    [[ "$output" == *'必須fixtureが欠落・重複・失敗・skip'* ]]
    [ ! -s "$(git rev-parse --git-path tested-trees)" ]
  done
}

@test "runtime gate records the tree only after both required tests pass" {
  change_bash_entry
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\nprintf 3.2\n' >"$bin/bash32"
  cat >"$bin/bats" <<'SH'
#!/bin/sh
  printf '1..1\nok 1 codex repo state works without inherited Git variables\n'
SH
  chmod +x "$bin/bash32" "$bin/bats"

  run -0 env PATH="$bin:$PATH" TEST_COMPAT_BASH="$bin/bash32" \
    "$PROJECT_ROOT/scripts/pre-push.sh" record

  grep -qxF "$(git rev-parse 'HEAD^{tree}')" "$(git rev-parse --git-path tested-trees)"
}

@test "a push that only deletes a ref runs nothing" {
  run -0 bash -c 'printf "(delete) %s refs/heads/topic %s\n" "$1" "$1" | "$2/scripts/pre-push.sh" origin url' _ "$ZERO" "$PROJECT_ROOT"
  [ ! -s "$CALLS" ]
}

@test "an empty ref list is not treated as a deletion" {
  DOCS_STATUS=2 run -0 bash -c ': | "$1/scripts/pre-push.sh" origin url' _ "$PROJECT_ROOT"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "a pushed commit that is not HEAD and was never verified is refused without running tests" {
  git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m second
  echo change >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m third
  run -1 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "a pushed commit that is not HEAD passes when its tree was verified" {
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  echo change >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m second
  run -0 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "every pushed ref must be verified" {
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  echo one >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m second
  second=$(git rev-parse HEAD)
  echo two >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m third
  run -1 bash -c 'printf "refs/heads/a %s refs/heads/a %s\nrefs/heads/b %s refs/heads/b %s\n" "$1" "$3" "$2" "$3" | "$4/scripts/pre-push.sh" origin url' _ "$HEAD_SHA" "$second" "$ZERO" "$PROJECT_ROOT"
  [ ! -s "$CALLS" ]
}

@test "a docs-only change passes after the docs entry succeeds, without the full Bats" {
  run -0 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = docs ]
}

@test "a change outside the docs exception runs the full Bats" {
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "a failing full Bats blocks the push with its status" {
  DOCS_STATUS=2 FULL_STATUS=7 run -7 push_refs "$HEAD_SHA"
}

@test "a failing docs entry blocks the push without falling back to the full Bats" {
  DOCS_STATUS=1 run -1 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = docs ]
}

@test "a tree that already passed is not tested again" {
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  : >"$CALLS"
  run -0 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "a tree that failed is tested again on the next push" {
  DOCS_STATUS=2 FULL_STATUS=1 run -1 push_refs "$HEAD_SHA"
  : >"$CALLS"
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "a new commit with different content is tested even after an earlier pass" {
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  echo change >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m change
  : >"$CALLS"
  DOCS_STATUS=2 run -0 push_refs "$(git rev-parse HEAD)"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "an unverified tree is refused without running tests while the worktree has untracked files" {
  echo change >file
  run -1 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "an unverified tree is refused without running tests while the worktree has uncommitted changes" {
  echo change >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m second
  echo changed >file
  run -1 push_refs "$(git rev-parse HEAD)"
  [ ! -s "$CALLS" ]
}

@test "a verified tree passes even while the worktree has uncommitted changes" {
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  echo change >file
  run -0 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "record remembers a clean tree so the next push runs nothing" {
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  run -0 push_refs "$HEAD_SHA"
  [ ! -s "$CALLS" ]
}

@test "record does not remember a tree with uncommitted changes" {
  echo change >file
  git add file
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  git reset -q
  rm file
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "record does not remember a tree with untracked files" {
  echo change >file
  run -0 "$PROJECT_ROOT/scripts/pre-push.sh" record
  rm file
  DOCS_STATUS=2 run -0 push_refs "$HEAD_SHA"
  [ "$(cat "$CALLS")" = $'docs\nfull' ]
}

@test "hidden index changes cannot be tested or recorded as the committed tree" {
  printf 'committed\n' >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m fixture
  local flag
  for flag in assume-unchanged skip-worktree; do
    git update-index "--$flag" file
    printf 'only in the working tree\n' >file
    [ -z "$(git status --porcelain)" ]

    run -1 push_refs "$(git rev-parse HEAD)"
    [ ! -s "$CALLS" ]
    run -1 "$PROJECT_ROOT/scripts/pre-push.sh" record
    [ ! -s "$(git rev-parse --git-path tested-trees)" ]

    git update-index "--no-$flag" file
    printf 'committed\n' >file
  done
}

@test "record from a subdirectory checks hidden files elsewhere in the repository" {
  printf 'committed\n' >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m fixture
  git update-index --assume-unchanged file
  printf 'hidden change\n' >file
  mkdir subdirectory
  cd subdirectory

  run -1 "$PROJECT_ROOT/scripts/pre-push.sh" record

  [ ! -s "$(git rev-parse --git-path tested-trees)" ]
}

@test "failed Git inspections refuse both recording and an unverified push" {
  local bin="$BATS_TEST_TMPDIR/bin" real_git command
  real_git=$(command -v git)
  mkdir "$bin"
  cat >"$bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "$FAIL_GIT_COMMAND" ]]; then
  printf 'simulated Git inspection failure\n' >&2
  exit 128
fi
exec "$REAL_GIT" "$@"
SH
  chmod +x "$bin/git"
  for command in status ls-files; do
    run -1 env PATH="$bin:$PATH" REAL_GIT="$real_git" FAIL_GIT_COMMAND="$command" \
      "$PROJECT_ROOT/scripts/pre-push.sh" record
    [ ! -s "$(git rev-parse --git-path tested-trees)" ]
    run -1 env PATH="$bin:$PATH" REAL_GIT="$real_git" FAIL_GIT_COMMAND="$command" \
      "$PROJECT_ROOT/scripts/pre-push.sh" <<<"refs/heads/topic $HEAD_SHA refs/heads/topic $ZERO"
    [ ! -s "$CALLS" ]
    [ ! -s "$(git rev-parse --git-path tested-trees)" ]
  done
}

@test "hidden changes introduced by the tests also refuse the push" {
  printf 'committed\n' >file
  git add file
  git -c user.name=t -c user.email=t@example.com commit -q -m fixture
  cat >"$BATS_TEST_TMPDIR/full" <<'SH'
#!/usr/bin/env bash
git update-index --assume-unchanged file
printf 'only tested locally\n' >file
SH

  DOCS_STATUS=2 run -1 push_refs "$(git rev-parse HEAD)"

  [ ! -s "$(git rev-parse --git-path tested-trees)" ]
}
