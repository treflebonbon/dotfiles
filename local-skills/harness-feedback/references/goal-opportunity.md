# Goal opportunity analysis for harness-feedback

When transcript evidence shows premature completion, repeated user nudges, incomplete validation loops, or checklist drift across a long-running task, add a `Goal opportunity` to the proposed fix. Recommend `/goal` only when the task has one coherent objective and a verifiable stopping condition visible in the conversation through surfaced command output, artifacts, PR state, or checklist evidence.

The recommendation must include:

- Objective.
- Stopping condition.
- Proof command or artifact.
- Constraints.
- Pause/ask conditions.
- Checkpoint progress log.

Do not replace a deterministic instruction fix with `/goal`; use `/goal` as a harness-level guard for autonomy and completion while still proposing the smallest instruction or test fix for the observed deviation.

Recommend `/goal` only as a completion guard up to the next explicit approval gate. It must not bypass plan PR review, merge approval, or any human/GitHub approval gate.
