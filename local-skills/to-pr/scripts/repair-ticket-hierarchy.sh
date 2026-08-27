#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

readonly LINKED_ISSUE="${1:-}"

if [[ ! "$LINKED_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'usage: repair-ticket-hierarchy.sh <linked-issue-number>' >&2
  exit 64
fi

for dependency in gh jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'required command is unavailable: %s\n' "$dependency" >&2
    exit 69
  fi
done

candidate_numbers=()
added_numbers=()
failed_numbers=()

numbers_json() {
  if (($# == 0)); then
    printf '[]\n'
    return
  fi

  printf '%s\n' "$@" | jq -cs 'map(tonumber)'
}

emit_result() {
  local status="$1"
  local parent_number="$2"
  local reason="$3"
  local snapshot_json="${4:-null}"
  local candidates_json added_json failures_json parent_json

  candidates_json="$(numbers_json "${candidate_numbers[@]}")"
  added_json="$(numbers_json "${added_numbers[@]}")"
  failures_json="$(numbers_json "${failed_numbers[@]}")"
  if [[ -n "$parent_number" ]]; then
    parent_json="$parent_number"
  else
    parent_json='null'
  fi

  jq -cn \
    --arg status "$status" \
    --argjson parent "$parent_json" \
    --arg reason "$reason" \
    --argjson candidates "$candidates_json" \
    --argjson added "$added_json" \
    --argjson failedIssues "$failures_json" \
    --argjson snapshot "$snapshot_json" \
    '{
      status: $status,
      parent: $parent,
      candidates: $candidates,
      added: $added,
      failedIssues: $failedIssues,
      reason: $reason,
      snapshot: $snapshot
    }'
}

append_failed_number() {
  local number="$1"
  local existing

  for existing in "${failed_numbers[@]}"; do
    [[ "$existing" == "$number" ]] && return
  done
  failed_numbers+=("$number")
}

query_issue() {
  local number="$1"

  gh api graphql \
    -F owner='{owner}' \
    -F name='{repo}' \
    -F number="$number" \
    -f query='
      query($owner: String!, $name: String!, $number: Int!) {
        repository(owner: $owner, name: $name) {
          nameWithOwner
          issue(number: $number) {
            id
            number
            state
            body
            parent { id number }
          }
        }
      }'
}

parse_body_parent() {
  local body="$1"
  local repository="$2"
  local heading_count section url reference_repository reference_number
  local -a references=()

  heading_count="$(printf '%s\n' "$body" | tr -d '\r' | awk '
    /^##[[:space:]]+Parent[[:space:]]*$/ { count += 1 }
    END { print count + 0 }
  ')"

  if [[ "$heading_count" == 0 ]]; then
    return 10
  fi
  if [[ "$heading_count" != 1 ]]; then
    return 11
  fi

  section="$(printf '%s\n' "$body" | tr -d '\r' | awk '
    /^##[[:space:]]+Parent[[:space:]]*$/ { in_parent = 1; next }
    in_parent && /^##([[:space:]]|$)/ { exit }
    in_parent { print }
  ')"

  if grep -Eq '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+' <<<"$section"; then
    return 11
  fi
  if grep -Eq '#[0-9]+[[:alnum:]_/-]' <<<"$section"; then
    return 11
  fi

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if [[ ! "$url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[1-9][0-9]*$ ]]; then
      return 11
    fi
    reference_repository="${url#https://github.com/}"
    reference_repository="${reference_repository%/issues/*}"
    reference_number="${url##*/issues/}"
    if [[ "${reference_repository,,}" != "${repository,,}" ]]; then
      return 11
    fi
    references+=("$reference_number")
  done < <(printf '%s\n' "$section" | grep -oE 'https://github\.com/[^[:space:])>}]+' || true)

  while IFS= read -r reference_number; do
    [[ -n "$reference_number" ]] || continue
    reference_number="${reference_number#*#}"
    [[ "$reference_number" =~ ^[1-9][0-9]*$ ]] || return 11
    references+=("$reference_number")
  done < <(printf '%s\n' "$section" | grep -oE '(^|[^[:alnum:]_/-])#[0-9]+' || true)

  if ((${#references[@]} != 1)); then
    return 11
  fi

  printf '%s\n' "${references[0]}"
}

current_response=''
if ! current_response="$(query_issue "$LINKED_ISSUE" 2>/dev/null)"; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed '' "linked issue #$LINKED_ISSUE could not be read"
  exit 0
fi

repository="$(jq -r '.data.repository.nameWithOwner // empty' <<<"$current_response")"
current_issue="$(jq -c '.data.repository.issue // empty' <<<"$current_response")"
if [[ -z "$repository" || -z "$current_issue" ]]; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed '' "linked issue #$LINKED_ISSUE does not exist in the current repository"
  exit 0
fi

native_parent="$(jq -r '.parent.number // empty' <<<"$current_issue")"
if [[ -n "$native_parent" ]]; then
  emit_result native-present "$native_parent" "linked issue #$LINKED_ISSUE already has native parent #$native_parent"
  exit 0
fi

parent_number=''
parse_status=0
parent_number="$(parse_body_parent "$(jq -r '.body // ""' <<<"$current_issue")" "$repository")" || parse_status=$?
if ((parse_status == 10)); then
  emit_result target-none '' "linked issue #$LINKED_ISSUE has no bounded ## Parent section"
  exit 0
fi
if ((parse_status != 0)); then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed '' "linked issue #$LINKED_ISSUE has an invalid or ambiguous bounded ## Parent section"
  exit 0
fi
if [[ "$parent_number" == "$LINKED_ISSUE" ]]; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed "$parent_number" "linked issue #$LINKED_ISSUE declares itself as its parent"
  exit 0
fi

pages=''
if ! pages="$(gh api graphql --paginate --slurp \
  -F owner='{owner}' \
  -F name='{repo}' \
  -f query='
    query($owner: String!, $name: String!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        issues(first: 100, after: $endCursor) {
          nodes {
            id
            number
            state
            body
            parent { id number }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }' 2>/dev/null)"; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed "$parent_number" 'repository issue pagination failed'
  exit 0
fi

if ! jq -e 'type == "array" and all(.[]; .data.repository.issues.nodes | type == "array")' \
  >/dev/null <<<"$pages"; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed "$parent_number" 'repository issue pagination returned an invalid response'
  exit 0
fi

mapfile -t issue_rows < <(jq -c '[.[].data.repository.issues.nodes[]] | .[]' <<<"$pages")
for issue_row in "${issue_rows[@]}"; do
  issue_number="$(jq -r '.number' <<<"$issue_row")"
  issue_parent=''
  issue_parse_status=0
  issue_parent="$(parse_body_parent "$(jq -r '.body // ""' <<<"$issue_row")" "$repository")" || issue_parse_status=$?
  if ((issue_parse_status == 0)) && [[ "$issue_parent" == "$parent_number" ]]; then
    candidate_numbers+=("$issue_number")
  fi
done

if ((${#candidate_numbers[@]} > 0)); then
  mapfile -t candidate_numbers < <(printf '%s\n' "${candidate_numbers[@]}" | sort -n -u)
fi

current_is_candidate=false
for candidate_number in "${candidate_numbers[@]}"; do
  if [[ "$candidate_number" == "$LINKED_ISSUE" ]]; then
    current_is_candidate=true
    break
  fi
done
if [[ "$current_is_candidate" != true ]]; then
  failed_numbers+=("$LINKED_ISSUE")
  emit_result failed "$parent_number" "linked issue #$LINKED_ISSUE disappeared from the direct-child candidate set"
  exit 0
fi

parent_response=''
if ! parent_response="$(query_issue "$parent_number" 2>/dev/null)" ||
  [[ "$(jq -r '.data.repository.issue.number // empty' <<<"$parent_response")" != "$parent_number" ]]; then
  failed_numbers+=("$parent_number")
  emit_result failed "$parent_number" "declared parent #$parent_number could not be re-read as an issue"
  exit 0
fi
parent_id="$(jq -r '.data.repository.issue.id' <<<"$parent_response")"

missing_numbers=()
missing_ids=()
for candidate_number in "${candidate_numbers[@]}"; do
  candidate_response=''
  if ! candidate_response="$(query_issue "$candidate_number" 2>/dev/null)"; then
    append_failed_number "$candidate_number"
    emit_result failed "$parent_number" "candidate #$candidate_number could not be re-read before mutation"
    exit 0
  fi

  candidate_issue="$(jq -c '.data.repository.issue // empty' <<<"$candidate_response")"
  if [[ -z "$candidate_issue" ]]; then
    append_failed_number "$candidate_number"
    emit_result failed "$parent_number" "candidate #$candidate_number no longer exists"
    exit 0
  fi

  candidate_body_parent=''
  candidate_parse_status=0
  candidate_body_parent="$(parse_body_parent "$(jq -r '.body // ""' <<<"$candidate_issue")" "$repository")" || candidate_parse_status=$?
  if ((candidate_parse_status != 0)) || [[ "$candidate_body_parent" != "$parent_number" ]]; then
    append_failed_number "$candidate_number"
    emit_result failed "$parent_number" "candidate #$candidate_number no longer declares the same single body parent"
    exit 0
  fi

  candidate_native_parent="$(jq -r '.parent.number // empty' <<<"$candidate_issue")"
  if [[ -n "$candidate_native_parent" && "$candidate_native_parent" != "$parent_number" ]]; then
    append_failed_number "$candidate_number"
    emit_result failed "$parent_number" "candidate #$candidate_number has different native parent #$candidate_native_parent"
    exit 0
  fi

  if [[ -z "$candidate_native_parent" ]]; then
    missing_numbers+=("$candidate_number")
    missing_ids+=("$(jq -r '.id' <<<"$candidate_issue")")
  fi
done

mutation_failed=false
mutation_failure_reason=''
for index in "${!missing_numbers[@]}"; do
  candidate_number="${missing_numbers[$index]}"
  candidate_id="${missing_ids[$index]}"
  if ! gh api graphql \
    -F parentId="$parent_id" \
    -F childId="$candidate_id" \
    -f query='
      mutation($parentId: ID!, $childId: ID!) {
        addSubIssue(input: {
          issueId: $parentId
          subIssueId: $childId
          replaceParent: false
        }) {
          issue { number }
          subIssue { number }
        }
      }' >/dev/null 2>&1; then
    append_failed_number "$candidate_number"
    mutation_failed=true
    mutation_failure_reason="addSubIssue failed for candidate #$candidate_number"
    break
  fi
  added_numbers+=("$candidate_number")
done

postverify_failed=false
postverify_reason=''
for candidate_number in "${candidate_numbers[@]}"; do
  candidate_response=''
  if ! candidate_response="$(query_issue "$candidate_number" 2>/dev/null)"; then
    append_failed_number "$candidate_number"
    postverify_failed=true
    postverify_reason="candidate #$candidate_number could not be re-read after mutation"
    continue
  fi

  candidate_issue="$(jq -c '.data.repository.issue // empty' <<<"$candidate_response")"
  if [[ -z "$candidate_issue" ||
    "$(jq -r '.parent.number // empty' <<<"$candidate_issue")" != "$parent_number" ]]; then
    append_failed_number "$candidate_number"
    postverify_failed=true
    postverify_reason="candidate #$candidate_number does not report native parent #$parent_number after mutation"
    continue
  fi

done

parent_pages=''
parent_query_failed=false
if ! parent_pages="$(gh api graphql --paginate --slurp \
  -F owner='{owner}' \
  -F name='{repo}' \
  -F number="$parent_number" \
  -f query='
    query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) {
          number
          state
          subIssues(first: 100, after: $endCursor) {
            nodes { number state }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }' 2>/dev/null)"; then
  append_failed_number "$parent_number"
  parent_query_failed=true
  postverify_failed=true
  postverify_reason="parent #$parent_number sub-issues could not be re-read after mutation"
fi

parent_state=''
native_children='[]'
if [[ "$parent_query_failed" != true ]] &&
  jq -e '
    type == "array"
    and length > 0
    and all(.[]; .data.repository.issue != null)
    and all(.[]; .data.repository.issue.subIssues.nodes | type == "array")
  ' >/dev/null <<<"$parent_pages"; then
  parent_state="$(jq -r '.[0].data.repository.issue.state // empty' <<<"$parent_pages")"

  if [[ "$parent_state" != OPEN && "$parent_state" != CLOSED ]] ||
    ! jq -e --argjson parent "$parent_number" --arg state "$parent_state" \
      'all(.[]; .data.repository.issue.number == $parent and .data.repository.issue.state == $state)' \
      >/dev/null <<<"$parent_pages"; then
    append_failed_number "$parent_number"
    postverify_failed=true
    postverify_reason="parent #$parent_number did not report a valid consistent state after mutation"
  fi

  native_children="$(jq -c \
    '[.[].data.repository.issue.subIssues.nodes[] | {number, state}] | sort_by(.number)' \
    <<<"$parent_pages")"
  if ! jq -e '
    all(.[];
      (.number | type == "number" and . > 0 and floor == .)
      and (.state == "OPEN" or .state == "CLOSED")
    )
    and (map(.number) | length) == (map(.number) | unique | length)
  ' >/dev/null <<<"$native_children"; then
    append_failed_number "$parent_number"
    postverify_failed=true
    postverify_reason="parent #$parent_number returned an invalid native child snapshot after mutation"
  fi

  for candidate_number in "${candidate_numbers[@]}"; do
    if ! jq -e --argjson number "$candidate_number" \
      'any(.[]; .number == $number)' >/dev/null <<<"$native_children"; then
      append_failed_number "$candidate_number"
      postverify_failed=true
      postverify_reason="parent #$parent_number does not list candidate #$candidate_number after mutation"
    fi
  done
elif [[ "$parent_query_failed" != true ]]; then
  append_failed_number "$parent_number"
  postverify_failed=true
  postverify_reason="parent #$parent_number sub-issues returned an invalid response after mutation"
fi

if [[ "$mutation_failed" == true ]]; then
  emit_result failed "$parent_number" "$mutation_failure_reason"
  exit 0
fi
if [[ "$postverify_failed" == true ]]; then
  emit_result failed "$parent_number" "$postverify_reason"
  exit 0
fi

snapshot="$(jq -cn \
  --argjson parent "$parent_number" \
  --arg parentState "$parent_state" \
  --argjson children "$native_children" \
  '{parent: {number: $parent, state: $parentState}, children: $children}')"
emit_result repaired "$parent_number" 'all declared edges and native direct children were verified on both sides' "$snapshot"
