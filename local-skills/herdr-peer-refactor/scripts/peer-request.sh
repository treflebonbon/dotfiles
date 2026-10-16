#!/usr/bin/env bash
# peer-request.sh: send one request to a herdr peer, confirm it started, wait,
# and accept completion only from the response file.
#
# usage: peer-request.sh <peer> <req-id> <sha> <workdir> <request-file> [round]
#
# <workdir> must be writable by BOTH this session and the peer (a directory in
# the shared task worktree such as <worktree>/.tmp/peer, which git ignores). A
# session scratch directory can be read-only for the peer's sandbox.
#
# Completion = <workdir>/<req-id>.md exists, its first line is
# "DONE <req-id> <sha>" and it has a non-blank body. An idle/done state from `herdr agent wait` is never
# completion (it does not track turns). Limits come from
# runtime/autonomous-peer-contract.md: 20 min per peer wait, 2 h total waiting
# per candidate, 3 Review Rounds, same failure twice = hold.
#
# State kept in <workdir> so a successor inherits it:
#   waited-s        total seconds waited (saved on every exit, including a signal)
#   round           highest Review Round seen (never goes back down)
#   <req-id>.failures  failure kinds for this request
#   .lock           one helper per workdir (the ledger is read-modify-write)
#
# exit: 0 done | 10 per-peer timeout (stop the original peer's edits, a
# successor may start) | 11 blocked (hold, no retry) | 12 not complete
# (stalled / no valid response file; one re-ask allowed) | 13 hold: same
# failure twice | 14 hold: total wait or Review Round budget exhausted |
# 15 hold: peer state cannot be verified, or another helper holds the workdir |
# 2 usage
set -euo pipefail

PEER_TIMEOUT_S=1200
TOTAL_WAIT_S=7200
MAX_ROUNDS=3
SETTLE_S=${PEER_SETTLE_S:-5}

[ $# -ge 5 ] || {
  echo "usage: $0 <peer> <req-id> <sha> <workdir> <request-file> [round]" >&2
  exit 2
}
peer=$1 id=$2 sha=$3 workdir=$4 request=$5
# The ID becomes a file name that is deleted and written: a path component
# ("../x") would escape <workdir>.
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "usage: <req-id> must match [A-Za-z0-9][A-Za-z0-9._-]*" >&2
  exit 2
}
mkdir -p "$workdir"
resp="$workdir/$id.md"

# Header line plus a non-blank body: a header alone is an interrupted write.
valid() {
  [ -f "$resp" ] && [ "$(head -n1 "$resp")" = "DONE $id $sha" ] &&
    awk 'NR > 1 && /[^[:space:]]/ { found = 1 } END { exit !found }' "$resp"
}
# herdr prints JSON: judge state by the "agent_status" value and errors by the
# "code" value, never by a bare word (a terminal title or path can contain one).
is_blocked() { grep -qE '"code": *"agent_blocked"|"agent_status": *"blocked"' <<<"$1"; }
# A state is trusted only if it parses as JSON: a truncated or garbled body that
# merely contains an idle/working fragment cannot be verified (fail closed; this
# also holds when python3 is missing).
json_ok() { python3 -c 'import json,sys; json.load(sys.stdin)' <<<"$1" >/dev/null 2>&1; }
is_working() { json_ok "$1" && grep -qE '"agent_status": *"working"' <<<"$1"; }
is_ready() { json_ok "$1" && grep -qE '"agent_status": *"(idle|done)"' <<<"$1"; }
# Children must not inherit the lock descriptor (fd 9): a process that outlives
# this helper would otherwise keep the workdir locked.
herdr_cmd() { herdr "$@" 9>&-; }

# One helper per workdir: refuse a duplicate instead of overwriting its ledger.
# The lock is system Perl's flock(2) on fd 9 (macOS has no flock command, ADR-0050).
# It belongs to the open file description, so it outlives the perl process and is
# held by this shell until it exits.
exec 9<>"$workdir/.lock"
lock_rc=0
perl -MFcntl=:flock -e 'open(my $fh, "+<&=", 9) or exit 2; flock($fh, LOCK_EX | LOCK_NB) or exit 1' || lock_rc=$?
if [ "$lock_rc" -eq 1 ]; then
  echo "hold: another peer-request is using $workdir" >&2
  exit 15
elif [ "$lock_rc" -ne 0 ]; then
  echo "hold: cannot take the lock on $workdir (system perl with flock is required)" >&2
  exit 15
fi

# Resume: an earlier run (or a predecessor) already got the response.
if valid; then
  echo "$resp"
  exit 0
fi

