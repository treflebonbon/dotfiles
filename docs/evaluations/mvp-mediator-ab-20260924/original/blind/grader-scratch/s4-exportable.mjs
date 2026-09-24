// Pure model for the search-result adoption arbitration described in the memo.
// No framework, no Query — this only models the decision of which in-flight
// request's outcome is allowed to update the displayed result, plus the
// independent tooltip toggle used to prove it never interferes.
//
// Run: node model.mjs

import assert from 'node:assert/strict';

// ---- pure model -----------------------------------------------------------

function initState() {
  return {
    nextId: 1,
    pending: new Set(), // ids not yet completed (includes superseded ids: a
                         // best-effort cancel does not prove the server
                         // stopped, so we still wait for their completion).
    acceptedId: null,    // id whose own completion may update `adopted`.
    adopted: null,       // { id, outcome } | null — last adopted completion.
    tooltipOpen: false,  // independent View-local display state.
  };
}

function cloneState(s) {
  return {
    nextId: s.nextId,
    pending: new Set(s.pending),
    acceptedId: s.acceptedId,
    adopted: s.adopted ? { id: s.adopted.id, outcome: { ...s.adopted.outcome } } : null,
    tooltipOpen: s.tooltipOpen,
  };
}

// event: {type:'search', text} | {type:'completed', id, outcome} | {type:'toggleTooltip'}
// outcome: {ok:true, value} | {ok:false, error}
function transition(state, event) {
  const next = cloneState(state);
  const effects = [];

  switch (event.type) {
    case 'search': {
      const id = next.nextId;
      next.nextId += 1;
      // Re-entering the same text still gets a fresh id: dedup by domain
      // text would let a stale response for an identical earlier search
      // masquerade as current.
      for (const supersededId of state.pending) {
        effects.push({ type: 'cancel', id: supersededId }); // best effort only
      }
      next.pending.add(id);
      next.acceptedId = id;
      effects.push({ type: 'fetch', id, text: event.text });
      return { state: next, effects };
    }
    case 'completed': {
      if (!state.pending.has(event.id)) {
        return { state: next, effects }; // unknown/already-settled id: no-op
      }
      next.pending.delete(event.id);
      if (event.id === state.acceptedId) {
        next.adopted = { id: event.id, outcome: event.outcome };
        effects.push({ type: 'adopt', id: event.id, outcome: event.outcome });
      } else {
        // Stale/superseded completion: still must be processed for cleanup
        // (release effect), but it may never touch the displayed result.
        effects.push({ type: 'release', id: event.id });
      }
      return { state: next, effects };
    }
    case 'toggleTooltip': {
      next.tooltipOpen = !state.tooltipOpen;
      return { state: next, effects };
    }
    default:
      throw new Error(`unknown event: ${event.type}`);
  }
}

// Derived display: never a separately-written field, always read off state.
function selectDisplay(state) {
  if (state.acceptedId !== null && state.pending.has(state.acceptedId)) {
    return { status: 'pending' };
  }
  if (state.adopted && state.adopted.id === state.acceptedId) {
    return state.adopted.outcome.ok
      ? { status: 'success', value: state.adopted.outcome.value }
      : { status: 'error', error: state.adopted.outcome.error };
  }
  return { status: 'idle' };
}

// ---- verification-only helpers (not part of the model's own API) ---------

function toPlain(x) {
  if (x instanceof Set) return { __set: [...x].sort() };
  if (Array.isArray(x)) return x.map(toPlain);
  if (x && typeof x === 'object') {
    const out = {};
    for (const k of Object.keys(x).sort()) out[k] = toPlain(x[k]);
    return out;
  }
  return x;
}
const snapshot = toPlain;
const assertEqual = (a, b) => assert.deepStrictEqual(toPlain(a), toPlain(b));

// ---- self-check ------------------------------------------------------------

const results = [];
function check(name, fn) {
  try {
    fn();
    results.push([name, 'ok']);
    console.log(`[ok] ${name}`);
  } catch (err) {
    results.push([name, 'FAIL: ' + err.message]);
    console.error(`[FAIL] ${name}`);
    console.error(err);
  }
}

// normalPath: fresh state, one search, its own success completion. No other
// request in flight, so no cancel/stale handling is exercised here.
check('normalPath', () => {
  let state = initState();
  let r = transition(state, { type: 'search', text: 'cat' });
  assertEqual(r.effects, [{ type: 'fetch', id: 1, text: 'cat' }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'pending' });

  r = transition(state, { type: 'completed', id: 1, outcome: { ok: true, value: ['cat photo'] } });
  assertEqual(r.effects, [{ type: 'adopt', id: 1, outcome: { ok: true, value: ['cat photo'] } }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'success', value: ['cat photo'] });
  assertEqual([...state.pending], []);
});

