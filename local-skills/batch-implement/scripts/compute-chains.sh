#!/usr/bin/env bash
# ---
# topics: [ticket-chain, graph, batch-implement]
# source: human
# ---
# compute-chains.sh
#
# Groups tickets connected by "blocked by" edges into Ticket Chains
# (see CONTEXT.md: a chain gets one worktree/branch and one `to-pr` call),
# and orders each chain's tickets with blockers first (Kahn's algorithm).
#
# A ticket with a still-open blocker outside this batch is not implementable
# this run (implementing it now would base it on work that isn't on the
# default branch yet — the exact stacking problem this skill exists to
# prevent). This script excludes such a ticket, and every ticket that
# transitively depends on it within the batch, rather than trusting a caller
# to have filtered them out beforehand.
#
# Input (stdin): TSV, one ticket per line:
#   issue<TAB>comma-separated in-batch blocker numbers (empty if none)<TAB>external-open-blocker (an issue number, empty if none)
#
# A blocker id in the second column with no entry of its own in this batch is
# a caller error (not a pass-through no-op): it is silently dropped from
# grouping rather than raising a hard error, so pass only in-batch blocker
# ids there. A blocker that is out of the batch and already closed is simply
# omitted entirely (it is satisfied and never appears in either column).
#
# Output (stdout): TSV, one of two shapes per line:
#   chain_id<TAB>order_in_chain<TAB>issue      (implementable, ordered blockers-first)
#   SKIP<TAB>issue<TAB>reason                  (not implementable this run)
# where reason is `external-open-blocker:<n>` (this ticket's own external
# blocker) or `blocked-by-excluded:<n>` (an in-batch blocker was itself
# excluded).
#
# A cycle among implementable tickets (should not happen for well-formed
# tickets) is reported on stderr and that group's remaining, unorderable
# tickets are omitted from stdout rather than emitted in an arbitrary order.
set -euo pipefail

find_root() {
  local x="$1"
  while [ "${PARENT[$x]}" != "$x" ]; do
    PARENT[$x]="${PARENT[${PARENT[$x]}]}"
    x="${PARENT[$x]}"
  done
  printf '%s\n' "$x"
}

union() {
  local ra rb
  ra="$(find_root "$1")"
  rb="$(find_root "$2")"
  [ "$ra" = "$rb" ] || PARENT[$rb]="$ra"
}

ensure_node() {
  local n="$1"
  if [ -z "${SEEN[$n]+x}" ]; then
    SEEN[$n]=1
    PARENT[$n]="$n"
    ORDER+=("$n")
  fi
}

# `read -r a b c` splits on runs of tab (a bash whitespace-IFS quirk: unlike a
# non-whitespace delimiter such as comma, consecutive tabs are collapsed into
# one, silently dropping an empty middle field — e.g. "C\t\t50" would read
# back as issue=C blocked_by=50 external=(empty) instead of blocked_by=(empty)
# external=50). Split with parameter expansion instead, which never collapses.
split_tsv_line() {
  local line="$1" rest
  TSV_ISSUE="${line%%$'\t'*}"
  if [[ "$line" == *$'\t'* ]]; then
    rest="${line#*$'\t'}"
  else
    rest=""
  fi
  TSV_BLOCKED="${rest%%$'\t'*}"
  if [[ "$rest" == *$'\t'* ]]; then
    TSV_EXTERNAL="${rest#*$'\t'}"
  else
    TSV_EXTERNAL=""
  fi
}

