// Pure model of the search-binding's request-sequencing responsibility.
//
// Scope: only the logic that decides WHICH request's outcome is allowed to
// update the displayed result, plus the independent tooltip state. It does
// not model network execution, caching, debouncing, or React Query itself —
// those stay exactly as they are; this is the gate that sits on top of them.
//
// Design: every submitted search gets a monotonically increasing
// `generation` number, regardless of whether its text repeats an earlier
// search. `currentGeneration` always names the newest submission. A SETTLE
// event (success or failure) is applied to the displayed result only if its
// generation still equals currentGeneration at the time it arrives — settles
// for any older generation are discarded, no matter when they arrive or
// whether a CANCEL was ever issued for them. CANCEL is modeled as a no-op:
// it's a best-effort signal to the fetch layer, and correctness never
// depends on it succeeding.

export function initState() {
  return {
    currentGeneration: 0,
    displayed: { generation: null, status: 'idle', data: null, error: null },
    tooltip: { open: false },
  };
}

export function reduce(state, event) {
  switch (event.type) {
    case 'SUBMIT': {
      const generation = state.currentGeneration + 1;
      return {
        ...state,
        currentGeneration: generation,
        // Keep the last-known-good data visible while the new request is
        // pending (avoids a results flash); only a settle replaces it.
        displayed: { ...state.displayed, generation, status: 'pending', error: null },
      };
    }

    case 'SETTLE': {
      if (event.generation !== state.currentGeneration) {
        // Stale: a newer search has already been submitted. Discard,
        // whether this is a success or a failure, and whether or not we
        // ever asked the fetch layer to cancel it.
        return state;
      }
      return event.outcome.ok
        ? { ...state, displayed: { generation: event.generation, status: 'success', data: event.outcome.data, error: null } }
        : { ...state, displayed: { generation: event.generation, status: 'error', data: state.displayed.data, error: event.outcome.error } };
    }

    case 'CANCEL':
      // Best-effort only; does not prove the server/request actually
      // stopped, so it must not be relied on for correctness. Modeled as a
      // no-op — the SETTLE guard above is what actually protects displayed.
      return state;

    case 'TOOLTIP_OPEN':
      return { ...state, tooltip: { open: true } };
    case 'TOOLTIP_CLOSE':
      return { ...state, tooltip: { open: false } };
    case 'TOOLTIP_TOGGLE':
      return { ...state, tooltip: { open: !state.tooltip.open } };

    default:
      throw new Error(`unknown event: ${event.type}`);
  }
}

export function run(events) {
  return events.reduce(reduce, initState());
}

// Whether a superseded request should actually be cancelled: only if it
// doesn't share the new request's query key. Query cancellation/abort is
// keyed, not per-generation — cancelling a request that shares a key with
// the newest one would abort the newest fetch too (they're the same
// in-flight fetch), which is the same-text re-entry case.
export function shouldCancel(prevKey, nextKey) {
  return prevKey !== nextKey;
}

