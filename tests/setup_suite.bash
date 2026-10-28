#!/usr/bin/env bash
# Bats が各 suite の開始前に自動で読む。継承した GIT_DIR / GIT_WORK_TREE 等は fixture の git を
# 実 repo へ向けるため、scripts/test.sh を通らない直接の bats 実行でもここで外す。

setup_suite() {
  local git_vars git_var
  git_vars=$(git rev-parse --local-env-vars) || return 1
  while IFS= read -r git_var; do unset "$git_var"; done <<<"$git_vars"
}
