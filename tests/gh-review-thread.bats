#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "runtime guidance defines the Review Round contract across agents" {
  local guidance
  for guidance in \
    "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$PROJECT_ROOT/private_dot_claude/CLAUDE.md" \
    "$PROJECT_ROOT/private_dot_gemini/AGENTS.md"; do
    grep -Fq 'Requests to address pull request review feedback authorize a Review Round' "$guidance"
    grep -Fq 'use `gh-review-thread` rather than the GitHub plugin' "$guidance"
    grep -Fq 'post a Japanese reply' "$guidance"
    grep -Fq '`fix: address PR review feedback`' "$guidance"
    grep -Fq 'short commit SHA' "$guidance"
  done

  grep -Fq '`~/runtime/skill-harness.md`' "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md"
  ! grep -Fq '`gh-address-comments`' "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md"
  grep -Fq '`gh-address-comments`' "$PROJECT_ROOT/private_dot_claude/CLAUDE.md"
  grep -Fq '`gh-review-thread`' "$PROJECT_ROOT/private_dot_claude/CLAUDE.md"
  grep -Fq 'Review Round' "$PROJECT_ROOT/private_dot_claude/CLAUDE.md"

  grep -Fq '**Review Round**' "$PROJECT_ROOT/GLOSSARY.md"
  grep -Fq '`gh-address-comments`' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq '`gh-review-thread`' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq '`--explanation-only`' "$PROJECT_ROOT/runtime/skill-harness.md"

  local adr="$PROJECT_ROOT/docs/adr/0032-automate-review-round.md"
  [ -f "$adr" ]
  grep -Fq 'status: accepted' "$adr"
  grep -Fq 'ADR-0023' "$adr"
  grep -Fq 'ADR-0030' "$adr"
}

@test "Codex execpolicy allows only the bounded review thread CLI" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"

  local command
  for command in \
    "gh-review-thread inspect --repo owner/repo --pr 42" \
    "gh-review-thread reply-resolve --repo owner/repo --pr 42 --thread-id PRRT_1 --explanation-only --body-file reply.md"; do
    run bash -c "codex execpolicy check --pretty --rules '$rules' -- $command"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "allow"'* ]]
  done

  run bash -c \
    "codex execpolicy check --pretty --rules '$rules' -- gh api graphql -f query=mutation"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision": "allow"'* ]]
}
