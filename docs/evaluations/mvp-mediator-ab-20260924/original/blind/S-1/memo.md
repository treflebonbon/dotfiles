# Search binding: responsibility / event / verification memo

## Problem

The search screen re-issues a query on every keystroke (including re-entering
text the user already typed). Requests overlap and settle out of order.
Cancellation (`AbortController.abort()`) is fire-and-forget from the client's
point of view — it does not prove the server stopped producing a response, so
a "cancelled" request can still settle later. Only the *newest* issued
request may write to the displayed result. A help tooltip is a second,
unrelated piece of UI state that must not be entangled with any of this.

Query (React Query / TanStack Query) is kept as-is: it still owns fetching,
retrying, caching, and `signal`/`cancelQueries`. What's missing — and what
this memo and model add — is the **display gate**: the rule that decides
whether an arriving response is allowed to update what's on screen.

## The trap this is designed to avoid

It's tempting to key the query by text alone: `useQuery(['search', text])`.
That's wrong here: if the user retypes the same text while the earlier
request for that text is still in flight, React Query treats the second call
as the *same* query key and will happily resolve either fetch into that one
cache entry — there is no independent notion of "this particular attempt".
Text equality is not request identity.

The fix: **identity is a monotonically increasing request id (`seq`), minted
by the binding, independent of the text.** The id goes into the query key
(e.g. `['search', text, seq]`) so Query never conflates two attempts, and the
display gate compares `seq`, never text, never cache freshness.

## Responsibilities

| Owner | Responsible for |
|---|---|
| Input handler (binding) | On every change (including a repeat of the previous value), mint the next `seq`, call `query.fetch/refetch` keyed with that `seq`, and best-effort `abort()` the previous in-flight controller. |
| Query (unmodified) | Fetch execution, retry, response caching, exposing `signal` for abort, exposing per-call pending/success/error. Query is not asked to dedupe or gate anything by itself. |
| Display gate (this model) | Owns exactly one number, the `seq` of the newest issued request, plus the last *applied* result. Accepts a `SETTLED(seq, outcome)` event and applies it only if `seq` matches the newest; otherwise silently drops it — including a straggler from a request that was already `abort()`-ed. |
| Tooltip | Its own state (open/closed), owned independently. No search event reads or writes it, and no tooltip event reads or writes search state. |

## Events

- `SEARCH` — user typed (any change, including re-entering prior text). Mints a new `seq`, sets `pending`, does **not** clear the previously displayed `data`/`error` (stale-while-revalidate: the old result stays visible until the new one lands, rather than flashing empty).
- `CANCEL(seq)` — the binding fired `abort()` on a superseded request. Recorded as a signal only; **provably a no-op on displayed state**, because abort success is never guaranteed.
- `SETTLED(seq, ok, payload)` — a request finished, in either order, possibly after being "cancelled". Applied only if `seq` equals the current newest `seq`:
  - `ok` → `status: success`, `data: payload`, `error: null`.
  - not `ok` → `status: error`, `error: payload`, `data: null` (a failure of the newest request clears stale data rather than showing "old-but-confirmed-valid" results next to an error — a deliberate simplification; "keep last good data on error" is a UX variant to add later if wanted).
  - Any other `seq` (older, or a post-cancel straggler) → dropped unconditionally, state unchanged.
- `TOOLTIP_OPEN` / `TOOLTIP_CLOSE` — independent of all of the above.

## Verification matrix

| # | Scenario | Required behavior | Covered by (`model.mjs`) |
|---|---|---|---|
| 1 | Two searches overlap; older settles after newer was issued | Older's result never reaches display; newer's does | `overlapping searches: only the newest settle updates the result` |
| 2 | Same text re-entered while the first request is still in flight | Not deduped by text — gets a new `seq`, old settle still dropped | `re-entering identical text still gets a fresh id, not deduped by text` |
| 3 | A request is cancelled, then a newer one is issued, then the cancelled one answers anyway | `CANCEL` itself changes nothing; the late answer is dropped by the `seq` check alone, not by trusting the abort | `cancellation is a no-op signal; correctness never depends on it` |
| 4 | Tooltip open/close interleaved with searches and failures | Neither state ever touches the other | `tooltip state is independent of search state, in both directions` |
| 5 | A stale **failure** arrives after the newest **success** | Display must stay success, not flip to error | `exhaustive arrival order` scenario A (all 6 permutations) |
| 6 | A stale **success** arrives after the newest **failure** | Display must stay the error, not get overwritten | `exhaustive arrival order` scenario B (all 6 permutations) |
| 7 | The newest request itself fails | The failure **is** shown (this is not "errors are always suppressed") | `exhaustive arrival order` scenario B, final state |
| 8 | `pending` flag correctness under any arrival order | `pending` is true iff the newest `seq` has not yet settled — checked after every event, not just at the end | asserted inside the `exhaustive arrival order` loop, both scenarios × all orders |

`exhaustive arrival order` issues 3 overlapping requests and replays all 6
possible arrival orders of their settle events, for two outcome
assignments (newest = success, newest = failure). That is a stronger
guarantee than hand-picked orderings: the final displayed state is asserted
to depend only on the newest request's outcome, never on arrival order.

## Running the check

```
$ node model.mjs
ok - overlapping searches: only the newest settle updates the result
ok - re-entering identical text still gets a fresh id, not deduped by text
ok - cancellation is a no-op signal; correctness never depends on it
ok - tooltip state is independent of search state, in both directions
ok - exhaustive arrival order: display only ever reflects the newest request
all checks passed
```

Exit code 0. `node:assert/strict` throws (nonzero exit) on any regression.
