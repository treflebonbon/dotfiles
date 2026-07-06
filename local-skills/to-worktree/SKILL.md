---
name: to-worktree
description: "Set up an isolated git worktree before starting feature work, so the current checkout stays clean. Use at the start of the workflow chain — run /to-worktree first, then begin design with /grill-with-docs or jump straight into implementation."
disable-model-invocation: true
---

# to-worktree

Entry point of every workflow chain. Which chain follows depends on the scenario:

- Requirements undetermined: `to-worktree → grill-with-docs → to-prd → to-issues → triage`
- Requirements already decided: `to-worktree → tdd → code-review → to-pr`
- Bug fix: `to-worktree → diagnosing-bugs → code-review → to-pr`

Isolate the upcoming work in a worktree so the current checkout is never dirtied. Design
artifacts written along the way (`CONTEXT.md`, ADRs) land on the same branch and ride into
the final PR naturally.

## Steps

1. **Pick a topic.** Use the user's stated topic, or propose a short kebab-case slug from
   the conversation and confirm it. Branch name follows Conventional style:
   `feat/<topic>` (or `fix/<topic>` etc. when clearly not a feature).

2. **Handle a dirty working tree.** "Dirty" means anything `git status` reports —
   tracked modifications, staged changes, and untracked files alike. Ask the user: stash
   them (`git stash -u` so untracked files are included), leave them in the current
   checkout (default; leaves every category untouched), or abort. If the user cannot be
   asked (non-interactive run), apply the default and say so in the report.

3. **Create and enter the worktree.** Two paths; pick by precondition, not preference:
   - **`EnterWorktree` tool (Claude Code)** — use it **only when the target repo is the
     session's current repository** (the repo the harness was launched in, not merely the
     shell's cwd). It places the worktree in a harness-managed location
     (`.claude/worktrees/`, also covered by `worktree-gc` roots) and auto-removes it if
     it ends up unchanged. Both properties are fine for normal feature work.
   - **Manual path (other runtimes, a different target repo, or when the worktree must
     persist regardless of changes)**:

     ```bash
     git worktree add .worktrees/<topic> -b feat/<topic>
     cd .worktrees/<topic>
     ```

   When in doubt about which path applies, take the manual path — it is always correct.
   Naming: the worktree directory uses the bare slug (`.worktrees/<topic>`), the branch
   uses the type-prefixed slug (`feat/<topic>`).

   Either location is collected by the `worktree-gc` skill later. Do not edit
   `.gitignore` to hide `.worktrees/` — if the repo doesn't ignore it already, it showing
   up as untracked in the parent checkout is acceptable noise.

4. **Report and hand off.** Confirm the worktree path and branch, then point to the next
   step: `/grill-with-docs` when the work starts from design, or the ready issue /
   implementation task when the design already exists.

## Notes

- This skill only sets up isolation. It never commits, pushes, or opens PRs — that is
  `/to-pr`'s job at the other end of the chain.
- One worktree per topic. If a worktree for the topic already exists, reuse it instead of
  creating a duplicate.
- Cleanup is out of scope: leftover worktrees are collected by the `worktree-gc` skill.
