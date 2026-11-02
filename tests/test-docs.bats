#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load 'helpers/outside-tmpdir'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$PROJECT_ROOT"
}

teardown() {
  [ -z "${KEPT_TMPDIR:-}" ] || rmdir "$KEPT_TMPDIR"
}

# 受け取った TMPDIR を記録するだけの bats。呼ばれるたびに1行足す。
write_tmpdir_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$TMPDIR" >> "$BATS_TEST_TMPDIR/tmpdirs"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/bats"
}

@test "a docs-only change plans the contract Bats plus Bats that reference the file" {
  run -0 scripts/test-docs.sh --plan runtime/skill-harness.md
  [[ "$output" == *"tests/workflow-contract.bats"* ]]
  [[ "$output" == *"tests/autonomous-peer-contract.bats"* ]]
}

@test "an out-of-scope record is a docs-only change" {
  run -0 scripts/test-docs.sh --plan .out-of-scope/embedded-bash-shellcheck.md
  [[ "$output" == *"tests/workflow-contract.bats"* ]]
}

@test "a non-docs file in the change requires the full Bats" {
  run scripts/test-docs.sh --plan runtime/index.md tests/with-env.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"例外の対象外: tests/with-env.bats"* ]]
}

@test "configuration and templates stay outside the exception" {
  local file
  for file in lefthook.yml .chezmoiignore private_dot_claude/settings.json.tmpl private_dot_config/codex/config.toml.tmpl; do
    run scripts/test-docs.sh --plan "$file"
    [ "$status" -eq 2 ]
  done
}

@test "a docs-only run does not pass git hook GIT_* variables to Bats" {
  local bin="$BATS_TEST_TMPDIR/bin" log="$BATS_TEST_TMPDIR/log"
  mkdir -p "$bin"
  printf '#!/bin/bash\nenv | grep -c "^GIT_DIR=" >> "%s" || true\n' "$log" >"$bin/bats"
  chmod +x "$bin/bats"

  GIT_DIR="$BATS_TEST_TMPDIR/hook.git" PATH="$bin:$PATH" run scripts/test-docs.sh runtime/skill-harness.md

  [ "$status" -eq 0 ]
  [ "$(sort -u "$log")" = 0 ]
}

@test "a docs-only run hands bats a TMPDIR under the scratch root when TMPDIR is outside it" {
  [ "$(uname -s)" = Linux ] || skip "the scratch root belongs to the Linux write-protected verification"
  local outside handed
  write_tmpdir_stub
  outside=$(make_outside_tmpdir)
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" TMPDIR="$outside" run scripts/test-docs.sh runtime/skill-harness.md
  rmdir "$outside"
  [ "$status" -eq 0 ]
  # bats は2回呼ばれ、どちらも同じ TMPDIR を受け取る。
  [ "$(wc -l <"$BATS_TEST_TMPDIR/tmpdirs")" -eq 2 ]
  handed=$(sort -u "$BATS_TEST_TMPDIR/tmpdirs")
  [ "$(wc -l <<<"$handed")" -eq 1 ]
  [[ "$handed" == /tmp/codex/* ]]
  [ ! -e "$handed" ]
}

@test "a docs-only run keeps a TMPDIR that is already under the scratch root" {
  [ "$(uname -s)" = Linux ] || skip "the scratch root belongs to the Linux write-protected verification"
  write_tmpdir_stub
  mkdir -p -m 700 /tmp/codex
  [ -O /tmp/codex ] && [ ! -L /tmp/codex ]
  KEPT_TMPDIR=$(mktemp -d /tmp/codex/test-docs-keep.XXXXXX)
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" TMPDIR="$KEPT_TMPDIR" run scripts/test-docs.sh runtime/skill-harness.md
  [ "$status" -eq 0 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/tmpdirs")" = "$KEPT_TMPDIR" ]
  [ -d "$KEPT_TMPDIR" ]
}

@test "a docs-only run does not trust a TMPDIR that only starts with the scratch root path" {
  [ "$(uname -s)" = Linux ] || skip "the scratch root belongs to the Linux write-protected verification"
  local handed
  write_tmpdir_stub
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" TMPDIR=/tmp/codex/../not-the-scratch-root run scripts/test-docs.sh runtime/skill-harness.md
  [ "$status" -eq 0 ]
  handed=$(sort -u "$BATS_TEST_TMPDIR/tmpdirs")
  [[ "$handed" == /tmp/codex/* ]]
  [[ "$handed" != *..* ]]
}
