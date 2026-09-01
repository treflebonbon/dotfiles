---
name: to-worktree
description: "Select and validate the non-Orca runtime-owned task worktree before starting a workflow chain."
disable-model-invocation: true
---

# to-worktree

Use this **Worktree Entry Point** outside Orca once at the start of a workflow chain. Orca fulfills
the same entry contract by creating or selecting an Orca native worktree and launching its built-in
agent from the Agent Picker. Orca owns that agent's permission mode; do not replace the built-in
launch with a repository Runtime Adapter. Complete this skill when the non-Orca runtime owns one
validated linked worktree and every later phase will run in that same checkout, or when the current
session has stopped with an explicit fresh-session command.

The next phase depends on the task:

- Requirements undetermined: `grill-with-docs → to-spec → to-tickets → implement → to-pr`
- Requirements decided: `implement → to-pr`
- Bug requiring diagnosis: `diagnosing-bugs → code-review → to-pr`

## Guard Orca before repository inspection

Before running any Git command, use runtime-provided session context for runtime self-identification
and determine whether the current session is running in Orca. Never infer this from `ORCA_*`
environment variables.

- If it identifies an Orca primary checkout, tell the user to create or select an Orca native
  worktree and start a new agent session there, then stop before repository inspection.
- If it identifies an Orca native linked worktree, continue with the read-only inspection and
  validation below.
- If it identifies Orca but cannot classify the current checkout, fail closed and stop before
  repository inspection.
- If runtime self-identification is unavailable, identify the missing Worktree Owner and stop
  before repository inspection.
- If it identifies one of the non-Orca Worktree Owners listed below, continue to establish the task
  context. For any other runtime, identify the missing Worktree Owner and stop before repository
  inspection.

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
  nested worktree. This is the only reusable checkout, including when this skill was invoked by
  mistake inside Orca. In that Orca case, keep the built-in agent launch and its Orca-owned
  permission mode; do not relaunch the agent through `codex-orca` or `codex-worktree`.
- **Orca guard** — when the preflight identified an Orca native linked worktree but the
  existing-worktree branch did not apply, report the session-context and Git-metadata mismatch and
  stop. Keep the current checkout unchanged. Do not invoke Orca CLI or raw Git to create or enter a
  replacement worktree. Do not probe `ORCA_*` environment variables to classify the runtime.
- **Codex Desktop** — use its native worktree flow. Once Codex has selected the native worktree,
  validate that checkout through the existing-worktree branch and continue there.
- **Claude Code** — use `EnterWorktree` when the target is the session repository. Let Claude own
  creation and entry, then validate the resulting current checkout before continuing.
- **raw Codex CLI** — request one scoped approval for exactly the new-worktree creation command:

  ```bash
  git -C <physical-top-level> worktree add <physical-top-level>/.worktrees/<topic> -b <type>/<topic> HEAD
  ```

  Complete this branch only after that one command succeeds with the same absolute physical top level for `-C` and the destination.
  Report the absolute path and branch, tell the user to start `codex-worktree` from that path, and
  stop. The fresh session performs Worktree Activation; the current session does not edit, commit,
  push, or continue the workflow in the new checkout.

- **Unknown runtime** — identify the missing Worktree Owner and stop. Do not guess a manual Git or
  permission-bypass path.

## Validation boundary

Before continuing to the next phase, confirm that the current checkout is a linked worktree and
that shell/tool working directories resolve inside its physical top level. A primary checkout,
non-Git directory, detached metadata pointer, or unresolved Git dir/common dir fails closed.

Worktree creation and built-in agent launch are Orca's responsibility in Orca. Worktree Activation
for raw Codex is the `codex-worktree` Runtime Adapter's responsibility. This skill does not widen
permissions, run routine manual-shell Git in place of the workflow, clean up worktrees, or publish
changes.