// ---------------------------------------------------------------------------
// Self-check
// ---------------------------------------------------------------------------
function demo() {
  const assert = (cond, msg) => {
    if (!cond) throw new Error('FAIL: ' + msg);
  };

  // Event lists reused below both for the real reducer and for the
  // mutation check, so out-of-order arrival (stale settle arriving LAST,
  // after the newer one already settled) is the thing actually exercised —
  // not just submission order, which any reducer would get right by luck.
  const scenario1 = [
    { type: 'SUBMIT', text: 'a' },                                       // gen 1
    { type: 'SUBMIT', text: 'b' },                                       // gen 2
    { type: 'SETTLE', generation: 2, outcome: { ok: true, data: 'B' } },
    { type: 'SETTLE', generation: 1, outcome: { ok: true, data: 'A' } },  // stale, arrives last
  ];
  const scenario2 = [
    { type: 'SUBMIT', text: 'a' },                                       // gen 1
    { type: 'SUBMIT', text: 'a' },                                       // gen 2 (re-entry, same text)
    { type: 'SETTLE', generation: 2, outcome: { ok: true, data: 'second-a' } },
    { type: 'SETTLE', generation: 1, outcome: { ok: true, data: 'first-a' } }, // stale, arrives last
  ];
  const scenario3 = [
    { type: 'SUBMIT', text: 'a' },                                       // gen 1
    { type: 'CANCEL', generation: 1 },
    { type: 'SUBMIT', text: 'b' },                                       // gen 2
    { type: 'SETTLE', generation: 2, outcome: { ok: false, error: 'boom' } },
    { type: 'SETTLE', generation: 1, outcome: { ok: true, data: 'A-leaked-through' } }, // stale despite cancel, arrives last
  ];

  // 1. Overlapping searches: older settle arrives after a newer one was
  //    submitted and already settled -> ignored.
  {
    const s = run(scenario1);
    assert(s.displayed.status === 'success' && s.displayed.data === 'B',
      `overlapping: expected B to win, got ${JSON.stringify(s.displayed)}`);
  }

  // 2. Re-entering the same text still gets a fresh generation, and the
  //    earlier occurrence's late settle must not override the later one,
  //    even though the text (and thus any cache/query key) is identical.
  {
    const s = run(scenario2);
    assert(s.displayed.status === 'success' && s.displayed.data === 'second-a',
      `re-entry: expected second-a to win, got ${JSON.stringify(s.displayed)}`);
  }

  // 3. Cancellation is best-effort: cancelling the stale request does not
  //    change the outcome above — the guard is generation equality, not
  //    whether CANCEL was sent or honored.
  {
    const s = run(scenario3);
    assert(s.displayed.status === 'error' && s.displayed.error === 'boom',
      `cancel-is-not-proof: expected gen2 error to win, got ${JSON.stringify(s.displayed)}`);
  }

  // 4. Failure of the newest request must still update displayed (it's not
  //    only success that's allowed through).
  {
    const s = run([
      { type: 'SUBMIT', text: 'a' },
      { type: 'SETTLE', generation: 1, outcome: { ok: false, error: 'network' } },
    ]);
    assert(s.displayed.status === 'error' && s.displayed.error === 'network',
      `newest failure: expected error to apply, got ${JSON.stringify(s.displayed)}`);
  }

  // 5. Tooltip is fully independent: toggling it interleaved with search
  //    events changes nothing about displayed, and search events change
  //    nothing about tooltip.
  {
    const s = run([
      { type: 'SUBMIT', text: 'a' },
      { type: 'TOOLTIP_OPEN' },
      { type: 'SETTLE', generation: 1, outcome: { ok: true, data: 'A' } },
      { type: 'TOOLTIP_CLOSE' },
      { type: 'SUBMIT', text: 'b' },
    ]);
    assert(s.tooltip.open === false, `tooltip: expected closed, got ${JSON.stringify(s.tooltip)}`);
    assert(s.displayed.status === 'pending' && s.displayed.data === 'A',
      `tooltip isolation: search state should be unaffected by tooltip events, got ${JSON.stringify(s.displayed)}`);
  }

  // 6. Mutation check: prove the generation guard is load-bearing, not
  //    incidental. Disable it (SETTLE always applies, like a naive
  //    implementation that just overwrites on every response) and confirm
  //    scenarios 1-3 now regress to the stale, wrong result.
  {
    const settleNoGuard = (state, event) => {
      if (event.type !== 'SETTLE') return reduce(state, event);
      return event.outcome.ok
        ? { ...state, displayed: { generation: event.generation, status: 'success', data: event.outcome.data, error: null } }
        : { ...state, displayed: { generation: event.generation, status: 'error', data: state.displayed.data, error: event.outcome.error } };
    };
    const runNoGuard = (events) => events.reduce(settleNoGuard, initState());

    const s1 = runNoGuard(scenario1);
    assert(s1.displayed.data === 'A',
      `mutation check 1: without the guard expected stale A to win (proving the guard matters), got ${JSON.stringify(s1.displayed)}`);

    const s2 = runNoGuard(scenario2);
    assert(s2.displayed.data === 'first-a',
      `mutation check 2: without the guard expected stale first-a to win, got ${JSON.stringify(s2.displayed)}`);

    const s3 = runNoGuard(scenario3);
    assert(s3.displayed.status === 'success' && s3.displayed.data === 'A-leaked-through',
      `mutation check 3: without the guard expected the cancelled-but-not-actually-stopped request to overwrite the real gen2 error, got ${JSON.stringify(s3.displayed)}`);

    console.log('mutation check: guard disabled -> scenarios 1-3 flip to the wrong (stale) result, as expected');
  }

  // 7. shouldCancel: only cancel a superseded request when its key differs
  //    from the new one's. Same-key re-entry shares Query's in-flight
  //    fetch/abort-signal with the new request, so cancelling it would also
  //    abort the request we want to keep.
  {
    assert(shouldCancel('a', 'b') === true, 'shouldCancel: different keys should cancel');
    assert(shouldCancel('a', 'a') === false, 'shouldCancel: same key (re-entry) must not cancel');
  }

  console.log('all checks passed');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  demo();
}
