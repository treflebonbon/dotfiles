#!/usr/bin/env bats

@test "topic publication records push separately and verifies without another push" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  if [ "$(uname -s)" = Linux ]; then
    run bwrap --unshare-user --unshare-pid --ro-bind / / --dev /dev --proc /proc \
      --tmpfs /tmp -- env TMPDIR=/tmp python3 "$root/tests/publish-topic.py"
  else
    run python3 "$root/tests/publish-topic.py"
  fi

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
