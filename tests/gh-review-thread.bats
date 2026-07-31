#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/private_dot_local/bin/executable_gh-review-thread"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  MOCK_LOG="$BATS_TEST_TMPDIR/gh.log"
  mkdir -p "$MOCK_BIN"

  cat >"$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MOCK_LOG"

case "$*" in
"auth status")
  ;;
"pr view 42 --repo owner/repo --json number,url,title,state,headRefOid,headRefName,baseRefName")
  printf '%s\n' '{"number":42,"url":"https://github.com/owner/repo/pull/42","title":"Review me","state":"OPEN","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","headRefName":"feature","baseRefName":"main"}'
  ;;
"pr diff 42 --repo owner/repo --patch")
  printf '%s\n' 'diff --git a/a.txt b/a.txt'
  ;;
*"reviewThreads(first:"*)
  printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"PRRT_1","isResolved":false,"isOutdated":false,"path":"a.txt","line":3,"diffSide":"RIGHT","startLine":null,"startDiffSide":null,"originalLine":3,"originalStartLine":null,"resolvedBy":null,"comments":{"nodes":[{"id":"PRRC_1","body":"Please fix","createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","author":{"login":"reviewer"}}]}}]}}}}}'
  ;;
*"node(id:"*)
  if [ "${MOCK_SCENARIO:-}" = "duplicate" ]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"body":"対応しました（aaaaaaa）。指摘箇所を修正しました。\n\n確認: bats成功。\n","author":{"login":"agent"}}]}}}}'
  elif [ "${MOCK_SCENARIO:-}" = "comment-pages" ] && [[ "$*" == *"cursor=NEXT"* ]]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"PRRC_2","body":"second","createdAt":"2026-07-31T00:01:00Z","updatedAt":"2026-07-31T00:01:00Z","author":{"login":"reviewer"}}]}}}}'
  elif [ "${MOCK_SCENARIO:-}" = "comment-pages" ]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":true,"endCursor":"NEXT"},"nodes":[{"id":"PRRC_1","body":"first","createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","author":{"login":"reviewer"}}]}}}}'
  elif [ "${MOCK_SCENARIO:-}" = "resolved" ]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":true,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}'
  elif [ "${MOCK_SCENARIO:-}" = "wrong-scope" ]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":7,"repository":{"nameWithOwner":"other/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}'
  elif [ "${MOCK_SCENARIO:-}" = "null-author" ]; then
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"body":"old reply","author":null}]}}}}'
  else
    printf '%s\n' '{"data":{"viewer":{"login":"agent"},"node":{"id":"PRRT_1","isResolved":false,"pullRequest":{"number":42,"repository":{"nameWithOwner":"owner/repo"}},"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"body":"Please fix","author":{"login":"reviewer"}}]}}}}'
  fi
  ;;
"api --paginate repos/owner/repo/pulls/42/commits --jq .[].sha")
  if [ "${MOCK_SCENARIO:-}" = "unpublished" ]; then
    printf '%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  else
    printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  fi
  ;;
*"addPullRequestReviewThreadReply"*)
  if [ "${MOCK_SCENARIO:-}" = "reply-failure" ]; then
    printf '%s\n' 'reply failed' >&2
    exit 1
  fi
  printf '%s\n' '{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"PRRC_REPLY"}}}}'
  ;;
*"resolveReviewThread"*)
  printf '%s\n' '{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_1","isResolved":true}}}}'
  ;;
*)
  printf 'unexpected gh invocation: %s\n' "$*" >&2
  exit 2
  ;;
esac
EOF
  chmod +x "$MOCK_BIN/gh"
}

@test "inspect returns thread-aware PR context from gh" {
  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" \
    python3 "$SCRIPT" inspect --repo owner/repo --pr 42

  [ "$status" -eq 0 ]
  run jq -e '
    .pull_request.number == 42
    and .diff == "diff --git a/a.txt b/a.txt\n"
    and .review_threads[0].id == "PRRT_1"
    and .review_threads[0].isResolved == false
  ' <<<"$output"
  [ "$status" -eq 0 ]
  grep -Fq 'pr view 42 --repo owner/repo' "$MOCK_LOG"
  grep -Fq 'pr diff 42 --repo owner/repo --patch' "$MOCK_LOG"
  grep -Fq 'api graphql' "$MOCK_LOG"
}

@test "reply-resolve publishes a verified reply before resolving the thread" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '対応しました（aaaaaaa）。指摘箇所を修正しました。' \
    '確認: bats成功。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --body-file "$body_file"

  [ "$status" -eq 0 ]
  run jq -e '
    .thread_id == "PRRT_1"
    and .reply == "created"
    and .resolve == "resolved"
  ' <<<"$output"
  [ "$status" -eq 0 ]

  reply_line="$(grep -n 'addPullRequestReviewThreadReply' "$MOCK_LOG" | head -n1 | cut -d: -f1)"
  resolve_line="$(grep -n 'resolveReviewThread' "$MOCK_LOG" | head -n1 | cut -d: -f1)"
  [ "$reply_line" -lt "$resolve_line" ]
}

