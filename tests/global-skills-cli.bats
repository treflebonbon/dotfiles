#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME/.local/bin"
  cat >"$TEST_HOME/.local/bin/sync-skills-plugin" <<'PY'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["DISPATCH_LOG"], "w", encoding="utf-8") as dispatch:
    dispatch.write("\n".join(sys.argv[1:]) + "\n")
PY
  chmod +x "$TEST_HOME/.local/bin/sync-skills-plugin"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env" "$TEST_HOME/.local/bin/devshell-env"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_codex-worktree" "$TEST_HOME/.local/bin/codex-worktree"
  export DISPATCH_LOG="$BATS_TEST_TMPDIR/dispatch.log"
}

assert_dispatch() {
  local name="$1"
  shift
  local entry="$PROJECT_ROOT/private_dot_local/bin/executable_$name"
  local expected="$BATS_TEST_TMPDIR/expected.log"
  run env HOME="$TEST_HOME" DISPATCH_LOG="$DISPATCH_LOG" "$entry" "$@"
  [ "$status" -eq 0 ]
  printf '%s\n' --run-cli "$name" -- "$@" >"$expected"
  cmp "$expected" "$DISPATCH_LOG"
}

@test "git-push-topic dispatches through the verified public CLI" {
  assert_dispatch git-push-topic --probe "topic with spaces"
}

@test "git-push-reviewed keeps its regular entrypoint name for the public basename branch" {
  local entry="$PROJECT_ROOT/private_dot_local/bin/executable_git-push-reviewed"
  [ -f "$entry" ]
  [ ! -L "$entry" ]
  assert_dispatch git-push-reviewed --probe
}

@test "gh-review-thread dispatches through the verified public CLI" {
  assert_dispatch gh-review-thread --repo owner/repo --pr 42
}

@test "orca-send dispatches through the verified public CLI" {
  assert_dispatch orca-send --body-file "$BATS_TEST_TMPDIR/body.md" -- send
}

@test "codex-reviewer dispatches through the verified public CLI" {
  assert_dispatch codex-reviewer --peer --model gpt-6
}

@test "generic devshell-env routes only raw Codex startup through the raw verifier" {
  run env HOME="$TEST_HOME" DISPATCH_LOG="$DISPATCH_LOG" \
    "$TEST_HOME/.local/bin/devshell-env" codex --probe "task with spaces"
  [ "$status" -eq 0 ]
  printf '%s\n' --run-raw codex -- --probe "task with spaces" >"$BATS_TEST_TMPDIR/expected.log"
  cmp "$BATS_TEST_TMPDIR/expected.log" "$DISPATCH_LOG"
}

@test "generic devshell-env routes raw admit with every public-input argument intact" {
  run env HOME="$TEST_HOME" DISPATCH_LOG="$DISPATCH_LOG" \
    "$TEST_HOME/.local/bin/devshell-env" admit --git-head abc --mcp context7 -- flake.nix task.sh
  [ "$status" -eq 0 ]
  printf '%s\n' --run-raw admit -- --git-head abc --mcp context7 -- flake.nix task.sh >"$BATS_TEST_TMPDIR/expected.log"
  cmp "$BATS_TEST_TMPDIR/expected.log" "$DISPATCH_LOG"
}

@test "generic devshell-env imports its shared module from the injected fixed source path" {
  local module_root="$BATS_TEST_TMPDIR/fixed/lib/python/treflebonbon_skills"
  local shadow_root="$BATS_TEST_TMPDIR/shadow/treflebonbon_skills"
  mkdir -p "$module_root" "$shadow_root"
  : >"$module_root/__init__.py"
  cat >"$module_root/devshell_environment.py" <<'PY'
class InvalidContext(Exception): pass
class PreparationError(Exception): pass
class Repository: pass
def executable(*args): return None
def prepare_environment(*args, **kwargs): return {}
def reuse_environment(*args, **kwargs): return {}
def selected_output(*args, **kwargs): return None
def trust_command(*args, **kwargs): return None
def trusted(*args, **kwargs): return False
PY
  printf 'raise RuntimeError("PYTHONPATH shadow was imported")\n' >"$shadow_root/devshell_environment.py"
  run env HOME="$TEST_HOME" TREFLEBONBON_SKILLS_LIB="$BATS_TEST_TMPDIR/fixed/lib/python" \
    PYTHONPATH="$BATS_TEST_TMPDIR/shadow" "$TEST_HOME/.local/bin/devshell-env" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: devshell-env"* ]]
}

@test "codex-worktree starts only through the verified public raw entry" {
  run env HOME="$TEST_HOME" DISPATCH_LOG="$DISPATCH_LOG" \
    "$TEST_HOME/.local/bin/codex-worktree" --no-alt-screen "task with spaces"
  [ "$status" -eq 0 ]
  printf '%s\n' --run-raw codex-worktree -- --no-alt-screen "task with spaces" >"$BATS_TEST_TMPDIR/expected.log"
  cmp "$BATS_TEST_TMPDIR/expected.log" "$DISPATCH_LOG"
}
