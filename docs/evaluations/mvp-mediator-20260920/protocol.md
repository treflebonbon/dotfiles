# MVP Mediator empirical evaluation protocol

- Target: `local-skills/mvp-mediator-architecture/SKILL.md` and its `references/tanstack-effect.md`.
- Baseline: `7302e42d9012b85027976a5c754aea629c620ce3`.
- Executor: fresh `gpt-5.6-terra` / `high` agents, no inherited conversation, one scenario per agent. Subsequent rounds use new agents and the same scenario/checklist.
- Deliverable: a concrete, version-independent architecture/change memo for the supplied application, followed by the prescribed self-report. This evaluates execution of the skill's design/review task, not running application code or autonomous skill discovery.
- Scoring fixed before dispatch: full = 1, partial = 0.5, missing/incorrect = 0. Accuracy = sum / item count. Success only when every critical item is full. Parent grades the deliverable independently of executor self-scores.
- `tool_uses` and `duration_ms` must come from dispatch usage metadata. Missing fields are recorded as unavailable, never reconstructed from tool counts or elapsed clock time. Retries come from executor self-report.
- Stop: two consecutive rounds with no new instruction ambiguity, plus an unused holdout, can establish qualitative plateau. Without usage metadata, strict quantitative convergence remains unverified; use an explicit resource cutoff after that plateau. If a critical failure or new ambiguity appears, apply one-theme minimal fixes and rerun; do not silently change these criteria.

## Iteration 0

Description claims new UI architecture, existing MVP work and competing UI flows, preserves existing architecture, and delegates ROP. Body covers these branches and the reference is conditional on the adopted stack. No description/body mismatch found; no edit before iteration 1. This is a static check, not an execution result.

## Scenario A — median: inventory reservation dialog

A new inventory screen uses React, Effect and an existing UI binding exposing each operation's pending/outcome state. Two panels consume a shared Context. A reservation dialog collects quantity and validates numeric format. Available-stock policy is already owned by the reservation use case. Closing during submission means cancel. The same item can be submitted again after cancel, and old success or failure can arrive later. A background stock refresh must not reset the active submission. Produce a concrete responsibility map, events/transitions and checks, without selecting package versions or writing framework code.

1. [critical] The use case owns and rechecks stock policy at execution; display does not introduce a second stock rule.
2. [critical] Submit/cancel/result acceptance has a named UI owner, and both stale success and failure from a prior same-item attempt cannot overwrite a new attempt.
3. Effect execution/interruption/resource lifetime is delegated; expected errors, defects and interruption remain distinguishable; interruption is not equated with server rollback.
4. Multiple Context consumers and local quantity/format handling are retained without mandatory forwarding components.
5. Reuses existing operation state where equivalent; identifies any extra cancellation/attempt coordination instead of duplicating all fetch state.
6. Gives concrete event/transition checks including background refresh during submission.

## Scenario B — edge: existing Query UI maintenance

An existing React screen uses TanStack Query, a shared Context read by several compound components, and no Effect. Request: format the displayed total with the existing formatter and add a help tooltip. Tooltip open/close does not affect submission or any other operation. Project rules retain this architecture. Produce the minimal change memo: what changes, what stays owned where, and how to verify it. Do not implement application code.

1. [critical] Preserves Query/project architecture; requires no Effect/Atom adoption or MVP migration.
2. [critical] Keeps this display-only change local without adding a Mediator, reducer or global UI state.
3. Keeps multiple Context consumers and does not require a single connector or pass-through hierarchy.
4. Uses the existing formatter and keeps tooltip state local.
5. Does not relocate or rewrite unrelated business/submission logic.
6. Provides proportionate behavior checks for formatting and tooltip behavior.

## Scenario C — edge: mutually exclusive device flows

A React/Effect application has screen recording and camera calibration, which cannot own the device concurrently. Each has its own UI flow. Starting calibration during recording must wait for recording shutdown and device release. Stop or release can fail; repeated start requests can arrive while shutdown is pending. A profile editor on the same screen is independent. Produce a concrete responsibility map, event/state transition table and execution/verification memo. Do not choose Effect API versions or write framework code.

1. [critical] A common parent owns device-flow exclusion; children keep local responsibilities and Views do not stop siblings directly.
2. [critical] Includes pending shutdown and successful release before new acquisition; handles stop/release failure without starting the other flow.
3. Repeated requests during the transition have an explicit, consistent policy; a single owner makes it.
4. Keeps the independent profile flow independent instead of centralizing all UI events globally.
5. Uses Effect execution/lifetime facilities under the parent's policy, without treating Scope closure alone as proof of interruption or inventing a parallel scheduler.
6. Provides concrete checks covering switch, failure and repeat requests.

## Holdout H — saved address and data refresh

An Effect-based address editor stores field values and format validation in a form library. Its existing binding exposes submission pending/result state and permits one outstanding submission. There is no cancel or cross-screen exclusion requirement. A shared address summary subscribes independently, and a background query can refresh saved addresses while a draft is being edited. Produce the minimal architecture memo and behavioral checks, distinguishing draft, persisted data and submit state without prescribing package APIs.

1. [critical] Model/use case owns business validation; form owns draft/format handling.
2. [critical] Background saved-data refresh does not overwrite the editing draft or invent an automatic submission transition.
3. Uses existing submission state without introducing a second equivalent state machine; preserves the existing single-submission constraint.
4. Allows independent read subscriptions without a mandatory single connector.
5. Effect owns execution/lifetime/error handling, with typed errors separate from defects/interruption.
6. Gives checks for refresh while editing, submit failure and successful completion, marking unspecified post-success draft policy as an assumption.
