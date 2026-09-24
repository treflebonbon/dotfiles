# Device-exclusion decision model — responsibility & verification memo

## Responsibility split

- **This model (parent)** owns device exclusion and current/desired intent only. It is a pure
  function of `(state, event) -> {state, effects}`; it performs no I/O.
- **Recording / calibration child flows** own their own local UI and behavior; they only ever
  see the machine through `start`/`ok`/`fail` and `observe()`. Their internal state is out of
  scope here.
- **Profile editor** is independent of device exclusion by product policy. The `profile` event
  is therefore an identity transition in every phase — it never reads or changes owner/desired.
- **Execution boundary (existing Effect runtime)** is the only thing that touches real
  hardware/APIs. It executes `acquire`/`stop`/`release` effects and reports completion via
  `ok`/`fail` carrying the effect's `id`. This model never calls it directly — it only emits
  effect descriptions.

## State shape (flat, no nested objects/arrays)

`{ phase, owner, desired, operationId, pendingTarget, stage, nextId }`

- `pendingTarget` / `stage` are internal bookkeeping not exposed by `observe()`: the target and
  effect-type of the current in-flight operation, or of the operation that failed while
  `blocked` (so `retry()` knows what to reissue).
- `nextId` is a monotonic counter carried in `state` (not a closure/module global) so IDs are
  never reused within a run, per the purity contract.

## Interpretive choices (flag if these don't match intent)

1. **Acquisition failure → idle resets `desired` to `null`**, discarding whatever intent had
   accumulated during the failed acquisition. Read literally, "returns idle" means the full
   idle shape (owner/desired both null); the caller must re-issue `start` for anything it still
   wants. Verified by walk-invariant `idle: desired === null` and scenario 20 (fail after
   intent diverged mid-acquire → idle, no leftover acquire fired).
2. **No short-circuit on "returning to an earlier target."** If desired flips back to the
   reserved owner while stopping/releasing, the model still finishes stop → release → acquire
   instead of cancelling back to `active`. This follows directly from "in-flight work continues
   with its identity unchanged" — only intent (`desired`) is updated mid-flight, never the
   in-flight operation itself. Verified by scenario 19.
3. **Blocked + start(reserved owner) stays blocked** until an explicit `retry`; it does not
   auto-resolve just because desired now matches the reserved owner. Verified by scenario in
   steps 9-10 (main chain: blocked with desired flipped back to owner, still requires retry).
4. **`retry` outside `blocked` is a no-op** (nothing failed to retry). **Same-target `start`**
   while `acquiring`/`stopping`/`releasing`/`blocked` is also a no-op (idempotent intent update).
5. **`ok`/`fail` are matched to the current stage only by `operationId`**; a stale id (including
   one for an already-superseded stop, after a retry reissued it under a new id) is always
   ignored, regardless of phase. Verified by scenario 21.

## Verification

`model.test.mjs`, run with `node model.test.mjs`:

```
OK: 2037 checks passed (functional transitions + purity + representation contract + 2000-step random walk)
```

Coverage:
- **Representation-contract audit** (`assertValidValue`): every state and effects value
  produced is recursively checked against the allowed-type contract (plain objects with only
  own enumerable data properties, dense arrays, null/boolean/string/finite-number) after every
  transition in the suite.
- **Purity** (`checkPure`): for every transition exercised, snapshots the input, calls
  `transition` twice from the same input, snapshots the first result before the second call,
  and asserts (a) the input is byte-for-byte unchanged after each call and (b) the two results
  are structurally equal — so no hidden mutable state (closure/WeakMap/module global) can leak
  between calls.
- **Linear scenario walk** (steps 1-18 + scenarios 19-21): the full product-policy narrative —
  acquire, intent updates mid-acquire (including reverting to an earlier target), same-owner
  no-op, owner switch via stop/release, stop/release failure → blocked → retry, stale
  completions, unknown event types, invalid/missing target, acquisition failure → idle, and the
  "keep owner if it matches intent, otherwise stop+release then acquire" branch after a
  mid-flight diversion.
- **ID uniqueness/monotonicity** (`assertIdRun`): checked per continuous run (the main chain,
  and the random walk) — not pooled across independent/hypothetical branches, since the
  contract only requires uniqueness *within* a run.
- **2000-step seeded random walk** (LCG, test-only, not in the model): drives `transition`
  through random start/ok/fail/retry/profile/unknown/stale-id events and asserts a per-phase
  structural invariant after every step (e.g. `acquiring` never has an owner, `active` always
  has `owner === desired` and no pending op, `stopping`/`releasing` always have
  `owner === pendingTarget`, `blocked` always has `operationId === null`). Every step also runs
  through `checkPure`.

**Limit, stated by the task itself:** these are finite checks (a bounded scenario list plus a
2000-step bounded random walk); they do not *prove* purity or correctness for every possible
execution, only exercise it broadly. No hidden decision state was found on inspection (`grep`
for `WeakMap`/module-level `let`/`var` in `model.mjs` finds none — the counter lives in
`state.nextId`).
