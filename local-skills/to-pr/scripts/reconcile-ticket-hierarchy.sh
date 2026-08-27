#!/usr/bin/env bash

set -euo pipefail

readonly INPUT_FILE="${1:-}"

if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
  printf '%s\n' 'usage: reconcile-ticket-hierarchy.sh <input-json-file>' >&2
  exit 64
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' 'required command is unavailable: jq' >&2
  exit 69
fi

if ! jq -e '
  (.linkedIssue | type == "number" and . > 0 and floor == .)
  and (.hierarchy | type == "object")
  and (.hierarchy.status | type == "string")
  and (.hierarchy.reason | type == "string")
  and (.coveredIssues | type == "array")
  and all(.coveredIssues[]; type == "number" and . > 0 and floor == .)
' "$INPUT_FILE" >/dev/null; then
  printf '%s\n' 'invalid Parent Reconciliation input' >&2
  exit 65
fi

jq -ce '
  def positive_integer: type == "number" and . > 0 and floor == .;
  def issue_state: . == "OPEN" or . == "CLOSED";
  def unique_sorted: unique | sort;
  def fixes($numbers): [$numbers[] | "Fixes #\(.)"];
  def ordinary($linked; $state; $reason; $failed):
    {
      state: $state,
      reason: $reason,
      uncoveredIssues: [],
      failedIssues: $failed,
      closeTargets: {children: [$linked], parent: [], all: [$linked]},
      fixes: fixes([$linked])
    };

  . as $input
  | $input.linkedIssue as $linked
  | $input.hierarchy as $hierarchy
  | ($input.coveredIssues | unique_sorted) as $covered
  | if $hierarchy.status == "target-none" then
      ordinary($linked; "対象なし"; $hierarchy.reason; [])
    elif $hierarchy.status == "failed" then
      ordinary($linked; "未実施"; $hierarchy.reason; ($hierarchy.failedIssues // []))
    elif ($hierarchy.status == "repaired" or $hierarchy.status == "ready") then
      if (
        ($hierarchy.reason | type) != "string"
        or ($hierarchy.snapshot.parent.number | positive_integer | not)
        or ($hierarchy.snapshot.parent.state | issue_state | not)
        or ($hierarchy.snapshot.children | type) != "array"
        or (all($hierarchy.snapshot.children[]; (.number | positive_integer) and (.state | issue_state)) | not)
        or ([$hierarchy.snapshot.children[].number] | length) != ([$hierarchy.snapshot.children[].number] | unique | length)
        or ([$hierarchy.snapshot.children[] | select(.number == $linked)] | length) != 1
        or any($hierarchy.snapshot.children[]; .number == $hierarchy.snapshot.parent.number)
      ) then
        error("invalid verified hierarchy snapshot")
      else
        ($hierarchy.snapshot.children | map(select(.state == "OPEN" and (.number as $number | $covered | index($number) | not))) | map(.number) | unique_sorted) as $uncovered
        | if ($uncovered | length) > 0 then
            ordinary(
              $linked;
              "未実施";
              "open direct children lack Ticket Coverage: \($uncovered | map("#\(.)") | join(", "))";
              []
            )
            | .uncoveredIssues = $uncovered
          else
            ($hierarchy.snapshot.children | map(select(.state == "OPEN" and (.number as $number | $covered | index($number) != null))) | map(.number) | unique_sorted) as $children
            | (if $hierarchy.snapshot.parent.state == "OPEN" then [$hierarchy.snapshot.parent.number] else [] end) as $parent
            | ($children + $parent) as $all
            | {
                state: "確認済み",
                reason: "all direct children are closed or covered",
                uncoveredIssues: [],
                failedIssues: [],
                closeTargets: {children: $children, parent: $parent, all: $all},
                fixes: fixes($all)
              }
          end
      end
    else
      error("hierarchy is not ready for Parent Reconciliation")
    end
' "$INPUT_FILE"
