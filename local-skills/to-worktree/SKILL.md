---
name: to-worktree
description: "Select and validate the runtime-owned task worktree before starting a workflow chain."
disable-model-invocation: true
---

# to-worktree

Use this universal **Worktree Entry Point** once at the start of a workflow chain. Complete it
when the runtime owns one validated linked worktree and every later phase will run in that same
checkout, or when the current session has stopped with an explicit fresh-session command.

The next phase depends on the task:

- Requirements undetermined: `grill-with-docs → to-spec → to-tickets → implement → to-pr`
- Requirements decided: `implement → to-pr`
- Bug requiring diagnosis: `diagnosing-bugs → code-review → to-pr`

## Establish the task context

1. Derive a short kebab-case topic and a Conventional branch name from the user's request. Ask
   only when that choice would materially change the task.
2. Inspect the target repository's physical top level, current `HEAD`, status, current Git dir,
   Git common dir, and `git worktree list --porcelain`. These are read-only facts.
3. Leave every parent change untouched: do not stash, clean, reset, stage, or copy uncommitted
   files. Base a new worktree on the caller `HEAD`. Do not fetch.
4. Reuse only the current linked worktree. A same-topic worktree at any other path is a conflict;
   report its path and stop instead of entering it or creating a duplicate.

## Route to the Worktree Owner

Evaluate these branches in order.

- **Existing linked worktree** — when the current repository has a worktree-specific Git dir
  distinct from its Git common dir, validate it idempotently and continue there. Do not create a
  nested worktree. This is the only reusable checkout.
- **Orca** — use the current Orca worktree when the existing-worktree branch applies. Otherwise,
  invoke the `orca-cli` skill, load its version-matched guide, and use native worktree creation and full handoff through Orca. Do not hardcode Orca CLI commands here. After the handoff succeeds,
  report the destination and stop the original session; the destination session validates its
  current worktree before continuing.
- **Codex Desktop** — use its native worktree flow. Once Codex has selected the native worktree,
  validate that checkout through the existing-worktree branch and continue there.
- **Claude Code** — use `EnterWorktree` when the target is the session repository. Let Claude own
  creation and entry, then validate the resulting current checkout before continuing.
- **raw Codex CLI** — request one scoped approval for exactly the new-worktree creation command:

  ```bash
  git worktree add .worktrees/<topic> -b <type>/<topic> HEAD
  ```

  After it succeeds, report the absolute path and branch, tell the user to start `codex-worktree`
  from that path, and stop. The fresh session performs Worktree Activation; the current session
  does not edit, commit, push, or continue the workflow in the new checkout.

- **Unknown runtime** — identify the missing Worktree Owner and stop. Do not guess a manual Git or
  permission-bypass path.

## Validation boundary

Before continuing to the next phase, confirm that the current checkout is a linked worktree and
that shell/tool working directories resolve inside its physical top level. A primary checkout,
non-Git directory, detached metadata pointer, or unresolved Git dir/common dir fails closed.

Worktree creation is the owner's responsibility. Worktree Activation for raw Codex is the
`codex-worktree` Runtime Adapter's responsibility. This skill does not widen permissions, run
routine manual-shell Git in place of the workflow, clean up worktrees, or publish changes.
