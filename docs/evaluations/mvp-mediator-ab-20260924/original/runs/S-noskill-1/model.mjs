// Pure model of the search-binding's display-gating logic.
//
// Scope: NOT a reimplementation of React Query. Query still owns fetch,
// retry, caching and the AbortController/signal. This module models only the
// piece that needs a correctness proof: which in-flight request is allowed
// to write to the displayed result, given that requests overlap, the same
// text can be re-entered, and cancellation is best effort.
//
// State shape:
//   seq        - id of the newest issued request (monotonic counter)
//   pending    - true until the request with id === seq has settled
//   status     - 'idle' | 'pending' | 'success' | 'error'
//   data       - payload of the last applied success (null otherwise)
//   error      - payload of the last applied failure (null otherwise)
//   tooltipOpen- independent UI flag, never touched by search events
//
// Design choices (stated, not hidden):
//   - Identity is `seq`, never the search text. Re-entering identical text
//     issues a new seq and is not deduped against the earlier in-flight one.
//   - Previous `data`/`error` stay visible while a new request is `pending`
//     (stale-while-revalidate style); only a SETTLED for the current `seq`
//     replaces them.
//   - A failure of the current request clears `data` (there is no
//     "keep last good data on error" behavior here — that's a UX variant,
//     add it if product wants it).
//   - CANCEL is recorded as a side-effect signal only (fire-and-forget
//     abort()); it is a no-op on this state, because abort is best effort
//     and must never be treated as proof the older request stopped.

export const initialState = () => ({
  seq: 0,
  pending: false,
  status: 'idle',
  data: null,
  error: null,
  tooltipOpen: false,
});

export function reduce(state, event) {
  switch (event.type) {
    case 'SEARCH': {
      // Caller's job (outside this pure model): mint this seq, call
      // query.fetch(text, { signal }) keyed so the seq disambiguates the
      // request, and best-effort abort() the previous in-flight controller.
      const seq = state.seq + 1;
      return { ...state, seq, pending: true, status: 'pending' };
    }
    case 'CANCEL': {
      // Best-effort abort signal only. Never changes displayed state and
      // never marks anything settled — the real settle (if it still lands)
      // is what decides, via the seq check in SETTLED.
      return state;
    }
    case 'SETTLED': {
      if (event.seq !== state.seq) return state; // stale: drop unconditionally
      return event.ok
        ? { ...state, pending: false, status: 'success', data: event.data, error: null }
        : { ...state, pending: false, status: 'error', error: event.error, data: null };
    }
    case 'TOOLTIP_OPEN':
      return { ...state, tooltipOpen: true };
    case 'TOOLTIP_CLOSE':
      return { ...state, tooltipOpen: false };
    default:
      throw new Error(`unknown event: ${event.type}`);
  }
}

// ---------------------------------------------------------------------------
// Self-check
// ---------------------------------------------------------------------------
import assert from 'node:assert/strict';

function permutations(arr) {
  if (arr.length <= 1) return [arr];
  const out = [];
  for (let i = 0; i < arr.length; i++) {
    const rest = [...arr.slice(0, i), ...arr.slice(i + 1)];
    for (const p of permutations(rest)) out.push([arr[i], ...p]);
  }
  return out;
}

function run(name, fn) {
  fn();
  console.log(`ok - ${name}`);
}

run('overlapping searches: only the newest settle updates the result', () => {
  let s = initialState();
  s = reduce(s, { type: 'SEARCH' }); // seq 1, "cat"
  s = reduce(s, { type: 'SEARCH' }); // seq 2, "catdog" — issued before seq1 settled
  assert.equal(s.seq, 2);
  assert.equal(s.pending, true);
  s = reduce(s, { type: 'SETTLED', seq: 1, ok: true, data: 'stale-cat-results' });
  assert.equal(s.pending, true, 'stale settle must not clear pending for the still-outstanding newest request');
  assert.equal(s.data, null, 'stale settle must not reach the display');
  s = reduce(s, { type: 'SETTLED', seq: 2, ok: true, data: 'catdog-results' });
  assert.equal(s.pending, false);
  assert.equal(s.data, 'catdog-results');
});