compute_chains() {
  local -A PARENT=() ALL_BLOCKERS=() SEEN=() KNOWN=() EXTERNAL_BLOCKER=()
  local -a ORDER=() RAW_ISSUES=() RAW_BLOCKED=() RAW_EXTERNAL=()
  local issue blocked_by b i blockers line

  # Pass 1: buffer stdin (it can only be read once) and record which issues
  # have their own entry in this batch.
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    split_tsv_line "$line"
    RAW_ISSUES+=("$TSV_ISSUE")
    RAW_BLOCKED+=("$TSV_BLOCKED")
    RAW_EXTERNAL+=("$TSV_EXTERNAL")
    KNOWN[$TSV_ISSUE]=1
  done

  # Pass 2: register every ticket as a node.
  for i in "${!RAW_ISSUES[@]}"; do
    issue="${RAW_ISSUES[$i]}"
    ensure_node "$issue"
    ALL_BLOCKERS[$issue]="${RAW_BLOCKED[$i]}"
    EXTERNAL_BLOCKER[$issue]="${RAW_EXTERNAL[$i]}"
  done

  # Pass 3: union only with blockers that are themselves part of this batch.
  for i in "${!RAW_ISSUES[@]}"; do
    issue="${RAW_ISSUES[$i]}"
    blocked_by="${RAW_BLOCKED[$i]}"
    [ -n "$blocked_by" ] || continue
    IFS=',' read -r -a blockers <<<"$blocked_by"
    for b in "${blockers[@]}"; do
      b="${b//[[:space:]]/}"
      [ -n "$b" ] || continue
      [ -n "${KNOWN[$b]+x}" ] || continue
      union "$issue" "$b"
    done
  done

  # Group issues by component root, preserving input order within each group.
  local -A GROUP_MEMBERS=()
  local -a GROUP_ROOTS=()
  local root

  for issue in "${ORDER[@]}"; do
    root="$(find_root "$issue")"
    if [ -z "${GROUP_MEMBERS[$root]+x}" ]; then
      GROUP_ROOTS+=("$root")
      GROUP_MEMBERS[$root]=""
    fi
    GROUP_MEMBERS[$root]="${GROUP_MEMBERS[$root]} $issue"
  done

  local chain_id=0
  local had_cycle=0
  for root in "${GROUP_ROOTS[@]}"; do
    chain_id=$((chain_id + 1))
    # shellcheck disable=SC2206 # word-splitting is intentional here
    local -a members=(${GROUP_MEMBERS[$root]})
    local -A indegree=() dependents=()
    local m dep

    for m in "${members[@]}"; do
      indegree[$m]=0
      dependents[$m]=""
    done
    for m in "${members[@]}"; do
      if [ -n "${ALL_BLOCKERS[$m]}" ]; then
        IFS=',' read -r -a blockers <<<"${ALL_BLOCKERS[$m]}"
        for b in "${blockers[@]}"; do
          b="${b//[[:space:]]/}"
          [ -n "$b" ] || continue
          # Always true by construction (union() above already merged $m and
          # $b into the same group), guarded anyway for defense in depth.
          case " ${members[*]} " in
          *" $b "*)
            indegree[$m]=$((indegree[$m] + 1))
            dependents[$b]="${dependents[$b]} $m"
            ;;
          esac
        done
      fi
    done

    # Exclusion propagation: seed with tickets that have their own external
    # open blocker, then flood forward along `dependents` (a ticket that
    # depends on an excluded ticket is excluded too), breadth-first.
    local -A EXCLUDED=() EXCLUDE_REASON=()
    local -a excl_queue=()
    for m in "${members[@]}"; do
      if [ -n "${EXTERNAL_BLOCKER[$m]}" ]; then
        EXCLUDED[$m]=1
        EXCLUDE_REASON[$m]="external-open-blocker:${EXTERNAL_BLOCKER[$m]}"
        excl_queue+=("$m")
      fi
    done
    while [ "${#excl_queue[@]}" -gt 0 ]; do
      local cur="${excl_queue[0]}"
      excl_queue=("${excl_queue[@]:1}")
      for dep in ${dependents[$cur]}; do
        if [ -z "${EXCLUDED[$dep]+x}" ]; then
          EXCLUDED[$dep]=1
          EXCLUDE_REASON[$dep]="blocked-by-excluded:$cur"
          excl_queue+=("$dep")
        fi
      done
    done
    for m in "${members[@]}"; do
      [ -n "${EXCLUDED[$m]+x}" ] || continue
      printf 'SKIP\t%s\t%s\n' "$m" "${EXCLUDE_REASON[$m]}"
    done

    local order_index=0
    local -a remaining=()
    for m in "${members[@]}"; do
      [ -n "${EXCLUDED[$m]+x}" ] || remaining+=("$m")
    done
    while [ "${#remaining[@]}" -gt 0 ]; do
      local next="" next_pos=-1 i
      for i in "${!remaining[@]}"; do
        m="${remaining[$i]}"
        if [ "${indegree[$m]}" -eq 0 ]; then
          next="$m"
          # shellcheck disable=SC2034 # read by `unset 'remaining[next_pos]'` below
          next_pos="$i"
          break
        fi
      done
      if [ -z "$next" ]; then
        echo "ERROR: cycle detected in chain rooted at issue $root, skipping remaining: ${remaining[*]}" >&2
        had_cycle=1
        break
      fi
      order_index=$((order_index + 1))
      printf '%s\t%s\t%s\n' "$chain_id" "$order_index" "$next"
      for dep in ${dependents[$next]}; do
        [ -n "${EXCLUDED[$dep]+x}" ] && continue
        indegree[$dep]=$((indegree[$dep] - 1))
      done
      unset 'remaining[next_pos]'
      remaining=("${remaining[@]}")
    done
  done

  [ "$had_cycle" -eq 0 ]
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  compute_chains
fi
