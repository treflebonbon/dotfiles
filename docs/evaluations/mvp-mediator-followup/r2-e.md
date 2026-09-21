# E — exclusive device

## Responsibility

The common UI parent owns device exclusion, latest-intent selection, and retry policy. Recording and calibration own their local UI only; `profile` is independent. This pure model emits commands for the existing Effect boundary. That boundary executes them and owns typed expected errors, defects, interruption, and resource lifetime; this model creates no scheduler or runtime.

## Executed verification

`node docs/evaluations/mvp-mediator-followup/r2-e.mjs` → `4 assertions passed`.

The named checks are `normalPath`, `latestIntentAndFreshIds`, `releaseBeforeNextAcquireAndRetry`, and `staleAndProfileAreIgnored`. They cover uninterrupted acquisition, target changes back to the in-flight target without duplicate I/O, stop/release ordering with failed-stage-only retry, fresh IDs, stale completion exclusion, and profile independence. Proposed, not executed: integration with the application's actual Effect services and device adapter.

## Frozen criteria

| Criterion | Result | Reason |
| --- | --- | --- |
| 1 | ○ | Every waiting phase accepts `start` as an intent update only; current command and ID remain unchanged. Acquisition success compares its fixed target with the latest intent before either activating or stopping. |
| 2 | ○ | A switch emits `stop`, then `release`, and only release success emits the next `acquire`. Stop/release failure enters `blocked`; `retry` repeats only `failedStage`. |
| 3 | ○ | `nextId` creates a new ID for every stage and retry. Completion must equal `operationId`; stale events return the same state and no effects. |
| 4 | ○ | The model is a pure parent-policy function that returns command data. The memo assigns execution, error classes, interruption, and lifetime to Effect. |
| 5 | ○ | `profile` returns its input state with no effects. Recording/calibration are represented only as parent requests, leaving their local flows out of this device policy. |
| 6 | ○ | The executable model and four Node assertions cover the stated policy; this memo distinguishes executed checks from the proposed adapter integration check. |

## Trace

| Understanding | Planning | Execution | Formatting | | --- | --- | --- | | OK | OK | OK | OK |

Unclear issue: whether an acquisition failure should retain a later, unattempted intent. Cause: “returns idle without auto-retrying” does not specify the observed `desired` value. General fix rule: when a failure must not cause implicit execution, clear the consumed intent; a later `start` is required to create a new acquisition.

Discretionary fill-ins: IDs are strings (`device-N`); invalid targets and unknown events are ignored; `blocked` has no pending operation ID. Retries: 0. Skill SHA-256: `6253f70613454fca7d5dd2c98a3bdab7c3053956651f62e89bf7ab4701cd4211`. References read: `local-skills/mvp-mediator-architecture/SKILL.md`; `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`.
