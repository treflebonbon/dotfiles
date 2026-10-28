#!/usr/bin/env bats
# tests/suite-git-env.bats が、継承した GIT_DIR 付きで入れ子起動する probe。通常の実行では skip する。

@test "probe: fixture の git は継承した GIT_DIR に作用しない" {
  [ -n "${GIT_ENV_PROBE:-}" ] || skip "tests/suite-git-env.bats からのみ有効にする"
  local fixture="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$fixture"
  git -C "$fixture" init -q
  printf 'probe\n' >"$fixture/probe-file"
  git -C "$fixture" add probe-file
  git -C "$fixture" -c user.name=Probe -c user.email=probe@example.test commit -qm probe
  git -C "$fixture" worktree add -q -b probe-branch "$BATS_TEST_TMPDIR/probe-worktree"
}
