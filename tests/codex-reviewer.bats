#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILLS_ROOT="$(cd "${TREFLEBONBON_SKILLS_LIB:?run tests in the pinned skills-plugin devShell}/../.." && pwd)"
}

# Prints command lines that start Codex with `herdr agent start`, joining
# backslash continuations first. Commands only: prose may still name the
# unsupported route in backticks.
herdr_codex_launches() {
  # Text files only; awk warns on binaries such as __pycache__ entries.
  grep -rIlZ '' "$@" | xargs -0 awk '
    FNR == 1 { command = "" }
    /\\$/ { command = command substr($0, 1, length($0) - 1); next }
    {
      command = command $0
      if (command ~ /^[[:space:]]*(\$[[:space:]]+)?herdr[[:space:]]+agent[[:space:]]+start[[:space:]][^`]*--kind(=|[[:space:]]+)codex/) {
        print FILENAME ": " command
      }
      command = ""
    }
  '
}

@test "herdr Codex launch check also catches commands wrapped with backslash continuations" {
  printf '%s\n' '```bash' 'herdr agent start reviewer \' '  --kind codex --pane 1' '```' \
    >"$BATS_TEST_TMPDIR/wrapped.md"

  run herdr_codex_launches "$BATS_TEST_TMPDIR/wrapped.md"

  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/wrapped.md: herdr agent start reviewer   --kind codex --pane 1" ]
}

@test "herdr Codex launch check also catches repeated whitespace and --kind=codex" {
  local command
  for command in 'herdr  agent start reviewer --kind codex' 'herdr agent  start reviewer --kind  codex' \
    'herdr agent start reviewer --kind=codex'; do
    printf '%s\n' "$command" >"$BATS_TEST_TMPDIR/spaced.md"
    run herdr_codex_launches "$BATS_TEST_TMPDIR/spaced.md"
    [ -n "$output" ] || { echo "missed: $command"; return 1; }
  done
}

@test "skills and runtime docs start Codex through codex-reviewer or codex-worktree, not herdr agent start" {
  local reference="$SKILLS_ROOT/skills/herdr-peer-refactor/references/herdr.md"
  [ -x "$SKILLS_ROOT/bin/codex-reviewer" ]
  grep -Fq '"$plugin_root/bin/codex-reviewer" --peer' "$reference"

  run herdr_codex_launches \
    "$PROJECT_ROOT/private_dot_config/codex" \
    "$PROJECT_ROOT/private_dot_claude" \
    "$PROJECT_ROOT/private_dot_gemini" \
    "$PROJECT_ROOT/runtime" \
    "$SKILLS_ROOT/skills/herdr-peer-refactor"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
