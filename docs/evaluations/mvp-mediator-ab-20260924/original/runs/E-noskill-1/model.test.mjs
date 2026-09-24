import assert from 'node:assert/strict';
import { initial, transition, observe } from './model.mjs';

// --- representation contract audit -----------------------------------------
// acyclic, only plain objects / dense arrays / null / boolean / string / finite number
function isPlainObject(v) {
  return typeof v === 'object' && v !== null && Object.getPrototypeOf(v) === Object.prototype;
}
function assertValidValue(v, path) {
  if (v === null || typeof v === 'boolean' || typeof v === 'string') return;
  if (typeof v === 'number') {
    assert.ok(Number.isFinite(v), `${path}: number must be finite`);
    return;
  }
  if (Array.isArray(v)) {
    const keys = Object.keys(v);
    assert.equal(keys.length, v.length, `${path}: array must be dense with no extra props`);
    v.forEach((item, i) => assertValidValue(item, `${path}[${i}]`));
    return;
  }
  if (isPlainObject(v)) {
    for (const key of Object.keys(v)) {
      const desc = Object.getOwnPropertyDescriptor(v, key);
      assert.ok('value' in desc, `${path}.${key}: must be a data property, not accessor`);
      assert.ok(desc.enumerable, `${path}.${key}: must be enumerable`);
      assertValidValue(v[key], `${path}.${key}`);
    }
    return;
  }
  assert.fail(`${path}: value of disallowed type: ${typeof v} (${String(v)})`);
}

// --- purity: repeat the same (state, event) call twice, snapshot in between -
// `sink`, when given, collects every emitted effect id for a single continuous
// run so its monotonic-uniqueness can be checked below. Independent or forked
// hypothetical chains (fresh initial(), or branching to explore alternatives)
// are each their own run and are not mixed into one sink.
function checkPure(state, event, label, sink) {
  const before = JSON.parse(JSON.stringify(state));
  const r1 = transition(state, event);
  assertValidValue(r1.state, `${label}.result1.state`);
  assertValidValue(r1.effects, `${label}.result1.effects`);
  assert.deepEqual(JSON.parse(JSON.stringify(state)), before, `${label}: input mutated by call 1`);
  const r1Snapshot = JSON.parse(JSON.stringify(r1));

  const r2 = transition(state, event);
  assert.deepEqual(JSON.parse(JSON.stringify(state)), before, `${label}: input mutated by call 2`);
  assert.deepEqual(JSON.parse(JSON.stringify(r2)), r1Snapshot, `${label}: nondeterministic result`);

  if (sink) for (const eff of r1.effects) sink.push(eff.id);
  return r1;
}
function assertIdRun(sink, label) {
  for (let i = 1; i < sink.length; i++) {
    assert.ok(sink[i] > sink[i - 1], `${label}: ids must be strictly increasing at index ${i} (${sink[i - 1]} -> ${sink[i]})`);
  }
  assert.equal(new Set(sink).size, sink.length, `${label}: ids must be unique`);
}

let checks = 0;
const mainIds = [];

// 1. idle -> start recording -> acquiring, emits acquire effect
let s0 = initial();
assertValidValue(s0, 's0');
assert.deepEqual(observe(s0), { phase: 'idle', owner: null, desired: null, operationId: null });

let r = checkPure(s0, { type: 'start', target: 'recording' }, 'idle->start', mainIds);
let s1 = r.state;
assert.deepEqual(observe(s1), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 1 });
assert.deepEqual(r.effects, [{ type: 'acquire', target: 'recording', id: 1 }]);
checks++;

// 2. while acquiring, a start for a different target updates intent only, no new effect
r = checkPure(s1, { type: 'start', target: 'calibration' }, 'acquiring->start(other)', mainIds);
let s2 = r.state;
assert.deepEqual(observe(s2), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: 1 });
assert.deepEqual(r.effects, []);
checks++;

// 3. switching back to the original target before it resolves ("returning to an earlier target")
r = checkPure(s2, { type: 'start', target: 'recording' }, 'acquiring->start(back)', mainIds);
let s3 = r.state;
assert.deepEqual(observe(s3), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 1 });
checks++;

