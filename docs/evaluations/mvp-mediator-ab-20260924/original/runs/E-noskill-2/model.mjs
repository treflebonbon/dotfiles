// Abstract decision model for recording/calibration device-ownership exclusion.
// Pure state machine: no I/O, no hidden state. All decision state lives in the
// `state` object passed to transition(); effects are commands for the caller
// (the existing execution boundary) to perform.
//
// State shape (flat, all fields are strings/null/finite numbers):
//   phase:       'idle'|'acquiring'|'active'|'stopping'|'releasing'|'blocked'
//   owner:       null|'recording'|'calibration'  - confirmed/reserved owner
//   opTarget:    null|'recording'|'calibration'  - target of in-flight acquire
//                (only meaningful while phase === 'acquiring')
//   desired:     null|'recording'|'calibration'  - latest requested intent
//   operationId: null|number                     - id of the in-flight effect
//   failedStage: null|'stop'|'release'            - stage awaiting retry
//   nextId:      number                           - monotonic id counter

const TARGETS = new Set(['recording', 'calibration']);
function isTarget(t) {
  return TARGETS.has(t);
}

export function initial() {
  return {
    phase: 'idle',
    owner: null,
    opTarget: null,
    desired: null,
    operationId: null,
    failedStage: null,
    nextId: 1,
  };
}

function noop(state) {
  return { state, effects: [] };
}

export function transition(state, event) {
  if (!event || typeof event.type !== 'string') return noop(state);

  switch (event.type) {
    case 'profile':
      // Profile editor is independent of the exclusion FSM: nothing to do here.
      return noop(state);

    case 'start': {
      if (!isTarget(event.target)) return noop(state);
      const target = event.target;

      if (state.phase === 'idle') {
        const id = state.nextId;
        return {
          state: {
            ...state,
            phase: 'acquiring',
            owner: null,
            opTarget: target,
            desired: target,
            operationId: id,
            failedStage: null,
            nextId: id + 1,
          },
          effects: [{ type: 'acquire', target, id }],
        };
      }

      if (
        state.phase === 'acquiring' ||
        state.phase === 'stopping' ||
        state.phase === 'releasing' ||
        state.phase === 'blocked'
      ) {
        // Latest start wins: update intent only. In-flight work (acquire,
        // stop, release) keeps its own identity and runs to completion.
        return { state: { ...state, desired: target }, effects: [] };
      }

      if (state.phase === 'active') {
        if (target === state.owner) return noop(state); // same-owner start is a no-op
        const id = state.nextId;
        return {
          state: {
            ...state,
            phase: 'stopping',
            desired: target,
            opTarget: null,
            operationId: id,
            failedStage: null,
            nextId: id + 1,
          },
          effects: [{ type: 'stop', target: state.owner, id }],
        };
      }

      return noop(state);
    }

    case 'ok': {
      if (state.operationId === null || event.id !== state.operationId) return noop(state);

      if (state.phase === 'acquiring') {
        const acquired = state.opTarget;
        if (acquired === state.desired) {
          return {
            state: {
              ...state,
              phase: 'active',
              owner: acquired,
              opTarget: null,
              operationId: null,
              failedStage: null,
            },
            effects: [],
          };
        }
        // Intent moved on while we were acquiring: own it briefly, then
        // stop + release it before chasing the latest desired target.
        const id = state.nextId;
        return {
          state: {
            ...state,
            phase: 'stopping',
            owner: acquired,
            opTarget: null,
            operationId: id,
            failedStage: null,
            nextId: id + 1,
          },
          effects: [{ type: 'stop', target: acquired, id }],
        };
      }

      if (state.phase === 'stopping') {
        const id = state.nextId;
        return {
          state: { ...state, phase: 'releasing', operationId: id, failedStage: null, nextId: id + 1 },
          effects: [{ type: 'release', target: state.owner, id }],
        };
      }

      if (state.phase === 'releasing') {
        const id = state.nextId;
        const target = state.desired;
        return {
          state: {
            ...state,
            phase: 'acquiring',
            owner: null,
            opTarget: target,
            operationId: id,
            failedStage: null,
            nextId: id + 1,
          },
          effects: [{ type: 'acquire', target, id }],
        };
      }

      return noop(state);
    }

    case 'fail': {
      if (state.operationId === null || event.id !== state.operationId) return noop(state);

      if (state.phase === 'acquiring') {
        // Acquisition failure returns idle without auto-retrying.
        return {
          state: {
            ...state,
            phase: 'idle',
            owner: null,
            opTarget: null,
            desired: null,
            operationId: null,
            failedStage: null,
          },
          effects: [],
        };
      }

      if (state.phase === 'stopping') {
        return {
          state: { ...state, phase: 'blocked', opTarget: null, operationId: null, failedStage: 'stop' },
          effects: [],
        };
      }

      if (state.phase === 'releasing') {
        return {
          state: { ...state, phase: 'blocked', opTarget: null, operationId: null, failedStage: 'release' },
          effects: [],
        };
      }

      return noop(state);
    }

    case 'retry': {
      if (state.phase !== 'blocked') return noop(state);
      const id = state.nextId;
      if (state.failedStage === 'stop') {
        return {
          state: { ...state, phase: 'stopping', operationId: id, failedStage: null, nextId: id + 1 },
          effects: [{ type: 'stop', target: state.owner, id }],
        };
      }
      if (state.failedStage === 'release') {
        return {
          state: { ...state, phase: 'releasing', operationId: id, failedStage: null, nextId: id + 1 },
          effects: [{ type: 'release', target: state.owner, id }],
        };
      }
      return noop(state);
    }

    default:
      return noop(state);
  }
}