@test "reply-resolve resumes without duplicating an identical viewer reply" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '対応しました（aaaaaaa）。指摘箇所を修正しました。' \
    '確認: bats成功。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="duplicate" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --body-file "$body_file"

  [ "$status" -eq 0 ]
  run jq -e '.reply == "skipped" and .resolve == "resolved"' <<<"$output"
  [ "$status" -eq 0 ]
  ! grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve treats an already resolved thread as an idempotent success" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '確認しました。既に対応済みです。' \
    '根拠: threadがresolvedです。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="resolved" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --explanation-only \
    --body-file "$body_file"

  [ "$status" -eq 0 ]
  run jq -e '.reply == "skipped" and .resolve == "already_resolved"' <<<"$output"
  [ "$status" -eq 0 ]
  ! grep -Fq 'pulls/42/commits' "$MOCK_LOG"
  ! grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  ! grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve refuses a thread from another pull request" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '確認しました。対象を確認しました。' \
    '根拠: PR metadataです。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="wrong-scope" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --explanation-only \
    --body-file "$body_file"

  [ "$status" -ne 0 ]
  [[ "$output" == *"review thread belongs to other/repo#7"* ]]
  ! grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  ! grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve refuses to resolve an unpublished fix commit" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '対応しました（aaaaaaa）。指摘箇所を修正しました。' \
    '確認: bats成功。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="unpublished" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --body-file "$body_file"

  [ "$status" -ne 0 ]
  [[ "$output" == *"is not published in owner/repo#42"* ]]
  ! grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  ! grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve never resolves when publishing the reply fails" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '確認しました。挙動を確認しました。' \
    '根拠: ADR-0031です。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="reply-failure" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --explanation-only \
    --body-file "$body_file"

  [ "$status" -ne 0 ]
  grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  ! grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve allows explanation-only threads without an empty commit" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '確認しました。この挙動は意図的に選択しています。' \
    '根拠: ADR-0031です。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --explanation-only \
    --body-file "$body_file"

  [ "$status" -eq 0 ]
  ! grep -Fq 'pulls/42/commits' "$MOCK_LOG"
  grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve tolerates comments whose author was deleted" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n\n%s\n' \
    '確認しました。挙動を確認しました。' \
    '根拠: ADR-0031です。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="null-author" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --explanation-only \
    --body-file "$body_file"

  [ "$status" -eq 0 ]
  grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "reply-resolve requires an explicit fix commit or explanation-only mode" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n' '任意の返信です。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --body-file "$body_file"

  [ "$status" -eq 2 ]
  [[ "$output" == *"one of the arguments --commit --explanation-only is required"* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test "reply-resolve rejects a fix reply without the Japanese evidence template" {
  body_file="$BATS_TEST_TMPDIR/reply.md"
  printf '%s\n' '対応しました。' >"$body_file"

  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" \
    python3 "$SCRIPT" reply-resolve \
    --repo owner/repo \
    --pr 42 \
    --thread-id PRRT_1 \
    --commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --body-file "$body_file"

  [ "$status" -eq 2 ]
  [[ "$output" == *"fix replies must use"* ]]
  ! grep -Fq 'addPullRequestReviewThreadReply' "$MOCK_LOG"
  ! grep -Fq 'resolveReviewThread' "$MOCK_LOG"
}

@test "inspect paginates comments within each review thread" {
  run env PATH="$MOCK_BIN:$PATH" MOCK_LOG="$MOCK_LOG" MOCK_SCENARIO="comment-pages" \
    python3 "$SCRIPT" inspect --repo owner/repo --pr 42

  [ "$status" -eq 0 ]
  run jq -e '
    .review_threads[0].comments.nodes | map(.body) == ["first", "second"]
  ' <<<"$output"
  [ "$status" -eq 0 ]
  grep -Fq 'cursor=NEXT' "$MOCK_LOG"
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

  for guidance in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md"; do
    grep -Fq '`gh-address-comments`' "$guidance"
    grep -Fq '`gh-review-thread`' "$guidance"
    grep -Fq 'Review Round' "$guidance"
  done

  grep -Fq '**Review Round**' "$PROJECT_ROOT/CONTEXT.md"
  grep -Fq '`gh-address-comments`' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq '`gh-review-thread`' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq '`--explanation-only`' "$PROJECT_ROOT/runtime/skill-harness.md"

  local adr="$PROJECT_ROOT/docs/adr/0031-automate-review-round.md"
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
