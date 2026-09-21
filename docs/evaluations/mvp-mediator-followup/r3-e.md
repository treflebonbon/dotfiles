# Exclusive device decision model

`r3-e.mjs` is a pure parent-Mediator decision model. `start` updates the latest intent in every wait phase, while the current command retains its operation ID. A successful acquisition is retained only when it matches that intent; otherwise the model emits `stop`, then `release`, before a new `acquire`.

The parent owns device exclusion, stage retry, and result adoption. The existing Effect boundary executes emitted commands and owns typed expected errors, defects, interruption, and resource lifetime; this model performs no I/O or scheduling. Recording and calibration children own their local UI, and `profile` is independent and returns no state change or effect.

## Executed checks

Ran `node docs/evaluations/mvp-mediator-followup/r3-e.mjs` successfully: `mvp mediator model checks passed`.

| Check | Expected result | Observed result |
| --- | --- | --- |
| Normal acquisition | acquire `recording` ID 1, then active `recording` | matched |
| Latest intent and release retry | intent changes during acquisition and shutdown produce no duplicate I/O; a failed release blocks, a new start only changes intent, retry releases with fresh ID, stale completion is ignored, then calibration acquires with fresh ID | matched |
| Independent profile event | no device state change or effect | matched |

## Proposed checks (not executed)

Run the emitted commands through the app's existing Effect boundary and verify its typed-error, defect, interruption, and Scope cleanup behavior. Also verify that each child View sends only its event to the common parent and keeps local presentation state independent.
