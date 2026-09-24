// Pure executable model for the search screen's request-adoption rule.
//
// Scope: the Mediator-level decision of *which in-flight search request's
// success/failure may update displayed results*, plus the independent
// tooltip view state. It does NOT reimplement TanStack Query — bindingState
// stands in for "the existing search binding's per-request pending/result",
// and the effects list stands in for calls into Query's own execution
// facilities (issuing a request, best-effort cancel, settlement/cleanup).
//
// No Query/Effect library is used here; this is the plain-data model the
// memo's evidence table is checked against.

import assert from 'node:assert/strict';

// ---- state ---------------------------------------------------------------
//
// state.bindingState : { [requestId]: { status: 'pending'|'success'|'failure', query, data?, error? } }
//   - simulates the existing search binding's own exposed pending/result,
//     one entry per issued request (per the task's "search binding exposing
//     pending/result for each request").
// state.latestId : number|null
//   - the one added Mediator-owned decision: which request id is "newest".
//     Only *this* id's resolution may reach the display.
// state.nextId : number
//   - request id issuance, standing in for the execution facility's own
//     per-invocation identity.
// state.tooltipOpen : boolean
//   - independent View-local state.

function initState() {
  return { nextId: 0, bindingState: {}, latestId: null, tooltipOpen: false };
}

// transition(state, event) -> { state, effects }
// Pure: never mutates `state`; effects are plain data describing what the
// execution layer should do (Query calls / cancel calls), not performed here.
function transition(state, event) {
  switch (event.type) {
    case 'search': {
      const id = state.nextId;
      const effects = [];
      const prev = state.latestId !== null ? state.bindingState[state.latestId] : undefined;
      if (prev && prev.status === 'pending') {
        // Best effort only — does not prove the server stopped, so a stale
        // resolution for this id can still arrive later (see 'resolve').
        effects.push({ type: 'cancelRequest', id: state.latestId });
      }
      effects.push({ type: 'startRequest', id, query: event.query });
      const bindingState = {
        ...state.bindingState,
        [id]: { status: 'pending', query: event.query },
      };
      return { state: { ...state, nextId: id + 1, bindingState, latestId: id }, effects };
    }
    case 'resolve': {
      const entry = state.bindingState[event.id];
      if (!entry) return { state, effects: [] }; // unknown id: nothing to settle
      const updated =
        event.outcome.type === 'success'
          ? { ...entry, status: 'success', data: event.outcome.data }
          : { ...entry, status: 'failure', error: event.outcome.error };
      const bindingState = { ...state.bindingState, [event.id]: updated };
      // Settlement/resource-release happens regardless of whether this id is
      // adopted for display — a discarded stale result still needs cleanup.
      const effects = [{ type: 'requestSettled', id: event.id }];
      return { state: { ...state, bindingState }, effects };
    }
    case 'toggleTooltip': {
      // View-local only: does not read or touch bindingState/latestId.
      return { state: { ...state, tooltipOpen: !state.tooltipOpen }, effects: [] };
    }
    default:
      throw new Error(`unknown event type: ${event.type}`);
  }
}

// Derived display: reads ONLY the latest id's binding entry. This is what
// makes "only the newest request's success/failure may update displayed
// results" hold — a resolve() for any other id changes bindingState but can
// never change what selectDisplay returns.
function selectDisplay(bindingState, coordination) {
  const entry = coordination.latestId === null ? undefined : bindingState[coordination.latestId];
  if (!entry) return { status: 'idle' };
  const display = { status: entry.status, query: entry.query };
  if (entry.status === 'success') display.data = entry.data;
  if (entry.status === 'failure') display.error = entry.error;
  return display;
}

// ---- self-check helpers ---------------------------------------------------

function snapshot(x) {
  return structuredClone(x);
}
function assertEqual(a, b, msg) {
  assert.deepStrictEqual(a, b, msg);
}