// 4. stale ok (wrong id) is ignored
r = checkPure(s3, { type: 'ok', id: 999 }, 'acquiring->ok(stale)', mainIds);
assert.equal(r.state, s3);
assert.deepEqual(r.effects, []);
checks++;

// 5. ok for the in-flight acquire; pendingTarget === desired ('recording') -> active
r = checkPure(s3, { type: 'ok', id: 1 }, 'acquiring->ok(match)', mainIds);
let s4 = r.state;
assert.deepEqual(observe(s4), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
assert.deepEqual(r.effects, []);
checks++;

// 6. same-owner start in active is a no-op
r = checkPure(s4, { type: 'start', target: 'recording' }, 'active->start(same)', mainIds);
assert.equal(r.state, s4);
assert.deepEqual(r.effects, []);
checks++;

// 7. different-target start in active begins stop
r = checkPure(s4, { type: 'start', target: 'calibration' }, 'active->start(other)', mainIds);
let s5 = r.state;
assert.deepEqual(observe(s5), { phase: 'stopping', owner: 'recording', desired: 'calibration', operationId: 2 });
assert.deepEqual(r.effects, [{ type: 'stop', target: 'recording', id: 2 }]);
checks++;

// 8. stop fails -> blocked, owner still reserved
r = checkPure(s5, { type: 'fail', id: 2 }, 'stopping->fail', mainIds);
let s6 = r.state;
assert.deepEqual(observe(s6), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
assert.deepEqual(r.effects, []);
checks++;

// 9. repeated start while blocked updates intent, does not retry automatically
r = checkPure(s6, { type: 'start', target: 'recording' }, 'blocked->start', mainIds);
let s7 = r.state;
assert.deepEqual(observe(s7), { phase: 'blocked', owner: 'recording', desired: 'recording', operationId: null });
assert.deepEqual(r.effects, []);
checks++;
// and back to calibration again, still blocked, still no auto-retry
r = checkPure(s7, { type: 'start', target: 'calibration' }, 'blocked->start2', mainIds);
let s8 = r.state;
assert.deepEqual(observe(s8), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
checks++;

// 10. explicit retry re-issues the failed stage (stop)
r = checkPure(s8, { type: 'retry' }, 'blocked->retry', mainIds);
let s9 = r.state;
assert.deepEqual(observe(s9), { phase: 'stopping', owner: 'recording', desired: 'calibration', operationId: 3 });
assert.deepEqual(r.effects, [{ type: 'stop', target: 'recording', id: 3 }]);
checks++;

// 11. stop succeeds -> releasing
r = checkPure(s9, { type: 'ok', id: 3 }, 'stopping->ok', mainIds);
let s10 = r.state;
assert.deepEqual(observe(s10), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: 4 });
assert.deepEqual(r.effects, [{ type: 'release', target: 'recording', id: 4 }]);
checks++;

// 12. release fails -> blocked (release stage remembered for retry)
r = checkPure(s10, { type: 'fail', id: 4 }, 'releasing->fail', mainIds);
let s11 = r.state;
assert.deepEqual(observe(s11), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
checks++;

r = checkPure(s11, { type: 'retry' }, 'blocked->retry(release)', mainIds);
let s12 = r.state;
assert.deepEqual(observe(s12), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: 5 });
assert.deepEqual(r.effects, [{ type: 'release', target: 'recording', id: 5 }]);
checks++;

// 13. release succeeds -> owner released, straight into acquiring the latest desired target
r = checkPure(s12, { type: 'ok', id: 5 }, 'releasing->ok', mainIds);
let s13 = r.state;
assert.deepEqual(observe(s13), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: 6 });
assert.deepEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: 6 }]);
checks++;

// 14. intent changes mid-acquire (recording), then original acquire resolves for calibration:
// since pendingTarget (calibration) !== desired (recording), must stop+release before acquiring recording.
r = checkPure(s13, { type: 'start', target: 'recording' }, 'acquiring->start(divert)', mainIds);
let s14 = r.state;
assert.deepEqual(observe(s14), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 6 });
checks++;