// caseFailure: own completion is a failure — must surface as an error and
// still release the in-flight slot, kept separate from normalPath per the
// case-naming rule.
check('caseFailure', () => {
  let state = initState();
  let r = transition(state, { type: 'search', text: 'dog' });
  state = r.state;
  r = transition(state, { type: 'completed', id: 1, outcome: { ok: false, error: 'network' } });
  assertEqual(r.effects, [{ type: 'adopt', id: 1, outcome: { ok: false, error: 'network' } }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'error', error: 'network' });
  assertEqual([...state.pending], []);
});

// caseReentrySameText: typing "cat", then re-typing "cat" again before the
// first resolves. Same domain text must not be deduped into one request —
// the stale first completion must never override the second.
check('caseReentrySameText', () => {
  let state = initState();
  state = transition(state, { type: 'search', text: 'cat' }).state;
  const idA = 1;
  const rB = transition(state, { type: 'search', text: 'cat' });
  assertEqual(rB.effects, [
    { type: 'cancel', id: idA },
    { type: 'fetch', id: 2, text: 'cat' },
  ]);
  state = rB.state;
  const idB = 2;
  assert.notEqual(idA, idB, 'same text must still get a distinct request id');

  // stale completion for A arrives first
  let r = transition(state, { type: 'completed', id: idA, outcome: { ok: true, value: ['old cat'] } });
  assertEqual(r.effects, [{ type: 'release', id: idA }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'pending' }); // B still outstanding

  // current completion for B arrives
  r = transition(state, { type: 'completed', id: idB, outcome: { ok: true, value: ['new cat'] } });
  assertEqual(r.effects, [{ type: 'adopt', id: idB, outcome: { ok: true, value: ['new cat'] } }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'success', value: ['new cat'] });
});

// caseOutOfOrderStale: search A, then B supersedes A (best-effort cancel of
// A). B's completion arrives first and is adopted; A's completion arrives
// *later* regardless (cancellation is best effort, not proof of server
// stop) and must not clobber B's already-adopted result.
check('caseOutOfOrderStale', () => {
  let state = initState();
  state = transition(state, { type: 'search', text: 'ca' }).state; // id 1
  state = transition(state, { type: 'search', text: 'cat' }).state; // id 2, cancels id 1

  let r = transition(state, { type: 'completed', id: 2, outcome: { ok: true, value: ['cat'] } });
  assertEqual(r.effects, [{ type: 'adopt', id: 2, outcome: { ok: true, value: ['cat'] } }]);
  state = r.state;
  assertEqual(selectDisplay(state), { status: 'success', value: ['cat'] });

  // ---- purity check on this exact transition call, per protocol ----
  const before = snapshot(state);
  const event = { type: 'completed', id: 1, outcome: { ok: true, value: ['ca'] } };
  const first = transition(state, event);
  assertEqual(state, before);
  const firstBefore = snapshot(first);
  const second = transition(state, event);
  assertEqual(state, before);
  assertEqual(first, firstBefore);
  assertEqual(second, firstBefore);

  // and the late/stale A result must never have reached the display
  assertEqual(first.effects, [{ type: 'release', id: 1 }]);
  assertEqual(selectDisplay(first.state), { status: 'success', value: ['cat'] });
});

// caseTooltipIndependence: tooltip open/close must not read or write any
// search-arbitration field, and search/completion must not touch tooltip.
check('caseTooltipIndependence', () => {
  let state = initState();
  state = transition(state, { type: 'search', text: 'owl' }).state;
  const searchFieldsBefore = snapshot({
    nextId: state.nextId, pending: state.pending, acceptedId: state.acceptedId, adopted: state.adopted,
  });

  state = transition(state, { type: 'toggleTooltip' }).state;
  assert.equal(state.tooltipOpen, true);
  assertEqual(
    { nextId: state.nextId, pending: state.pending, acceptedId: state.acceptedId, adopted: state.adopted },
    searchFieldsBefore,
  );

  const tooltipBefore = state.tooltipOpen;
  state = transition(state, { type: 'completed', id: 1, outcome: { ok: true, value: ['owl'] } }).state;
  assert.equal(state.tooltipOpen, tooltipBefore);
});

const failed = results.filter(([, r]) => r !== 'ok');
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
if (failed.length) process.exit(1);

export { initState, transition, selectDisplay };