// Prescribed purity check : input-state invariance across both
// calls, first-result stability, and same-input/same-output. Every case
// below calls `transition` exclusively through this helper, so every event
// branch actually exercised anywhere in the file is purity-checked, not just
// one hand-picked branch.
function step(state, event) {
  const before = snapshot(state);
  const first = transition(state, event);
  assertEqual(state, before, 'input state must stay unchanged after 1st call');
  const firstBefore = snapshot(first);
  const second = transition(state, event);
  assertEqual(state, before, 'input state must stay unchanged after 2nd call');
  assertEqual(first, firstBefore, 'first result must not have been mutated since');
  assertEqual(second, firstBefore, 'same input must produce the same output');
  return first;
}

const results = []; // { case, ok, detail }
function record(name, fn) {
  try {
    fn();
    results.push({ case: name, ok: true });
    console.log(`[PASS] ${name}`);
  } catch (err) {
    results.push({ case: name, ok: false, detail: err.message });
    console.log(`[FAIL] ${name}: ${err.message}`);
  }
}

// ---- cases -----------------------------------------------------------------
// Every case below calls `transition` only via `step()`, so the prescribed
// purity sequence (input invariance / first-result stability / same-input
// same-output) runs on that exact event in that exact state, for every
// branch touched anywhere in this file: search-without-cancel (normalPath),
// search-with-cancel (staleResolution etc.), resolve-for-latest-id
// (staleResolution's 2nd resolve), resolve-for-stale-id (staleResolution's
// 1st resolve), resolve-for-unknown-id (resolveUnknownId), toggleTooltip
// (tooltipIndependence).

// normalPath: independent case with only a start + its own normal completion.
record('normalPath', () => {
  let state = initState();
  let res = step(state, { type: 'search', query: 'cat' });
  assertEqual(res.effects, [{ type: 'startRequest', id: 0, query: 'cat' }]);
  state = res.state;
  assertEqual(state.latestId, 0);
  assertEqual(selectDisplay(state.bindingState, state), { status: 'pending', query: 'cat' });

  res = step(state, { type: 'resolve', id: 0, outcome: { type: 'success', data: ['Cat'] } });
  assertEqual(res.effects, [{ type: 'requestSettled', id: 0 }]);
  state = res.state;
  assertEqual(selectDisplay(state.bindingState, state), {
    status: 'success',
    query: 'cat',
    data: ['Cat'],
  });
});

// staleResolution: a stale success for the superseded id must not override
// the newer request's display, even though it still gets settled. Also
// covers resolve-for-the-current-latest-id (the 2nd resolve below).
record('staleResolution', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state; // id 0
  const searchRes = step(state, { type: 'search', query: 'dog' }); // id 1
  assertEqual(searchRes.effects, [
    { type: 'cancelRequest', id: 0 },
    { type: 'startRequest', id: 1, query: 'dog' },
  ]);
  state = searchRes.state;
  assertEqual(state.latestId, 1);

  // stale id 0 resolves anyway (best-effort cancel did not prove the server stopped)
  const staleRes = step(state, { type: 'resolve', id: 0, outcome: { type: 'success', data: ['Cat'] } });
  assertEqual(staleRes.effects, [{ type: 'requestSettled', id: 0 }]);
  state = staleRes.state;
  // display still reflects id 1 (pending), unaffected by id 0's stale success
  assertEqual(selectDisplay(state.bindingState, state), { status: 'pending', query: 'dog' });
  assertEqual(state.bindingState[0].status, 'success'); // settled, just not adopted

  // now the newest id resolves and IS adopted
  state = step(state, { type: 'resolve', id: 1, outcome: { type: 'success', data: ['Dog'] } }).state;
  assertEqual(selectDisplay(state.bindingState, state), {
    status: 'success',
    query: 'dog',
    data: ['Dog'],
  });
});

// newestFirstThenStaleFailure: the ordering that would visibly break the
// screen if unhandled — the newest request succeeds FIRST, then a stale
// failure for the superseded id arrives afterwards. Display must not flip
// to error.
record('newestFirstThenStaleFailure', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state; // id 0
  state = step(state, { type: 'search', query: 'dog' }).state; // id 1, latest
  state = step(state, { type: 'resolve', id: 1, outcome: { type: 'success', data: ['Dog'] } }).state;
  assertEqual(selectDisplay(state.bindingState, state), { status: 'success', query: 'dog', data: ['Dog'] });

  state = step(state, { type: 'resolve', id: 0, outcome: { type: 'failure', error: 'stale error' } }).state;
  assertEqual(selectDisplay(state.bindingState, state), { status: 'success', query: 'dog', data: ['Dog'] });
  assertEqual(state.bindingState[0].status, 'failure'); // settled, just not adopted
});