# The Review Round only goes up; an omitted argument continues from the saved one.
saved_round=$(cat "$workdir/round" 2>/dev/null || echo 0)
round=${6:-$saved_round}
[ "$round" -ge 1 ] 2>/dev/null || round=1
[ "$round" -ge "$saved_round" ] || round=$saved_round
[ "$round" -le "$MAX_ROUNDS" ] || {
  echo "hold: Review Round $round > $MAX_ROUNDS" >&2
  exit 14
}
echo "$round" >"$workdir/round"

waited_file="$workdir/waited-s"
waited=$(cat "$waited_file" 2>/dev/null || echo 0)
[ "$waited" -lt "$TOTAL_WAIT_S" ] || {
  echo "hold: total wait ${waited}s >= ${TOTAL_WAIT_S}s" >&2
  exit 14
}

start=$(date +%s)
used() { echo $((waited + $(date +%s) - start)); }
# Save the time waited on every exit path, a signal included.
trap 'echo "$(used)" >"$waited_file"' EXIT
trap 'exit 143' TERM INT HUP

hold_blocked() {
  echo "blocked: hold, do not retry" >&2
  exit 11
}
cannot_verify() {
  echo "hold: cannot read the peer state: $(head -c 120 <<<"$1" | tr '\n' ' ')" >&2
  exit 15
}
# The same failure kind twice for this ID = hold, wherever it falls in the log
# (missing, stalled, missing is the second missing). Generic errors differ only
# in their message, so they are one kind. A failure that would allow a re-ask is
# a hold once the total wait is reached.
fail() {
  local detail=$1 code=$2 log="$workdir/$id.failures" kind=$1
  case $kind in error:*) kind=error ;; esac
  [ "$(used)" -lt "$TOTAL_WAIT_S" ] || {
    echo "hold: total wait reached ${TOTAL_WAIT_S}s" >&2
    exit 14
  }
  if grep -qxF -- "$kind" "$log" 2>/dev/null; then
    echo "hold: $kind twice" >&2
    exit 13
  fi
  echo "$kind" >>"$log"
  echo "$detail" >&2
  exit "$code"
}
timed_out() {
  [ "$(used)" -lt "$TOTAL_WAIT_S" ] || {
    echo "hold: total wait reached ${TOTAL_WAIT_S}s" >&2
    exit 14
  }
  fail timeout 10
}
left_ms() { echo $((((PEER_TIMEOUT_S < TOTAL_WAIT_S - waited ? PEER_TIMEOUT_S : TOTAL_WAIT_S - waited) - ($(date +%s) - start)) * 1000)); }

rm -f "$resp" "$resp.part" # a file without a valid header is stale; never trust it

prompt="$(cat "$request")

Request ID: $id
Target SHA: $sha
Write your full reply to the file $resp.part, then rename it to $resp (mv) when it is complete. Its first line must be exactly: DONE $id $sha, followed by the reply body
Do not write the reply anywhere else: if that path is not writable, answer on the terminal with UNWRITABLE $resp and stop.
Then answer on the terminal with only that file path."

set +e
out=$(herdr_cmd agent prompt "$peer" "$prompt" --wait --timeout "$(left_ms)" 2>&1)
rc=$?
set -e

while :; do
  # The file is the primary completion signal: it wins over timeout/blocked text.
  if valid; then
    echo "$resp"
    exit 0
  fi
  is_blocked "$out" && hold_blocked
  if grep -qE '"code": *"agent_prompt_stalled"' <<<"$out"; then fail stalled 12; fi
  if [ "$rc" -ne 0 ] && grep -qE '"code": *"timeout"' <<<"$out"; then timed_out; fi
  [ "$rc" -eq 0 ] || fail "error: $(head -c 200 <<<"$out" | tr '\n' ' ')" 12

  # Returned without a valid response: an old turn may have completed, or the
  # agent is waiting on approval right after idle. Read the real state; a state
  # that cannot be read is held, never treated as "send again".
  state=$(herdr_cmd agent get "$peer" 2>&1) || cannot_verify "$state"
  is_blocked "$state" && hold_blocked
  if ! is_working "$state"; then
    # Only a known idle/done state may lead to a re-ask; unknown, missing or
    # unparsable state cannot be verified and is held.
    is_ready "$state" || cannot_verify "$state"
    # An approval dialog can appear just after idle: look once more, and take a
    # response file that landed in the meantime.
    sleep "$SETTLE_S"
    if valid; then
      echo "$resp"
      exit 0
    fi
    state=$(herdr_cmd agent get "$peer" 2>&1) || cannot_verify "$state"
    is_blocked "$state" && hold_blocked
    if ! is_working "$state"; then
      is_ready "$state" || cannot_verify "$state"
      fail missing 12
    fi
  fi

  [ "$(left_ms)" -gt 0 ] || timed_out
  set +e
  out=$(herdr_cmd agent wait "$peer" --timeout "$(left_ms)" 2>&1)
  rc=$?
  set -e
done
