# Responsibility / verification memo

## Responsibility split

- **Parent (this model, `model.mjs`)**: owns the recording/calibration mutual-exclusion
  decision. Tracks who owns the shared device, what's currently being acquired/stopped/
  released, and what the latest requested target ("desired") is. Emits `acquire`/`stop`/
  `release` commands; never performs I/O itself — the caller (the Effect execution
  boundary) runs those and reports back via `ok`/`fail`.
- **Child flows (recording UI, calibration UI)**: own their own local UI state (progress
  spinners, error banners, etc.) and issue `start` events into the parent. They don't
  decide exclusion — they just ask and observe `phase`/`owner`/`desired`/`operationId`
  via `observe()`.
- **Profile editor**: genuinely independent. It never contends for the device, so the
  `profile` event is a deliberate no-op in every phase — the parent doesn't model it at
  all beyond acknowledging the event exists.

## State representation

Flat record: `phase, owner, opTarget, desired, operationId, failedStage, nextId`. All
fields are strings/null/finite numbers, no nesting — trivially satisfies the "ordinary
data only" contract. `opTarget` only carries meaning during `acquiring` (the target
being acquired, before ownership is confirmed); `owner` is null until acquisition
succeeds and stays populated (reserved) through `stopping`/`releasing`/`blocked` per the
spec's explicit note that those phases "reserve the old owner until successful release."
`nextId` is a plain counter carried in state — no closure/module-global — so id
generation stays pure and auditable.

## Key decision points

- **`start` while `acquiring`/`stopping`/`releasing`/`blocked`**: only updates `desired`,
  no new effect. This is the "latest start wins, in-flight work keeps its identity"
  rule — the running operation's id/target never change underneath it.
- **`ok` while `acquiring`**: this is the single re-evaluation point. If the acquired
  target still matches `desired`, go `active`. Otherwise the parent immediately begins
  unwinding (`stopping` the target it just (briefly) owned) without ever visiting
  `active` — matching "keep that owner if it matches latest intent, otherwise stop then
  release before acquiring the latest target."
- **`ok` while `releasing`**: always proceeds to `acquiring` the *current* `desired`
  (read fresh at that moment), which is what makes "returning to an earlier requested
  target" fall out for free — no special-casing needed, it's just another value of
  `desired`.
- **`fail`**: in `acquiring` → `idle` (owner/desired/operationId all cleared, no
  auto-retry). In `stopping`/`releasing` → `blocked`, recording which stage failed;
  `owner` stays reserved so `retry` knows what to re-issue.
- **Staleness**: `ok`/`fail` are only honored when `event.id === state.operationId`.
  Since `operationId` is `null` whenever there's no pending operation (idle, active,
  blocked), any leftover completion from an already-resolved or superseded operation is
  automatically ignored — no separate "is this stale" branch needed.

## Verification performed

`node model.mjs` runs 8 scenario groups (A–H), each independently seeded from
`initial()`, covering: basic start/acquire/active, same-owner no-op, `profile` no-op,
full owner handoff (stop→release→acquire), intent change mid-acquire including
returning to the earlier target, mismatch discovered only after acquisition succeeds,
stop-failure → blocked → repeated-start-no-retry → explicit `retry` → recovery,
release-failure → blocked → `retry` → recovery, acquisition failure → idle (no
auto-retry), and stale/unknown events (wrong id, unknown type, `retry` outside
`blocked`, completions while idle).

Every transition in every scenario goes through a `checkPure` helper that: snapshots
the input state, calls `transition` once, asserts the input wasn't mutated, snapshots
that result, calls `transition` again with the *same original* state/event, asserts the
input still wasn't mutated, and asserts the second result is structurally equal to the
first (so no closure/global could silently make it nondeterministic). It also collects
every emitted effect id per run and asserts none is reused within that run.

Actual output:

```
$ node model.mjs
OK: all self-checks passed. 22 effect ids issued across all runs, none reused within a run.
```

Exit code 0.