export function observe(state) {
  return {
    phase: state.phase,
    owner: state.owner,
    desired: state.desired,
    operationId: state.operationId,
  };
}

// ---------------------------------------------------------------------------
// Self-check (run with `node model.mjs`). Not a framework: plain assertions.
// ---------------------------------------------------------------------------
async function demo() {
  const assert = (await import('node:assert/strict')).default;

  const clone = (x) => JSON.parse(JSON.stringify(x));
  let totalIds = 0;

  // Purity check: preserve input, deterministic across repeated calls.
  // `usedIds` is scoped to one run (one lineage starting at initial()) since
  // ids only need to be unique within a run, not across independent runs.
  function checkPure(state, event, label, usedIds) {
    const before = clone(state);
    const r1 = transition(state, event);
    assert.deepStrictEqual(clone(state), before, `${label}: 1st call mutated input`);
    const r1Snapshot = clone(r1);
    const r2 = transition(state, event);
    assert.deepStrictEqual(clone(state), before, `${label}: 2nd call mutated input`);
    assert.deepStrictEqual(clone(r2), r1Snapshot, `${label}: nondeterministic result`);
    for (const e of r1.effects) {
      assert.ok(!usedIds.has(e.id), `${label}: effect id ${e.id} reused within run`);
      usedIds.add(e.id);
      totalIds++;
    }
    return r1;
  }

  // A. basic start -> acquire -> active; same-owner no-op; profile no-op.
  {
    let s = initial();
    const ids = new Set();
    assert.deepStrictEqual(observe(s), { phase: 'idle', owner: null, desired: null, operationId: null });

    let r = checkPure(s, { type: 'start', target: 'recording' }, 'A1', ids);
    assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'recording', id: 1 }]);
    s = r.state;
    assert.deepStrictEqual(observe(s), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 1 });

    r = checkPure(s, { type: 'ok', id: 1 }, 'A2', ids);
    assert.deepStrictEqual(r.effects, []);
    s = r.state;
    assert.deepStrictEqual(observe(s), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });

    r = checkPure(s, { type: 'start', target: 'recording' }, 'A3 same-owner no-op', ids);
    assert.deepStrictEqual(r.effects, []);
    assert.deepStrictEqual(r.state, s);

    r = checkPure(s, { type: 'profile' }, 'A4 profile no-op', ids);
    assert.deepStrictEqual(r.effects, []);
    assert.deepStrictEqual(r.state, s);
  }

  // B. owner switch from active: stop -> release -> acquire new target.
  {
    let s = initial();
    const ids = new Set();
    s = checkPure(s, { type: 'start', target: 'recording' }, 'B0', ids).state;
    s = checkPure(s, { type: 'ok', id: s.operationId }, 'B0b', ids).state; // active/recording

    let r = checkPure(s, { type: 'start', target: 'calibration' }, 'B1 switch owner', ids);
    assert.strictEqual(r.state.phase, 'stopping');
    assert.deepStrictEqual(r.effects, [{ type: 'stop', target: 'recording', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'B2 stop ok -> releasing', ids);
    assert.strictEqual(r.state.phase, 'releasing');
    assert.deepStrictEqual(r.effects, [{ type: 'release', target: 'recording', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'B3 release ok -> acquiring latest', ids);
    assert.strictEqual(r.state.phase, 'acquiring');
    assert.strictEqual(r.state.owner, null);
    assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'B4 acquire ok -> active', ids);
    assert.deepStrictEqual(observe(r.state), {
      phase: 'active',
      owner: 'calibration',
      desired: 'calibration',
      operationId: null,
    });
  }

  // C. intent changes mid-acquire, including returning to the earlier target:
  // in-flight acquire keeps its identity; completion re-evaluates against
  // the latest desired target and unwinds via stop+release before re-acquiring.
  {
    let s = initial();
    const ids = new Set();
    let r = checkPure(s, { type: 'start', target: 'recording' }, 'C1', ids);
    s = r.state; // acquiring recording, id=1

    r = checkPure(s, { type: 'start', target: 'calibration' }, 'C2 intent change mid-acquire', ids);
    assert.deepStrictEqual(r.effects, []); // in-flight acquire untouched
    assert.strictEqual(r.state.phase, 'acquiring');
    assert.strictEqual(r.state.opTarget, 'recording'); // identity unchanged
    assert.strictEqual(r.state.desired, 'calibration');
    s = r.state;

    r = checkPure(s, { type: 'start', target: 'recording' }, 'C3 returning to earlier target', ids);
    assert.strictEqual(r.state.desired, 'recording');
    s = r.state;

    // Still same in-flight op id; completes for the target it was issued for.
    r = checkPure(s, { type: 'ok', id: 1 }, 'C4 in-flight acquire completes, matches latest desired', ids);
    assert.deepStrictEqual(observe(r.state), {
      phase: 'active',
      owner: 'recording',
      desired: 'recording',
      operationId: null,
    });
  }

  // D. mismatch discovered only after acquisition succeeds.
  {
    let s = initial();
    const ids = new Set();
    let r = checkPure(s, { type: 'start', target: 'recording' }, 'D1', ids);
    s = r.state;
    r = checkPure(s, { type: 'start', target: 'calibration' }, 'D2 change intent mid-acquire', ids);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: 1 }, 'D3 acquire completes for stale target -> unwind', ids);
    assert.strictEqual(r.state.phase, 'stopping');
    assert.strictEqual(r.state.owner, 'recording');
    assert.deepStrictEqual(r.effects, [{ type: 'stop', target: 'recording', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'D4 stop ok -> releasing', ids);
    s = r.state;
    r = checkPure(s, { type: 'ok', id: s.operationId }, 'D5 release ok -> acquiring latest', ids);
    assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: r.state.operationId }]);
    s = r.state;
    r = checkPure(s, { type: 'ok', id: s.operationId }, 'D6 -> active calibration', ids);
    assert.strictEqual(r.state.phase, 'active');
    assert.strictEqual(r.state.owner, 'calibration');
  }

  // E. stop failure blocks; repeated starts update intent only; retry recovers.
  {
    let s = initial();
    const ids = new Set();
    s = checkPure(s, { type: 'start', target: 'recording' }, 'E1', ids).state;
    s = checkPure(s, { type: 'ok', id: s.operationId }, 'E2', ids).state; // active/recording

    let r = checkPure(s, { type: 'start', target: 'calibration' }, 'E3', ids);
    s = r.state; // stopping

    r = checkPure(s, { type: 'fail', id: s.operationId }, 'E4 stop fails -> blocked', ids);
    assert.deepStrictEqual(observe(r.state), {
      phase: 'blocked',
      owner: 'recording',
      desired: 'calibration',
      operationId: null,
    });
    assert.deepStrictEqual(r.effects, []);
    s = r.state;

    r = checkPure(s, { type: 'start', target: 'calibration' }, 'E5 repeated start while blocked: no auto-retry', ids);
    assert.deepStrictEqual(r.effects, []);
    assert.strictEqual(r.state.phase, 'blocked');
    s = r.state;

    r = checkPure(s, { type: 'retry' }, 'E6 explicit retry of failed stop', ids);
    assert.strictEqual(r.state.phase, 'stopping');
    assert.deepStrictEqual(r.effects, [{ type: 'stop', target: 'recording', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'E7 stop ok -> releasing', ids);
    s = r.state;
    r = checkPure(s, { type: 'ok', id: s.operationId }, 'E8 release ok -> acquiring calibration', ids);
    s = r.state;
    r = checkPure(s, { type: 'ok', id: s.operationId }, 'E9 -> active calibration', ids);
    assert.strictEqual(r.state.phase, 'active');
    assert.strictEqual(r.state.owner, 'calibration');
  }

  // F. release failure blocks with failedStage=release; retry recovers.
  {
    let s = initial();
    const ids = new Set();
    s = checkPure(s, { type: 'start', target: 'recording' }, 'F1', ids).state;
    s = checkPure(s, { type: 'ok', id: s.operationId }, 'F2', ids).state;
    s = checkPure(s, { type: 'start', target: 'calibration' }, 'F3', ids).state; // stopping
    s = checkPure(s, { type: 'ok', id: s.operationId }, 'F4', ids).state; // releasing

    let r = checkPure(s, { type: 'fail', id: s.operationId }, 'F5 release fails -> blocked', ids);
    assert.strictEqual(r.state.phase, 'blocked');
    assert.strictEqual(r.state.owner, 'recording'); // still reserved
    s = r.state;

    r = checkPure(s, { type: 'retry' }, 'F6 retry release', ids);
    assert.deepStrictEqual(r.effects, [{ type: 'release', target: 'recording', id: r.state.operationId }]);
    s = r.state;

    r = checkPure(s, { type: 'ok', id: s.operationId }, 'F7 release ok -> acquiring calibration', ids);
    s = r.state;
    r = checkPure(s, { type: 'ok', id: s.operationId }, 'F8 -> active calibration', ids);
    assert.strictEqual(r.state.phase, 'active');
    assert.strictEqual(r.state.owner, 'calibration');
  }

  // G. acquisition failure returns idle without auto-retry.
  {
    let s = initial();
    const ids = new Set();
    let r = checkPure(s, { type: 'start', target: 'recording' }, 'G1', ids);
    s = r.state;
    r = checkPure(s, { type: 'fail', id: s.operationId }, 'G2 acquire fails -> idle', ids);
    assert.deepStrictEqual(observe(r.state), { phase: 'idle', owner: null, desired: null, operationId: null });
    assert.deepStrictEqual(r.effects, []);
  }

  // H. stale/unknown events are ignored.
  {
    let s = initial();
    const ids = new Set();
    let r = checkPure(s, { type: 'start', target: 'recording' }, 'H1', ids);
    s = r.state; // acquiring, id=1

    r = checkPure(s, { type: 'ok', id: 999 }, 'H2 stale ok ignored', ids);
    assert.deepStrictEqual(r.state, s);
    assert.deepStrictEqual(r.effects, []);

    r = checkPure(s, { type: 'fail', id: 999 }, 'H3 stale fail ignored', ids);
    assert.deepStrictEqual(r.state, s);

    r = checkPure(s, { type: 'bogus' }, 'H4 unknown event ignored', ids);
    assert.deepStrictEqual(r.state, s);

    r = checkPure(s, { type: 'retry' }, 'H5 retry outside blocked ignored', ids);
    assert.deepStrictEqual(r.state, s);

    // idle/active/blocked have operationId===null: any ok/fail is stale.
    let idleState = initial();
    r = checkPure(idleState, { type: 'ok', id: 1 }, 'H6 ok while idle ignored', ids);
    assert.deepStrictEqual(r.state, idleState);
  }

  console.log(`OK: all self-checks passed. ${totalIds} effect ids issued across all runs, none reused within a run.`);
}

const { fileURLToPath } = await import('node:url');
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  demo().catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
}