r = checkPure(s14, { type: 'ok', id: 6 }, 'acquiring->ok(divert)', mainIds);
let s15 = r.state;
assert.deepEqual(observe(s15), { phase: 'stopping', owner: 'calibration', desired: 'recording', operationId: 7 });
assert.deepEqual(r.effects, [{ type: 'stop', target: 'calibration', id: 7 }]);
checks++;

r = checkPure(s15, { type: 'ok', id: 7 }, 'stopping->ok(divert)', mainIds);
let s16 = r.state;
assert.deepEqual(observe(s16), { phase: 'releasing', owner: 'calibration', desired: 'recording', operationId: 8 });
checks++;

r = checkPure(s16, { type: 'ok', id: 8 }, 'releasing->ok(divert)', mainIds);
let s17 = r.state;
assert.deepEqual(observe(s17), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 9 });
assert.deepEqual(r.effects, [{ type: 'acquire', target: 'recording', id: 9 }]);
checks++;

// 15. acquisition failure returns idle without auto-retrying
r = checkPure(s17, { type: 'fail', id: 9 }, 'acquiring->fail', mainIds);
let s18 = r.state;
assert.deepEqual(observe(s18), { phase: 'idle', owner: null, desired: null, operationId: null });
assert.deepEqual(r.effects, []);
checks++;

// 16. unknown event type is a no-op
r = checkPure(s18, { type: 'nonsense' }, 'idle->unknown');
assert.equal(r.state, s18);
assert.deepEqual(r.effects, []);
checks++;

// 17. profile event never touches the exclusion machine, from any reachable phase
r = checkPure(s18, { type: 'profile' }, 'idle->profile');
assert.equal(r.state, s18);
checks++;
r = checkPure(s5, { type: 'profile' }, 'stopping->profile');
assert.equal(r.state, s5);
checks++;

// 18. invalid/missing target is a no-op, from idle and from active
r = checkPure(s18, { type: 'start', target: 'profile' }, 'idle->start(invalid target)');
assert.equal(r.state, s18);
checks++;
r = checkPure(s18, { type: 'start' }, 'idle->start(no target)');
assert.equal(r.state, s18);
checks++;

// ids emitted across the whole main chain (steps 1-15) are strictly increasing and unique
assertIdRun(mainIds, 'main chain');
checks++;

// --- additional scenarios ---------------------------------------------------

// 19. returning to the reserved owner while stopping still completes stop -> release -> acquire
//     (in-flight identity unchanged; no short-circuit back to active)
let a0 = checkPure(initial(), { type: 'start', target: 'recording' }, 'A:idle->start').state;
a0 = checkPure(a0, { type: 'ok', id: a0.operationId }, 'A:acquiring->ok').state;
assert.deepEqual(observe(a0), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
let a1 = checkPure(a0, { type: 'start', target: 'calibration' }, 'A:active->start(other)').state;
assert.equal(a1.phase, 'stopping');
let a2 = checkPure(a1, { type: 'start', target: 'recording' }, 'A:stopping->start(back to owner)').state;
assert.deepEqual(observe(a2), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: a1.operationId });
let a3r = checkPure(a2, { type: 'ok', id: a2.operationId }, 'A:stopping->ok');
assert.equal(a3r.state.phase, 'releasing');
assert.deepEqual(a3r.effects, [{ type: 'release', target: 'recording', id: a3r.state.operationId }]);
let a4r = checkPure(a3r.state, { type: 'ok', id: a3r.state.operationId }, 'A:releasing->ok');
// released, then re-acquires the (unchanged) desired target with a fresh id
assert.deepEqual(observe(a4r.state), { phase: 'acquiring', owner: null, desired: 'recording', operationId: a4r.state.operationId });
assert.deepEqual(a4r.effects, [{ type: 'acquire', target: 'recording', id: a4r.state.operationId }]);
checks += 5;

// 20. acquire fails after intent diverged mid-flight: desired is discarded too, no leftover acquire for it
let b0 = checkPure(initial(), { type: 'start', target: 'recording' }, 'B:idle->start').state;
b0 = checkPure(b0, { type: 'start', target: 'calibration' }, 'B:acquiring->start(divert)').state;
assert.deepEqual(observe(b0), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: 1 });
let b1r = checkPure(b0, { type: 'fail', id: 1 }, 'B:acquiring->fail(diverted)');
assert.deepEqual(observe(b1r.state), { phase: 'idle', owner: null, desired: null, operationId: null });
assert.deepEqual(b1r.effects, []);
checks += 2;

