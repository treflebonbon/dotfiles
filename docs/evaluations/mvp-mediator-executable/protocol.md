# Executable-model experiment

Baseline: `d2966a0`. Target: `local-skills/mvp-mediator-architecture/SKILL.md` and conditional reference. Iter 0: description/body remain consistent. This is a **new experiment**, not a rescore of the earlier memo-only rounds. Preserve the previous failure ledger (lost execution completion; state-specific rules contradict the declared policy).

Fresh gpt-5.6-terra/high executors receive only the target and their scenario. No history, prior reports or parent checker access. Full=1, partial=0.5, absent/incorrect=0; success requires all critical items full. Parent runs the frozen checker and reads the memo independently. Canonical usage metrics only; unavailable remains unavailable. Stop after two clear rounds and an unused holdout, reporting qualitative plateau only when metrics are missing. Do not modify checklists or oracle expectations after seeing outputs. A harness defect is reported separately.

## E — exclusive device (executable)

A React/Effect app has recording and calibration that cannot own a device concurrently; a profile editor is independent. The parent owns exclusion; child flows own local UI. Product policy: latest start request wins during acquisition, stop and release, including returning to an earlier requested target. In-flight work continues with its identity unchanged. After acquisition, keep that owner if it matches latest intent, otherwise stop then release before acquiring the latest target. Stop/release failure blocks new acquisition until explicit retry of the failed stage. Repeated starts in blocked state update intent but do not retry automatically. Acquisition failure returns idle without auto-retrying. Same-owner start in active state is a no-op. Stale completions are ignored.

Deliver a minimal executable **abstract decision model**, plus a short responsibility/verification memo. This is not a replacement Effect runtime: output commands for the existing execution boundary; do not perform I/O. Use only JavaScript and Node built-ins. Export:

- `initial()` -> fresh opaque state.
- `transition(state, event)` -> `{ state, effects }`, without mutating input.
- `observe(state)` -> `{ phase, owner, desired, operationId }`. Phases: `idle`, `acquiring`, `active`, `stopping`, `releasing`, `blocked`. owner/desired are `recording`, `calibration` or null; operationId is the pending execution ID or null. IDs must not be reused within a run.
- Events: `{type:'start', target}`, `{type:'ok', id}`, `{type:'fail', id}`, `{type:'retry'}`, `{type:'profile'}`. Completion applies to the current stage. Unknown/stale events leave state/effects unchanged.
- Effects: `{type:'acquire'|'stop'|'release', target, id}`. Acquisition owns nothing until successful; stopping/releasing/blocked reserve the old owner until successful release. State internals are your choice.

1. [critical] Executable transitions implement latest intent consistently in every waiting phase, including target changes back to the in-flight target, without duplicate I/O.
2. [critical] Stop and release success are required before the next acquire; failure blocks acquisition and explicit retry repeats only the failed stage.
3. Execution IDs survive intent changes, are fresh for new stages/retries, and stale success/failure cannot advance state.
4. Common UI parent owns policy; Effect owns execution, typed errors/defects/interruption/lifetime. The pure model only emits commands and does not invent a scheduler or runtime.
5. Child local flows and the profile editor remain independent; profile events leave device state/effects unchanged.
6. Model, memo and concrete checks agree; run at least one meaningful assertion-based check and report its actual result, separating executed checks from proposed checks.

## B — display-only negative control

Existing React/TanStack Query screen, shared Context read by compound components, no Effect. Format total with the existing formatter and add a local help tooltip which affects no submission/other operation. Project rules retain the architecture. Deliver only a minimal change/verification memo. Application code or a state model is unnecessary.

1. [critical] Retains Query/project architecture; no Effect/Atom adoption or MVP migration.
2. [critical] Keeps the display-only change local; no Mediator/reducer/global state or executable transition model.
3. Keeps multiple Context consumers; no single connector/forwarding requirement.
4. Reuses existing formatter and local tooltip state.
5. Leaves unrelated business/submission logic with its existing owners.
6. Gives proportionate concrete formatting/tooltip behavior checks; does not claim unexecuted app tests passed.

## S — held-out search UI

An existing React/Query screen has a search binding exposing pending/result for each request. Typing issues overlapping searches, including re-entering the same text. Only the newest request's success/failure may update displayed results. A help tooltip is independent. Query cancellation is best effort and does not prove the server stopped. Design the responsibility/event/verification memo and a minimal pure executable model with a self-check (no prescribed model API). Keep Query and its execution facilities; do not introduce Effect. This scenario is not supplied until the plateau check.

1. [critical] Latest request identity, not text equality, governs both success and failure acceptance, including repeated identical text.
2. [critical] Model execution and asserted checks show stale success/failure cannot change newer pending/results; current completion still applies.
3. Reuses the existing binding for execution and ordinary pending/result; identifies only the additional result-acceptance coordination needed.
4. No forced Effect/Atom adoption, custom scheduler or promise that cancellation rolls back server work.
5. Tooltip stays local and unrelated to request policy; UI has one named result-acceptance owner.
6. Memo and model agree, checks are actually run and their limitations stated; no claim of browser/runtime integration coverage.
