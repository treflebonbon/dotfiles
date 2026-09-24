---
name: batch-implement
description: 'Drive every ready-for-agent ticket under a parent (epic) issue to completion, one Ticket Chain at a time, until each chain has produced exactly one main-based PR (or been reported as incomplete/blocked). Invoke explicitly (e.g. "実装可能な issue の PR がすべて作成されるまで" batch-driven from a to-tickets run) — do not trigger automatically, since invocation itself authorizes the AFK-style `to-pr` call each completed chain makes.'
disable-model-invocation: true
---

# batch-implement

Drives `to-tickets` output to completion: every ready-for-agent ticket under one parent issue ends up in exactly one PR against the real default branch, never stacked on another ticket's unmerged branch. This skill only adds the piece existing skills don't cover — grouping tickets into **Ticket Chains** (see `CONTEXT.md`) and assigning one worktree per chain with an explicit base. It does not reimplement `implement` / `tdd` / `code-review` / `to-pr`; it hands each chain to a fresh child agent session that invokes them itself (`implement` refuses direct invocation from another skill and its workflow may not be replicated by other means).

Out of scope: anything not under the given parent issue, parallel processing of independent chains (chains are handed off one at a time, in sequence — see step 3), and re-polling for tickets created after this run started. One pass over the current snapshot of children is the whole job.

## 1. Scope

Take a parent (epic) issue number as input. If none was given, ask for one — do not sweep the whole repository's `ready-for-agent` backlog.

- Prefer native sub-issues: `gh issue view <parent> --json subIssues --jq '.subIssues[].number'`.
- If empty, fall back to searching open issues labeled `ready-for-agent` whose body declares `## Parent` pointing at this parent, and read each candidate's body to confirm (do not guess from title/search snippets alone).
- If native sub-issues and body-declared parents disagree, stop and report the discrepancy — do not guess which is authoritative (same caution as `to-pr`'s Hierarchy Repair).
- Keep only tickets that are still **open** and carry `ready-for-agent`. A closed child is already done; exclude it.
- Exclude a ticket that already has an open PR referencing it (e.g. `gh pr list --search "#<n>" --state open`) — it is mid-progress from an earlier `batch-implement` run. Report it as already-in-progress rather than re-implementing it.

The result is the batch: the fixed set of ticket numbers this run will process. Tickets opened under this parent after this point are out of scope for this run.

## 2. Compute Ticket Chains

For each ticket in the batch, read `gh issue view <n> --json body,number` and extract the `## Blocked by` references. Use the native blocking/tracked-by relation when the platform exposes one; otherwise parse the `## Blocked by` section text for issue numbers.

A blocker reference falls into one of three cases:

- **In the batch**: keep it as an edge for grouping.
- **Not in the batch, but closed** (`gh issue view <b> --json state`): already satisfied — drop the edge, it does not join the two tickets into the same chain.
- **Not in the batch, and still open**: the blocked ticket is **not implementable this run** — implementing it now would base it on work that doesn't exist on the default branch yet, recreating the exact stacking problem this skill exists to prevent. Exclude that ticket (and anything in the batch transitively blocked by it) from the batch, and report it as skipped with the still-open blocker's number.

Feed one line per surviving ticket to the bundled script, `issue<TAB>comma-separated in-batch blocker numbers` (a blocker already resolved by the second case above is simply omitted from that ticket's list):

```bash
bash <skill-directory>/scripts/compute-chains.sh <<'EOF'
101
102	101
103	101,102
EOF
```

Output is `chain_id<TAB>order_in_chain<TAB>issue`, grouped by connected component and ordered blockers-first within each chain (a ticket with no in-batch blocker is its own chain of size 1). A non-zero exit with `cycle detected` on stderr means the batch's declared dependencies are contradictory — report it and skip that chain's tickets rather than guessing an order; unaffected chains still proceed.

## 3. Hand off each chain to a fresh agent, in order

`implement` is reserved for explicit invocation and cannot be called from within this skill, directly or by replicating its steps. Each chain is instead handed to its own fresh, disposable agent session, which invokes `implement` and `to-pr` itself exactly as a human would. Process chains one at a time (in the order the script emitted chain ids) — do not start the next chain's session until the current one is done.

1. **Resolve and fetch the real base** — do not rely on the current checkout's local branch, which may be stale, and never rely on the current checkout's HEAD, which may still be sitting on a previous chain's unmerged branch:

   ```bash
   default_ref="$(git ls-remote --symref origin HEAD | awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }')"
   default_branch="${default_ref#refs/heads/}"
   git fetch origin "$default_branch"
   ```

   Use `origin/$default_branch` (or, if the worktree tool requires a local branch name, fast-forward one first: `git fetch origin "$default_branch:$default_branch"`) as the base in the next step — always the just-fetched tip, never an existing local branch that might predate it.

2. **Create one fresh worktree for this chain**, explicitly passing the resolved, fetched ref as the base — never omit it and never let the tool default to "current HEAD" (this was the root cause of non-main PRs: a worktree created without an explicit base silently branches off whatever the previous chain's loop iteration left checked out). For Herdr: `herdr worktree create --branch <name> --base <resolved-ref> ...` (check `herdr worktree create --help` for the exact current flags); for another native mechanism, use its equivalent explicit-base argument per `runtime/skill-harness.md`'s Worktree Entry Point. Name the branch after the chain's first (most-blocking) ticket, following the existing `task/<N>-<slug>` convention. Note the pane it opens for the next step.
3. **Start a fresh agent in that pane and hand off the chain**, per `runtime/skill-harness.md`'s Herdr contract (confirm the agent is recognized and input-ready before handing off):

   ```bash
   herdr agent start <name> --kind <same kind as this session> --pane <pane-id>
   herdr agent prompt <name> "/implement Implement tickets #<n1>, #<n2>, ... in this exact order (each blocks the next) under parent #<parent>. Read each ticket's own issue body for its Contract." --wait --until idle done blocked
   ```

   If the child reaches `blocked` (needs human input it can't resolve on its own) rather than `idle`/`done`, do not treat this as a completed chain — report it as **needs human attention**, leave the pane open, and move to the next chain.

4. **On apparent completion**, read the child's recent output (`herdr agent read <name>` or `herdr pane read`) to judge whether it actually finished the chain (every ticket committed) or stalled/failed partway. This is a judgment call, not a fixed string match — read enough of the transcript to be sure.
   - **Success**: prompt the same session once more, `herdr agent prompt <name> "/to-pr" --wait --until idle done blocked`, then read its output for the resulting PR (number/URL). Handing this chain to a fresh session via `batch-implement` is itself the AFK-style completion authorization for this one `to-pr` call — the same authorization `to-pr` already documents for AFK operation, scoped here to chains that actually finished. It does not authorize anything `to-pr` itself doesn't authorize (no force-push, no direct default-branch push, no merge, no close/reopen).
   - **Failure** (a ticket in the chain didn't converge through `tdd`/`code-review`): do not prompt `/to-pr` — a partial chain has no clean acceptance-criteria story. Record the chain as incomplete with the failing ticket and reason, leave its worktree/branch/pane as-is for a human to inspect, and move on to the next chain. Do not stop the whole run for one chain's failure.

## 4. Report

When every chain has been attempted, report: for each chain, its tickets, and one of — the resulting PR (number/URL, confirmed base = the resolved default branch), incomplete (failing ticket + reason), needs human attention (blocked state), or skipped (still-open out-of-batch blocker, from step 2). A chain that isn't a clean success keeps its worktree/branch/pane around for inspection — do not delete or close it as part of this skill.
