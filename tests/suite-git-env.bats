#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VICTIM="$BATS_TEST_TMPDIR/victim"
  mkdir -p "$VICTIM"
  git -C "$VICTIM" init -q
  printf 'victim\n' >"$VICTIM/victim-file"
  git -C "$VICTIM" add victim-file
  git -C "$VICTIM" -c user.name=Victim -c user.email=victim@example.test commit -qm victim
}

victim_state() {
  git -C "$VICTIM" symbolic-ref HEAD
  git -C "$VICTIM" rev-parse HEAD
  git -C "$VICTIM" for-each-ref
  git -C "$VICTIM" ls-files -s
  git -C "$VICTIM" worktree list
}

@test "bats を直接実行しても、継承した GIT_DIR 系が fixture の git に届かず実 repo を変えない" {
  local before
  before="$(victim_state)"

  run env -i PATH="$PATH" HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_DIR="$VICTIM/.git" GIT_WORK_TREE="$VICTIM" GIT_INDEX_FILE="$VICTIM/.git/index" \
    GIT_ENV_PROBE=1 \
    bats "$PROJECT_ROOT/tests/git-env-probe.bats"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok 1 probe: fixture の git は継承した GIT_DIR に作用しない"* ]]
  [[ "$output" != *"ok 1 probe: fixture の git は継承した GIT_DIR に作用しない # skip"* ]]
  [ "$(victim_state)" = "$before" ]
}
