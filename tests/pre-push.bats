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
}

push_refs() {
  # git が pre-push hook の stdin へ渡す形: <local ref> <local sha> <remote ref> <remote sha>
  printf 'refs/heads/topic %s refs/heads/topic %s\n' "$1" "$ZERO" | "$PROJECT_ROOT/scripts/pre-push.sh" origin url
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
