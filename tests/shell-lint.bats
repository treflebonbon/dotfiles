#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  BIN="$BATS_TEST_TMPDIR/bin"
  export SHELL_LINT_LOG="$BATS_TEST_TMPDIR/lint.jsonl"
  mkdir -p "$FIXTURE/private_dot_local/bin" "$FIXTURE/private_dot_local/share/devshell-env" "$BIN"
  cp "$PROJECT_ROOT/lefthook.yml" "$FIXTURE/lefthook.yml"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config" "$FIXTURE/private_dot_local/bin/"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env" "$FIXTURE/private_dot_local/bin/"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_codex-worktree" "$FIXTURE/private_dot_local/bin/"
  cp "$PROJECT_ROOT/private_dot_local/share/devshell-env/claude-env.sh" "$FIXTURE/private_dot_local/share/devshell-env/"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" add .
  local tool
  for tool in shfmt shellcheck; do
    cat >"$BIN/$tool" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['SHELL_LINT_LOG'], 'a') as log:
    log.write(json.dumps([Path(sys.argv[0]).name, *sys.argv[1:]]) + '\n')
PY
    chmod +x "$BIN/$tool"
  done
  cd "$FIXTURE"
}

@test "pre-commit checks extensionless Bash and skips neighboring Python scripts" {
  run env PATH="$BIN:$PATH" lefthook run pre-commit --no-auto-install --no-stage-fixed \
    --job shell-extensionless \
    --file private_dot_local/bin/executable_sync-codex-managed-config \
    --file private_dot_local/bin/executable_devshell-env \
    --file private_dot_local/bin/executable_codex-worktree

  [ "$status" -eq 0 ]
  python3 - "$SHELL_LINT_LOG" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert sorted(row[0] for row in rows)==['shellcheck', 'shfmt']
for row in rows:
    assert row[1:]==(['-w'] if row[0]=='shfmt' else [])+['private_dot_local/bin/executable_sync-codex-managed-config']
PY
}

@test "pre-commit keeps checking shell fragments without a shebang" {
  run env PATH="$BIN:$PATH" lefthook run pre-commit --no-auto-install --no-stage-fixed \
    --job shfmt --job shellcheck --file private_dot_local/share/devshell-env/claude-env.sh

  [ "$status" -eq 0 ]
  python3 - "$SHELL_LINT_LOG" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert sorted(row[0] for row in rows)==['shellcheck', 'shfmt']
assert all(row[-1]=='private_dot_local/share/devshell-env/claude-env.sh' for row in rows)
PY
}
