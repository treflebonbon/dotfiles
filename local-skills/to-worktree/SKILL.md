---
name: to-worktree
description: "Set up an isolated git worktree before starting feature work, so the current checkout stays clean. Use at the start of the workflow chain — run /to-worktree first, then begin design with /grill-with-docs or jump straight into implementation."
disable-model-invocation: true
---

# to-worktree

Entry point of the workflow chain
(`to-worktree → grill-with-docs → to-prd → to-issues → triage → implementation → to-pr`).
Isolate the upcoming work in a worktree so the current checkout is never dirtied. Design
artifacts written along the way (`CONTEXT.md`, ADRs) land on the same branch and ride into
the final PR naturally.

## Steps

1. **Pick a topic.** Use the user's stated topic, or propose a short kebab-case slug from
   the conversation and confirm it. Branch name follows Conventional style:
   `feat/<topic>` (or `fix/<topic>` etc. when clearly not a feature).

2. **Handle a dirty working tree.** If `git status` shows uncommitted changes, ask the
   user: stash them, leave them in the current checkout (default), or abort.

3. **Create and enter the worktree.**
   - **Claude Code**: prefer the native `EnterWorktree` tool — it moves the session into
     an isolated worktree and cleans up automatically if unchanged.
   - **Other runtimes** (Codex, Antigravity, plain shell): create it manually and run all
     subsequent commands inside it:

     ```bash
     git worktree add .worktrees/<topic> -b feat/<topic>
     cd .worktrees/<topic>
     ```

   Keep worktrees under `.worktrees/` — this matches the roots the `worktree-gc` skill
   collects, so abandoned worktrees get reclaimed later.

4. **Report and hand off.** Confirm the worktree path and branch, then point to the next
   step: `/grill-with-docs` when the work starts from design, or the ready issue /
   implementation task when the design already exists.

## Notes

- This skill only sets up isolation. It never commits, pushes, or opens PRs — that is
  `/to-pr`'s job at the other end of the chain.
- One worktree per topic. If a worktree for the topic already exists, reuse it instead of
  creating a duplicate.
- Cleanup is out of scope: leftover worktrees are collected by the `worktree-gc` skill.