// repeatedTextReentry: re-entering the same text issues a fresh request id;
// the stale first occurrence must not resolve into the later one's slot.
record('repeatedTextReentry', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state; // id 0
  state = step(state, { type: 'search', query: 'dog' }).state; // id 1
  state = step(state, { type: 'search', query: 'cat' }).state; // id 2, same text as id 0
  assertEqual(state.latestId, 2);
  assert.notEqual(state.latestId, 0); // domain text alone ("cat") does not identify the request

  // id 0's late success ("cat") must not be mistaken for id 2's ("cat") result
  state = step(state, { type: 'resolve', id: 0, outcome: { type: 'success', data: ['STALE cat'] } }).state;
  assertEqual(selectDisplay(state.bindingState, state), { status: 'pending', query: 'cat' });

  state = step(state, { type: 'resolve', id: 2, outcome: { type: 'success', data: ['FRESH cat'] } }).state;
  assertEqual(selectDisplay(state.bindingState, state), {
    status: 'success',
    query: 'cat',
    data: ['FRESH cat'],
  });
});

// bestEffortCancelStillArrives: cancelRequest effect was sent for the
// superseded id, but its failure still arrives later; must stay unadopted.
record('bestEffortCancelStillArrives', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state; // id 0
  const cancelRes = step(state, { type: 'search', query: 'dog' }); // id 1, cancels id 0
  assert.ok(cancelRes.effects.some((e) => e.type === 'cancelRequest' && e.id === 0));
  state = cancelRes.state;

  state = step(state, { type: 'resolve', id: 0, outcome: { type: 'failure', error: 'AbortError' } }).state;
  assertEqual(selectDisplay(state.bindingState, state), { status: 'pending', query: 'dog' });
  assertEqual(state.bindingState[0].status, 'failure'); // settled despite the cancel request
});

// noCancelWhenPreviousAlreadySettled: cancelRequest is only meaningful while
// the previous request is still pending; once it already settled, a new
// search must not re-cancel it.
record('noCancelWhenPreviousAlreadySettled', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state; // id 0
  state = step(state, { type: 'resolve', id: 0, outcome: { type: 'success', data: ['Cat'] } }).state; // settled
  const res = step(state, { type: 'search', query: 'dog' }); // id 1
  assertEqual(res.effects, [{ type: 'startRequest', id: 1, query: 'dog' }]); // no cancelRequest
});

// resolveUnknownId: a resolve for an id the model never issued (defensive
// branch) is a no-op — no state change, no effects.
record('resolveUnknownId', () => {
  const state = initState();
  const res = step(state, { type: 'resolve', id: 999, outcome: { type: 'success', data: ['?'] } });
  assertEqual(res.state, state);
  assertEqual(res.effects, []);
});

// tooltipIndependence: tooltip toggling never touches search coordination,
// and search events never touch tooltipOpen.
record('tooltipIndependence', () => {
  let state = initState();
  state = step(state, { type: 'search', query: 'cat' }).state;
  const beforeToggle = snapshot(state);
  const toggleRes = step(state, { type: 'toggleTooltip' });
  assertEqual(toggleRes.effects, []);
  state = toggleRes.state;
  assertEqual(state.tooltipOpen, true);
  assertEqual(state.bindingState, beforeToggle.bindingState);
  assertEqual(state.latestId, beforeToggle.latestId);

  state = step(state, { type: 'resolve', id: 0, outcome: { type: 'success', data: ['Cat'] } }).state;
  assertEqual(state.tooltipOpen, true); // untouched by a search event
});

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} cases passed`);
if (failed.length > 0) {
  process.exitCode = 1;
}

export { initState, transition, selectDisplay };
