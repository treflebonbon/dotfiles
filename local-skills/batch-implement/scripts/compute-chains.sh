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
# This script only groups and orders — it trusts its input completely. A
# blocker id with no entry of its own in the input is treated as already
# satisfied and ignored for grouping purposes. The caller (see SKILL.md
# step 2) is responsible for only ever passing a blocker id here when that
# blocker is either in the batch, or closed; a blocker that is out of the
# batch AND still open makes its dependent unimplementable this run, and
# the caller must drop that dependent from the input entirely rather than
# passing it here with the still-open blocker omitted.
#
# Input (stdin): TSV, one ticket per line:
#   issue<TAB>comma-separated blocked-by issue numbers (empty if none)
#
# Output (stdout): TSV, grouped and ordered:
#   chain_id<TAB>order_in_chain<TAB>issue
#
# A cycle (should not happen for well-formed tickets) is reported on stderr
# and that group's remaining, unorderable tickets are omitted from stdout
# rather than emitted in an arbitrary order.
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

compute_chains() {
  local -A PARENT=() ALL_BLOCKERS=() SEEN=() KNOWN=()
  local -a ORDER=() RAW_ISSUES=() RAW_BLOCKED=()
  local issue blocked_by b i blockers

  # Pass 1: buffer stdin (it can only be read once) and record which issues
  # have their own entry in this batch.
  while IFS=$'\t' read -r issue blocked_by || [ -n "$issue" ]; do
    [ -n "$issue" ] || continue
    RAW_ISSUES+=("$issue")
    RAW_BLOCKED+=("$blocked_by")
    KNOWN[$issue]=1
  done

  # Pass 2: register every ticket as a node.
  for i in "${!RAW_ISSUES[@]}"; do
    issue="${RAW_ISSUES[$i]}"
    ensure_node "$issue"
    ALL_BLOCKERS[$issue]="${RAW_BLOCKED[$i]}"
  done

  # Pass 3: union only with blockers that are themselves part of this batch.
  # A blocker with no entry of its own is out of scope (e.g. already merged
  # in an earlier run) and is treated as already satisfied.
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

    local order_index=0
    local -a remaining=("${members[@]}")
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
