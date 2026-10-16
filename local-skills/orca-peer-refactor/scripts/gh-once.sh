#!/usr/bin/env bash
# gh-once.sh: create an issue or post the run report at most once per run.
#
# usage: gh-once.sh issue  <run-id> <candidate-id> <title> <body-file>
#        gh-once.sh report <run-id> <issue-number> <body-file>
#
# Every write carries a marker "<!-- auto-run:<run-id> <key> -->" (key = cand:<id>
# or report). The marker is looked up BEFORE the write and again after a failed
# write, so a response lost after the server succeeded finds the artifact instead
# of creating a duplicate. List reads are used, not search: search is eventually
# consistent and could miss a just-created issue.
#
# stdout: issue number (issue) | the report comment's issue number (report)
# exit: 0 done (created or already there) | 1 write failed and a lookup confirmed
# no artifact exists (the caller may resend) | 2 usage | 3 a lookup itself failed,
# so whether the artifact exists is unknown (never resend; report it unconfirmed)
set -euo pipefail

kind=${1:-}
case $kind in
issue) [ $# -eq 5 ] || kind= ;;
report) [ $# -eq 4 ] || kind= ;;
*) kind= ;;
esac
[ -n "$kind" ] || {
  echo "usage: $0 issue <run-id> <cand-id> <title> <body-file> | report <run-id> <issue-number> <body-file>" >&2
  exit 2
}

run=$2
if [ "$kind" = issue ]; then
  marker="<!-- auto-run:$run cand:$3 -->"
  title=$4 body=$5
  lookup() {
    # ponytail: newest 1000 issues only; paginate if a repo ever outgrows it
    gh issue list --state all --limit 1000 --json number,body |
      jq -r --arg m "$marker" '[.[] | select(.body | contains($m)) | .number] | first // empty'
  }
  write() { gh issue create --label ready-for-agent --title "$title" --body-file "$tmp" >/dev/null; }
else
  marker="<!-- auto-run:$run report -->"
  target=$3 body=$4
  [[ $target =~ ^[0-9]+$ ]] || {
    echo "issue-number must be numeric: $target" >&2
    exit 2
  }
  lookup() {
    gh issue view "$target" --json comments |
      jq -r --arg m "$marker" --arg t "$target" 'if any(.comments[]; .body | contains($m)) then $t else empty end'
  }
  write() { gh issue comment "$target" --body-file "$tmp" >/dev/null; }
fi

found=$(lookup) || exit 3
[ -z "$found" ] || {
  echo "$found"
  exit 0
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  cat "$body"
  printf '\n%s\n' "$marker"
} >"$tmp"

write || true
found=$(lookup) || exit 3
[ -n "$found" ] || exit 1
echo "$found"
