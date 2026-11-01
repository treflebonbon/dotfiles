#!/usr/bin/env bats

@test "skills plugin checkout verification detects tampering outside git status" {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  if [ "$(uname -s)" = Linux ]; then
    # 他 suite の Codex glob scan に fixture の作成・撤去を見せない。
    run bwrap --unshare-user --die-with-parent --ro-bind / / \
      --tmpfs /tmp --dir /tmp/codex --chmod 0700 /tmp/codex \
      --ro-bind "$PROJECT_ROOT" "$PROJECT_ROOT" --dev /dev --proc /proc \
      --chdir "$PROJECT_ROOT" python3 "$PROJECT_ROOT/tests/skills-plugin-verify.py"
  else
    run python3 "$PROJECT_ROOT/tests/skills-plugin-verify.py"
  fi

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
