#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

: "${FAKE_GH_STATE:?}"
: "${FAKE_GH_LOG:?}"
: "${FAKE_GH_REPO:=example/project}"

printf 'argv:%s\n' "$*" >>"$FAKE_GH_LOG"

query=''
number=''
parent_id=''
child_id=''
for argument in "$@"; do
  case "$argument" in
  query=*) query="${argument#query=}" ;;
  number=*) number="${argument#number=}" ;;
  parentId=*) parent_id="${argument#parentId=}" ;;
  childId=*) child_id="${argument#childId=}" ;;
  esac
done

if [[ "$query" == *'addSubIssue'* ]]; then
  parent_number="$(jq -r --arg id "$parent_id" '.[] | select(.id == $id) | .number' "$FAKE_GH_STATE")"
  child_number="$(jq -r --arg id "$child_id" '.[] | select(.id == $id) | .number' "$FAKE_GH_STATE")"
  printf 'add:%s\n' "$child_number" >>"$FAKE_GH_LOG"
  : >"$FAKE_GH_STATE.mutation-attempted"

  if [[ "${FAKE_GH_FAIL_ADD_NUMBER:-}" == "$child_number" ]]; then
    exit 1
  fi

  updated_state="$(mktemp "${TMPDIR:-/tmp}/fake-gh-state.XXXXXX")"
  jq \
    --arg childId "$child_id" \
    --arg parentId "$parent_id" \
    --argjson parentNumber "$parent_number" \
    'map(if .id == $childId then .parent = {id: $parentId, number: $parentNumber} else . end)' \
    "$FAKE_GH_STATE" >"$updated_state"
  mv "$updated_state" "$FAKE_GH_STATE"
  jq -n --argjson parent "$parent_number" --argjson child "$child_number" \
    '{data: {addSubIssue: {issue: {number: $parent}, subIssue: {number: $child}}}}'
  exit 0
fi

if [[ "$query" == *'issues(first: 100'* ]]; then
  printf 'list\n' >>"$FAKE_GH_LOG"
  [[ "${FAKE_GH_FAIL_LIST:-0}" != 1 ]] || exit 1
  [[ " $* " == *' --paginate '* && " $* " == *' --slurp '* ]] || exit 2

  jq --arg repo "$FAKE_GH_REPO" '
    . as $issues
    | [
        range(0; length; 2) as $start
        | {
            data: {
              repository: {
                nameWithOwner: $repo,
                issues: {
                  nodes: $issues[$start:$start + 2],
                  pageInfo: {
                    hasNextPage: ($start + 2 < ($issues | length)),
                    endCursor: (if $start + 2 < ($issues | length) then "cursor-\($start + 2)" else null end)
                  }
                }
              }
            }
          }
      ]' "$FAKE_GH_STATE"
  exit 0
fi

if [[ "$query" == *'subIssues(first: 100'* ]]; then
  phase=preflight
  [[ ! -e "$FAKE_GH_STATE.mutation-attempted" ]] || phase=post
  printf 'subissues:%s:%s\n' "$number" "$phase" >>"$FAKE_GH_LOG"
  [[ " $* " == *' --paginate '* && " $* " == *' --slurp '* ]] || exit 2
  [[ "${FAKE_GH_FAIL_PARENT_VERIFY:-0}" != 1 ]] || exit 1

  jq --argjson number "$number" '
    . as $issues
    | ($issues | map(select(.number == $number)) | first) as $parent
    | [
        {
          data: {
            repository: {
              issue: (
                if $parent == null then null
                else {
                  number: $parent.number,
                  state: $parent.state,
                  subIssues: {
                    nodes: [$issues[] | select(.parent.number? == $number) | {number, state}],
                    pageInfo: {hasNextPage: false, endCursor: null}
                  }
                }
                end
              )
            }
          }
        }
      ]' "$FAKE_GH_STATE"
  exit 0
fi

if [[ "$query" == *'issue(number: $number)'* ]]; then
  phase=preflight
  [[ ! -e "$FAKE_GH_STATE.mutation-attempted" ]] || phase=post
  printf 'read:%s:%s\n' "$number" "$phase" >>"$FAKE_GH_LOG"

  if [[ "$phase" == post && "${FAKE_GH_FAIL_VERIFY_NUMBER:-}" == "$number" ]]; then
    exit 1
  fi
  if [[ "${FAKE_GH_FAIL_READ_NUMBER:-}" == "$number" ]]; then
    exit 1
  fi

  jq --arg repo "$FAKE_GH_REPO" --argjson number "$number" '
    {
      data: {
        repository: {
          nameWithOwner: $repo,
          issue: (map(select(.number == $number)) | first)
        }
      }
    }' "$FAKE_GH_STATE"
  exit 0
fi

printf 'unsupported fake gh call\n' >&2
exit 2
