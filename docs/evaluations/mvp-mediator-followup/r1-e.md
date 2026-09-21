# E — exclusive device

## Responsibility

The common UI parent owns this pure transition policy: latest device intent, exclusion, stop/release ordering, and result adoption. Recording and calibration children retain local UI only and send `start` events. `profile` is independent and has no device effect. The existing Effect boundary executes emitted commands, returns typed success/failure events, and owns interruption, defects, and resource lifetime; this model performs no I/O and creates no scheduler.

## Executed checks

`node r1-e.mjs` completed with `all assertions passed`. Worktree-local `node_modules/.bin/oxfmt --check` passed for the module and memo, and worktree-local `node_modules/.bin/oxlint` reported 0 warnings and 0 errors for the module.

- Uninterrupted recording-to-calibration switch emits acquire, stop, release, then acquire, with fresh IDs.
- An acquisition keeps its identity while starts change intent back to its target, producing no duplicate I/O and becoming active on success.
- Stop failure blocks; a start only updates intent; retry emits a fresh stop. Release failure similarly retries only release. A stale completion has no effect, and acquisition failure returns idle.
- Same-owner active start and `profile` both leave the device state/effects unchanged.

## Proposed checks

None for this abstract model. Application integration should separately verify that the Effect boundary maps typed errors, defects, interruption, and Scope-managed release back to the documented completion events.

## Criterion result

| Criterion | Result | Reason |
| --- | --- | --- |
| 1 | ○ | Waiting-phase starts only replace `desired`; the current command/ID continues. The check covers changing back to the acquiring target without duplicate I/O. |
| 2 | ○ | Switches always emit stop then release before acquire; failures enter `blocked`; retry emits only the failed stage. |
| 3 | ○ | IDs increment for every command and completion matches only `operationId`; the stale-completion assertion leaves state unchanged. |
| 4 | ○ | The memo and module keep policy in the pure parent model and emit commands for the Effect execution boundary only. |
| 5 | ○ | `profile` is an explicit no-op; child-local UI has no representation in the shared device state. |
| 6 | ○ | The executable assertions and this memo describe the same cases and distinguish executed from integration-proposed checks. |

## Trace

| Trace         | Status |
| ------------- | ------ |
| Understanding | OK     |
| Planning      | OK     |
| Execution     | OK     |
| Formatting    | OK     |

## Evaluation notes

- Unclear Issue: none.
- Cause: none.
- General Fix Rule: keep the pending command identity separate from latest desired target, and retry only a recorded failed stage.
- Discretionary fill-ins: invalid `start` targets are ignored; idle after acquisition failure clears desired intent; opaque IDs use `device-N`.
- Retries: 3 (one formatting pass; the PATH linter was an incompatible older version; the worktree-local lint required an explicit, scoped style-rule exemption for this compact executable model).
- Target skill SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`.
- References read: `local-skills/mvp-mediator-architecture/SKILL.md`; `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`.
