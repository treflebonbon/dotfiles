# /tmp/codex の外で、保護された検証経路でも書き込める task worktree の ignore 済み tmp/ に作る。
make_outside_tmpdir() {
  local repo_tmp
  repo_tmp="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/tmp"
  mkdir -p "$repo_tmp"
  mktemp -d "$repo_tmp/outside-tmpdir.XXXXXX"
}