// 21. a stale fail for an old stop id, arriving after a retry already reissued it, is ignored
let c0 = checkPure(a1, { type: 'fail', id: a1.operationId }, 'C:stopping->fail').state; // -> blocked
assert.equal(c0.phase, 'blocked');
const staleStopId = a1.operationId;
let c1r = checkPure(c0, { type: 'retry' }, 'C:blocked->retry');
const freshStopId = c1r.state.operationId;
assert.notEqual(freshStopId, staleStopId);
let c2r = checkPure(c1r.state, { type: 'fail', id: staleStopId }, 'C:stopping->fail(stale, post-retry)');
assert.equal(c2r.state, c1r.state); // ignored: still stopping under the fresh id
checks += 3;

// --- seeded random walk: broad invariant check across ~2000 random events ---
// LCG (test-only; never in the model).
function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}
function checkInvariants(state, label) {
  switch (state.phase) {
    case 'idle':
      assert.equal(state.owner, null, `${label}: idle.owner`);
      assert.equal(state.desired, null, `${label}: idle.desired`);
      assert.equal(state.operationId, null, `${label}: idle.operationId`);
      assert.equal(state.pendingTarget, null, `${label}: idle.pendingTarget`);
      assert.equal(state.stage, null, `${label}: idle.stage`);
      break;
    case 'acquiring':
      assert.equal(state.owner, null, `${label}: acquiring.owner`);
      assert.notEqual(state.operationId, null, `${label}: acquiring.operationId`);
      assert.notEqual(state.pendingTarget, null, `${label}: acquiring.pendingTarget`);
      assert.equal(state.stage, 'acquire', `${label}: acquiring.stage`);
      break;
    case 'active':
      assert.equal(state.owner, state.desired, `${label}: active.owner===desired`);
      assert.equal(state.operationId, null, `${label}: active.operationId`);
      break;
    case 'stopping':
    case 'releasing':
      assert.equal(state.owner, state.pendingTarget, `${label}: ${state.phase}.owner===pendingTarget`);
      assert.notEqual(state.operationId, null, `${label}: ${state.phase}.operationId`);
      assert.equal(state.stage, state.phase === 'stopping' ? 'stop' : 'release', `${label}: ${state.phase}.stage`);
      break;
    case 'blocked':
      assert.equal(state.operationId, null, `${label}: blocked.operationId`);
      assert.notEqual(state.owner, null, `${label}: blocked.owner`);
      assert.ok(state.stage === 'stop' || state.stage === 'release', `${label}: blocked.stage`);
      break;
    default:
      assert.fail(`${label}: unknown phase ${state.phase}`);
  }
}

const rng = makeRng(42);
const eventPool = (st) => {
  const pool = [
    { type: 'start', target: 'recording' },
    { type: 'start', target: 'calibration' },
    { type: 'retry' },
    { type: 'profile' },
    { type: 'unknown-event' },
    { type: 'ok', id: 999999 }, // stale on purpose
    { type: 'fail', id: 999999 }, // stale on purpose
  ];
  if (st.operationId !== null) {
    pool.push({ type: 'ok', id: st.operationId });
    pool.push({ type: 'fail', id: st.operationId });
  }
  return pool;
};

let w = initial();
checkInvariants(w, 'walk:0');
const walkIds = [];
const WALK_STEPS = 2000;
for (let i = 0; i < WALK_STEPS; i++) {
  const pool = eventPool(w);
  const ev = pool[Math.floor(rng() * pool.length)];
  const res = checkPure(w, ev, `walk:${i}:${ev.type}`, walkIds);
  checkInvariants(res.state, `walk:${i}:${ev.type}:post`);
  w = res.state;
}
assertIdRun(walkIds, 'random walk');
checks += WALK_STEPS + 1;

console.log(`OK: ${checks} checks passed (functional transitions + purity + representation contract + ${WALK_STEPS}-step random walk)`);
