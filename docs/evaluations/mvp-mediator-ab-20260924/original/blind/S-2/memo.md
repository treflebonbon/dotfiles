# Search binding: stale-response guarding

## Problem

The screen's search binding exposes per-request `pending`/`result` (a thin
wrapper around Query). Typing fires overlapping searches — including
re-submitting text already searched — and Query's cancellation on
superseding a request is best-effort: it may reduce work, but a cancelled
request can still resolve. Any fix must not assume cancellation succeeded.

## Responsibilities

| Owner | Responsibility |
|---|---|
| **Query (unchanged)** | Executes each request, retries/caches by query key, attempts abort on cancel. Emits pending/success/error per request instance. Not asked to change. |
| **Generation gate (new, thin)** | Assigns a monotonically increasing `generation` to every submitted search, tracks `currentGeneration`, and decides whether an arriving settle (success or error) is allowed to reach the displayed result. |
| **Displayed-result state** | Mutated only by a settle the gate accepted. Holds `status`/`data`/`error` plus the generation being awaited or shown — that field names *which request owns this slot*, not necessarily the generation whose data is currently on screen (while pending it still shows the previous generation's last-known-good data). |
| **Tooltip state** | Fully separate reducer/state slice. No event from the search lifecycle touches it, and no tooltip event touches search state. |
| **Binding (glue)** | On input change: emit `SUBMIT(text)` to the gate, then start the Query call tagged with the generation it returned, guaranteeing exactly one `SETTLE` per `SUBMIT` even on a cache hit or a deduped fetch (so a re-entered cached text never leaves `displayed` stuck in `pending`). Emit `SETTLE(generation, outcome)` from wherever that request's promise resolves/rejects (e.g. around `queryClient.fetchQuery`/`refetch`'s returned promise — not per-hook `onSuccess`/`onError`, which TanStack Query v5 removed from `useQuery`). On superseding a request, call Query's cancel **only if its query key differs from the new request's key** — Query's abort signal is shared by same-key in-flight fetches, so cancelling a same-key predecessor (the re-entry case) would abort the request we want to keep. A cancellation error for the *current* generation must never be surfaced as a failure. |

The gate is a sequencing layer on top of Query, not a replacement for it —
Query keeps owning fetch execution, caching, and cancellation attempts.

## Events

- `SUBMIT(text)` → issues a new generation, becomes `currentGeneration`.
  Fires on every submission, including a re-entry of previously searched
  text — text equality is Query's cache-key concern, not the gate's; the
  gate only cares about submission order.
- `SETTLE(generation, outcome)` → outcome is success(data) or error(error).
  Applied to displayed state **iff** `generation === currentGeneration`;
  otherwise silently discarded, regardless of arrival order or whether a
  cancel was issued for it.
- `CANCEL(generation)` → forwarded to Query as an optimization. Modeled as a
  no-op for correctness: the thing that actually protects displayed state is
  the generation check in `SETTLE`, not whether the cancel took effect.
- `TOOLTIP_OPEN` / `TOOLTIP_CLOSE` / `TOOLTIP_TOGGLE` → independent slice,
  never conditioned on or conditioning search generation.

## Verification (what the self-check in `model.mjs` proves)

All out-of-order scenarios below have the stale (older-generation) settle
arrive *last*, after the newer generation already settled — arrival order,
not submission order, is what the guard has to get right; a reducer that
just "applies settles in submission order" would pass a same-order test for
the wrong reason.

1. **Overlapping searches**: a stale settle arriving after a newer one
   already settled never overwrites it.
2. **Re-entering the same text**: re-submission gets a new generation; an
   earlier occurrence's late settle loses to the later one even though the
   text — and any Query cache key derived from it — is identical.
3. **Cancellation is not proof**: cancelling a request and having its settle
   arrive anyway (after the newer request already settled) still gets
   discarded, because discard is driven by generation mismatch, not by
   whether cancel succeeded.
4. **Failure also gates correctly**: the newest request's *error* outcome
   updates displayed state (the rule is "newest wins," not "success wins").
5. **Tooltip isolation**: interleaving tooltip events with search events
   changes neither slice's outcome.
6. **Mutation check**: re-running scenarios 1-3 through a variant reducer
   with the generation guard deleted (settle always applies) makes all
   three flip to the stale, wrong result. This is the evidence that the
   guard is load-bearing, not incidental — deleting it breaks the checks
   that are supposed to catch its absence.
7. **`shouldCancel`**: cancels a superseded request only when its key
   differs from the new one's (same-key re-entry must not cancel, since it
   would share — and abort — the new request's in-flight fetch).

Out of scope for this model (left to Query, unchanged): actual network
execution, retry/backoff, cache-key design, debounce timing. Those facilities
are kept as-is; only the newest-wins gate, `shouldCancel`, and the binding's
wiring to them are new.

## Run

```
$ node model.mjs
mutation check: guard disabled -> scenarios 1-3 flip to the wrong (stale) result, as expected
all checks passed
```
Verified in this session, exit 0.
