# Hierarchy Repair

Use this branch only when the linked issue has no native parent. Run the deterministic
repair helper before Parent Reconciliation:

```bash
HIERARCHY_REPAIR_RESULT="$(mktemp "${TMPDIR:-/tmp}/to-pr-hierarchy.XXXXXX")"
bash <skill-directory>/scripts/repair-ticket-hierarchy.sh <linked-issue-number> \
  >"$HIERARCHY_REPAIR_RESULT"
jq . "$HIERARCHY_REPAIR_RESULT"
```

The helper models expected GitHub and validation failures as a JSON result with exit
status zero so PR creation can continue. A nonzero exit means the helper itself could
not run; handle it as `status: failed`. Interpret its JSON `status` as follows:

- `repaired`: use only the returned, re-fetched native `snapshot` for Ticket Coverage
  and Parent Reconciliation.
- `target-none`: record Parent Reconciliation as `対象なし`; there is no body Parent
  declaration to repair.
- `native-present`: a native parent appeared since the first read. Re-enter the native
  hierarchy path in the main skill and cross-check the body declaration.
- `failed`: record Parent Reconciliation as `未実施` using `failedIssues` and `reason`.

## Canonical body parent

Bound `## Parent` from that exact level-two heading to the next level-two heading or end
of body. Exactly one such heading and exactly one reference occurrence are required. The
only accepted reference forms are `#<positive-decimal-issue-number>` and the canonical
same-repository URL
`https://github.com/<current-owner>/<current-repo>/issues/<positive-decimal-issue-number>`.
Markdown list or link punctuation may surround the reference. Duplicate occurrences,
multiple references, `owner/repo#N`, non-positive numbers, noncanonical or
other-repository issue URLs, and multiple `## Parent` headings are invalid. Prose outside
the bounded section is never a hierarchy source.

The helper uses the linked issue's single canonical body parent to find the
**direct-child candidates**. It captures every open or closed repository issue with
GraphQL cursor pagination, flattens every returned page, and selects issues with the same
single canonical body parent. GitHub's repository `issues` connection excludes pull requests.
The current linked issue must be in the candidate set.

## Safety and completion boundary

The helper re-reads the parent and every direct-child candidate before the first mutation.
It requires the parent to exist, every candidate still to declare the same
body parent, and every candidate's native parent to be absent or the target parent. A
candidate with a **different native parent**, or any missing, ambiguous, changed, or
unavailable issue, must abort the whole repair before mutation.

The only permitted mutation is `addSubIssue` with `replaceParent: false`, applied in
issue-number order to **every missing edge** in the prevalidated candidate set. Existing
edges remain untouched. The helper never edits issue bodies, state, labels, assignees,
or parent relationships and never removes or reparents a sub-issue.

On a mutation failure, stop adding edges. GitHub does not make multiple mutations
atomic, so a repair can be partially successful. Preserve additions already made; a
partially successful repair is still a failure.

After all additions, and also after any mutation failure, the helper performs two-sided
post-mutation verification: it re-reads every child and cursor-paginates the parent's
native sub-issues. Success requires every candidate to report the target parent and the
parent to list every candidate. Only a successful `repaired` result may proceed to the
existing native-only Ticket Coverage and Parent Reconciliation path.

For any pagination, preflight, mutation, or verification failure, record Parent
Reconciliation as `未実施`. Include the failed issue numbers and reasons in the PR body
and completion report, omit the parent `Fixes` reference, preserve the linked issue's
ordinary `Fixes` reference, and continue creating the PR.
