# Hierarchy Repair

Use this branch only when the linked issue has no native parent and its bounded
`## Parent` section declares exactly one valid issue in the current repository. Complete
the repair before Parent Reconciliation so the existing native-only Ticket Coverage and
parent-completion rules remain the only reconciliation path.

## Discover the direct-child candidates

Capture every issue in the repository with GraphQL cursor pagination:

```bash
gh api graphql --paginate --slurp \
  -F owner='{owner}' \
  -F name='{repo}' \
  -f query='
    query($owner: String!, $name: String!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        issues(first: 100, after: $endCursor) {
          nodes { id number body parent { id number } }
          pageInfo { hasNextPage endCursor }
        }
      }
    }'
```

The repository `issues` connection excludes pull requests. Preserve all returned pages;
`--slurp` emits an array of page objects, so flatten every page's `nodes` before matching.
Do not impose a fixed issue-count limit.

For each issue, bound the Parent section from the `## Parent` heading to the next level-two
heading or end of body. The **direct-child candidates** are every open or closed issue whose
bounded section contains exactly one valid reference and resolves to the same parent as the
linked issue. Do not infer relationships from prose outside that section.

Re-read the parent and every direct-child candidate from GitHub before the first mutation,
using the same `gh issue view` fields listed under **Verify and return the native hierarchy**.
The preflight succeeds only when the parent exists as an issue, the current linked issue is
in the candidate set, every candidate still contains the same unambiguous body parent, and
each candidate's native parent is either absent or already the target parent.

If the parent or any candidate cannot be re-read, a Parent section is missing, invalid, or
ambiguous, the current linked issue is absent, or a candidate has a **different native parent**,
abort the whole repair before mutation. A relationship already attached to the target parent
is valid and needs no mutation; a different parent is a conflict, never a reparent request.

## Add the complete candidate set

Keep candidates already attached to the target parent and add **every missing edge** with
the GraphQL `addSubIssue` mutation. Set `replaceParent: false` explicitly:

```bash
gh api graphql \
  -F parentId='<parent-node-id>' \
  -F childId='<candidate-node-id>' \
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
    }'
```

Apply this mutation to every missing edge in the validated set before Parent Reconciliation.
This batch boundary prevents the current linked issue from making the parent appear complete
while a body-declared sibling remains outside the native hierarchy.

On any mutation failure, stop adding edges. GitHub does not make multiple `addSubIssue`
mutations atomic, so a failed repair can be partially successful; preserve those additions
and do not remove or reparent them.

## Verify and return the native hierarchy

After all additions, and also after any mutation failure, re-read every candidate and the
parent:

```bash
gh issue view <candidate> --json number,state,body,parent
gh issue view <parent> --json number,state,body,subIssues,subIssuesSummary
```

Verification succeeds only when every candidate reports the target as its native parent and
the parent's direct `subIssues` contains every candidate. Use that re-fetched native snapshot
for Ticket Coverage and Parent Reconciliation; the body-declared candidate set is not a second
reconciliation source.

Any pagination, preflight, mutation, or verification failure records Parent Reconciliation as `未実施`.
Include the failed issue numbers and reasons in the PR body and completion report,
omit the parent `Fixes` reference, preserve the linked issue's ordinary `Fixes` reference, and
continue creating the PR. A partially successful repair is still a verification failure until
every candidate appears on both sides of the native hierarchy.