run('re-entering identical text still gets a fresh id, not deduped by text', () => {
  // The model takes no text at all — SEARCH only ever mints a new seq — which
  // is itself the point: two SEARCH events for the same text produce two
  // distinct ids, so a same-text re-issue can never be conflated with the
  // earlier in-flight one purely by looking at this state.
  let s = initialState();
  s = reduce(s, { type: 'SEARCH' }); // "cat", seq 1
  s = reduce(s, { type: 'SEARCH' }); // "cat" again, seq 2
  assert.equal(s.seq, 2);
  s = reduce(s, { type: 'SETTLED', seq: 1, ok: true, data: 'old-cat-results' });
  assert.equal(s.data, null, 'seq1 result must not surface even though the text is identical to seq2');
  s = reduce(s, { type: 'SETTLED', seq: 2, ok: true, data: 'new-cat-results' });
  assert.equal(s.data, 'new-cat-results');
});

run('cancellation is a no-op signal; correctness never depends on it', () => {
  let s = initialState();
  s = reduce(s, { type: 'SEARCH' }); // seq 1
  const beforeCancel = s;
  s = reduce(s, { type: 'CANCEL', seq: 1 }); // best-effort abort() fired
  assert.deepEqual(s, beforeCancel, 'CANCEL must not alter displayed state');
  s = reduce(s, { type: 'SEARCH' }); // seq 2, still outstanding
  // The "cancelled" request answers anyway — server didn't actually stop.
  s = reduce(s, { type: 'SETTLED', seq: 1, ok: true, data: 'should-never-show' });
  assert.equal(s.pending, true, 'seq2 is still outstanding; pending must stay true');
  assert.equal(s.data, null, 'the post-cancel straggler must still be dropped by the seq check alone');
});

run('tooltip state is independent of search state, in both directions', () => {
  let s = initialState();
  s = reduce(s, { type: 'TOOLTIP_OPEN' });
  s = reduce(s, { type: 'SEARCH' });
  assert.equal(s.tooltipOpen, true, 'issuing a search must not close the tooltip');
  s = reduce(s, { type: 'SETTLED', seq: 1, ok: false, error: 'boom' });
  assert.equal(s.tooltipOpen, true, 'a search failure must not touch the tooltip');
  s = reduce(s, { type: 'TOOLTIP_CLOSE' });
  assert.equal(s.status, 'error', 'closing the tooltip must not touch search status');
  assert.equal(s.error, 'boom');
});

run('exhaustive arrival order: display only ever reflects the newest request', () => {
  // Two fixed scenarios so both failure directions are covered:
  //   A: seq3 (newest) succeeds, while seq1/seq2 are a mix of ok/fail —
  //      proves a stale failure arriving after/around the newest success
  //      can never turn the display into an error.
  //   B: seq3 (newest) fails, while seq1/seq2 succeed —
  //      proves a stale success can never overwrite the newest failure,
  //      and that a genuine newest-request failure IS displayed.
  const scenarios = [
    { outcomes: [{ ok: true, v: 'r1' }, { ok: false, v: 'e2' }, { ok: true, v: 'r3-final' }] }, // stale failure must not surface as error
    { outcomes: [{ ok: true, v: 'r1' }, { ok: true, v: 'r2' }, { ok: false, v: 'e3-final' }] }, // stale success must not overwrite the real error; newest failure IS shown
  ];

  for (const { outcomes } of scenarios) {
    const settleEvents = outcomes.map((o, i) => ({
      type: 'SETTLED',
      seq: i + 1,
      ok: o.ok,
      ...(o.ok ? { data: o.v } : { error: o.v }),
    }));

    for (const order of permutations(settleEvents)) {
      let s = initialState();
      s = reduce(s, { type: 'SEARCH' });
      s = reduce(s, { type: 'SEARCH' });
      s = reduce(s, { type: 'SEARCH' }); // seq becomes 3, the newest
      assert.equal(s.pending, true);

      let newestSettled = false;
      for (const ev of order) {
        s = reduce(s, ev);
        if (ev.seq === 3) newestSettled = true;
        assert.equal(s.pending, !newestSettled, `pending must track only whether seq3 has settled (order=${JSON.stringify(order.map(e => e.seq))})`);
      }

      const final = outcomes[2]; // seq3's outcome, regardless of arrival order
      if (final.ok) {
        assert.equal(s.status, 'success');
        assert.equal(s.data, final.v);
        assert.equal(s.error, null);
      } else {
        assert.equal(s.status, 'error');
        assert.equal(s.error, final.v);
        assert.equal(s.data, null);
      }
    }
  }
});

console.log('all checks passed');
