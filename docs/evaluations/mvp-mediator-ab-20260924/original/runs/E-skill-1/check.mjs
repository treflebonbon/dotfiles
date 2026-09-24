import assert from 'node:assert/strict';
import { initial, transition, observe } from './model.mjs';

// Representation contract: acyclic plain data only (Object.prototype objects,
// dense arrays, null, boolean, string, finite number).
function assertPlainData(value, path = 'root') {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return;
  if (typeof value === 'number') {
    assert.ok(Number.isFinite(value), `${path}: number must be finite`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertPlainData(v, `${path}[${i}]`));
    return;
  }
  assert.equal(Object.getPrototypeOf(value), Object.prototype, `${path}: must be a plain object`);
  for (const key of Object.keys(value)) assertPlainData(value[key], `${path}.${key}`);
}

// Every checked transition goes through this: preserves input, snapshots the
// first result before a second identical call, compares input snapshot and
// both full results (state + effects), per the skill's purity procedure.
function step(state, event) {
  const before = structuredClone(state);
  const first = transition(state, event);
  assert.deepEqual(state, before, 'input mutated by 1st call');
  assertPlainData(first.state, 'first.state');
  assertPlainData(first.effects, 'first.effects');
  const firstBefore = structuredClone(first);
  const second = transition(state, event);
  assert.deepEqual(state, before, 'input mutated by 2nd call');
  assert.deepEqual(first, firstBefore, '1st result mutated by 2nd call');
  assert.deepEqual(second, firstBefore, 'same state+event produced a different result');
  return first;
}

function run(events) {
  let state = initial();
  for (const event of events) state = step(state, event).state;
  return state;
}

// --- normalPath: fresh state, start request, then the in-flight command's
// normal completion. Nothing else. ---
{
  const s0 = initial();
  const r1 = step(s0, { type: 'start', target: 'recording' });
  assert.deepEqual(r1.effects, [{ type: 'acquire', target: 'recording', id: 1 }]);
  assert.deepEqual(observe(r1.state), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 1 });
  const r2 = step(r1.state, { type: 'ok', id: 1 });
  assert.deepEqual(r2.effects, []);
  assert.deepEqual(observe(r2.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  console.log('normalPath: ok');
}

// --- acquisitionFailureIdle: acquisition failure returns idle, no auto-retry,
// even if intent changed mid-acquisition (calibration was never acquired). ---
{
  const s0 = initial();
  const r1 = step(s0, { type: 'start', target: 'recording' });
  const r2 = step(r1.state, { type: 'start', target: 'calibration' }); // intent flips, in-flight acquire(recording) continues
  const r3 = step(r2.state, { type: 'fail', id: 1 });
  assert.deepEqual(r3.effects, []);
  assert.deepEqual(observe(r3.state), { phase: 'idle', owner: null, desired: null, operationId: null });
  const r4 = step(r3.state, { type: 'start', target: 'calibration' }); // fresh start, new id, not reused
  assert.deepEqual(r4.effects, [{ type: 'acquire', target: 'calibration', id: 2 }]);
  console.log('acquisitionFailureIdle: ok');
}

// --- sameOwnerNoOp: start with the currently-active owner is a no-op ---
{
  const active = run([{ type: 'start', target: 'recording' }, { type: 'ok', id: 1 }]);
  const r = step(active, { type: 'start', target: 'recording' });
  assert.equal(r.state, active); // same reference: truly unchanged
  assert.deepEqual(r.effects, []);
  console.log('sameOwnerNoOp: ok');
}

// --- switchKeepsIdentityThenSwitches: latest intent wins during acquisition;
// once acquired, owner kept only if it still matches latest intent, else
// stop+release before acquiring the new target. In-flight op id is untouched
// by the intent change. ---
{
  const s0 = initial();
  const r1 = step(s0, { type: 'start', target: 'recording' }); // acquiring(recording), id=1
  const r2 = step(r1.state, { type: 'start', target: 'calibration' }); // intent flips, no new effect
  assert.deepEqual(r2.effects, []);
  assert.deepEqual(observe(r2.state), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: 1 });
  const r3 = step(r2.state, { type: 'ok', id: 1 }); // in-flight acquire(recording) completes
  assert.deepEqual(observe(r3.state), { phase: 'stopping', owner: 'recording', desired: 'calibration', operationId: 2 });
  assert.deepEqual(r3.effects, [{ type: 'stop', target: 'recording', id: 2 }]);
  const r4 = step(r3.state, { type: 'ok', id: 2 });
  assert.deepEqual(r4.effects, [{ type: 'release', target: 'recording', id: 3 }]);
  assert.deepEqual(observe(r4.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: 3 });
  const r5 = step(r4.state, { type: 'ok', id: 3 });
  assert.deepEqual(r5.effects, [{ type: 'acquire', target: 'calibration', id: 4 }]);
  assert.deepEqual(observe(r5.state), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: 4 });
  const r6 = step(r5.state, { type: 'ok', id: 4 });
  assert.deepEqual(observe(r6.state), { phase: 'active', owner: 'calibration', desired: 'calibration', operationId: null });
  console.log('switchKeepsIdentityThenSwitches: ok');
}

// --- returningToEarlierTarget: desired flips away and back while stopping;
// the in-flight stop/release keep operating on the original owner, and once
// released the model acquires whatever the latest (now reverted) intent is. ---
{
  const active = run([{ type: 'start', target: 'recording' }, { type: 'ok', id: 1 }]);
  const r1 = step(active, { type: 'start', target: 'calibration' }); // stopping(recording), id=2
  const r2 = step(r1.state, { type: 'start', target: 'recording' }); // intent reverts, in-flight stop untouched
  assert.deepEqual(r2.effects, []);
  assert.deepEqual(observe(r2.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: 2 });
  const r3 = step(r2.state, { type: 'ok', id: 2 });
  assert.deepEqual(r3.effects, [{ type: 'release', target: 'recording', id: 3 }]);
  // also exercise an intent change during releasing itself, reverting again
  const r3b = step(r3.state, { type: 'start', target: 'calibration' });
  const r3c = step(r3b.state, { type: 'start', target: 'recording' });
  assert.deepEqual(observe(r3c.state), { phase: 'releasing', owner: 'recording', desired: 'recording', operationId: 3 });
  const r4 = step(r3c.state, { type: 'ok', id: 3 });
  assert.deepEqual(r4.effects, [{ type: 'acquire', target: 'recording', id: 4 }]); // reverted target re-acquired
  const r5 = step(r4.state, { type: 'ok', id: 4 });
  assert.deepEqual(observe(r5.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  console.log('returningToEarlierTarget: ok');
}

// --- stopFailureBlocks: stop failure blocks new acquisition; repeated start
// (even to a different, non-shortcutting target) only updates intent; stale
// ids around the blocked/retry boundary are ignored; explicit retry resumes
// the exact failed stage regardless of where intent ends up. ---
{
  const active = run([{ type: 'start', target: 'recording' }, { type: 'ok', id: 1 }]);
  const r1 = step(active, { type: 'start', target: 'calibration' }); // stopping(recording), id=2
  const r2 = step(r1.state, { type: 'fail', id: 2 });
  assert.deepEqual(r2.effects, []);
  assert.deepEqual(observe(r2.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  // a stale ok for the failed op, and a stale ok for an already-consumed id, are both ignored
  const staleOk = step(r2.state, { type: 'ok', id: 2 });
  assert.equal(staleOk.state, r2.state);
  assert.deepEqual(staleOk.effects, []);
  // repeated start while blocked: real intent change (not a same-target shortcut), no retry
  const r3 = step(r2.state, { type: 'start', target: 'recording' });
  assert.deepEqual(r3.effects, []);
  assert.deepEqual(observe(r3.state), { phase: 'blocked', owner: 'recording', desired: 'recording', operationId: null });
  const r4 = step(r3.state, { type: 'retry' }); // resumes the failed stage: stop(recording), not acquire
  assert.deepEqual(r4.effects, [{ type: 'stop', target: 'recording', id: 3 }]);
  assert.deepEqual(observe(r4.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: 3 });
  // stale ids for the abandoned pre-retry operation (id=2) are ignored even after retry issued id=3
  const staleAfterRetryOk = step(r4.state, { type: 'ok', id: 2 });
  assert.equal(staleAfterRetryOk.state, r4.state);
  const staleAfterRetryFail = step(r4.state, { type: 'fail', id: 2 });
  assert.equal(staleAfterRetryFail.state, r4.state);
  // following through: release, then re-acquire the reverted (latest) intent
  const r5 = step(r4.state, { type: 'ok', id: 3 });
  assert.deepEqual(r5.effects, [{ type: 'release', target: 'recording', id: 4 }]);
  const r6 = step(r5.state, { type: 'ok', id: 4 });
  assert.deepEqual(r6.effects, [{ type: 'acquire', target: 'recording', id: 5 }]);
  console.log('stopFailureBlocks: ok');
}

// --- releaseFailureBlocks: same contract for the release stage ---
{
  const active = run([{ type: 'start', target: 'recording' }, { type: 'ok', id: 1 }]);
  const r1 = step(active, { type: 'start', target: 'calibration' }); // stopping id=2
  const r2 = step(r1.state, { type: 'ok', id: 2 }); // releasing id=3
  const r3 = step(r2.state, { type: 'fail', id: 3 });
  assert.deepEqual(r3.effects, []);
  assert.deepEqual(observe(r3.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  const r4 = step(r3.state, { type: 'retry' });
  assert.deepEqual(r4.effects, [{ type: 'release', target: 'recording', id: 4 }]);
  assert.deepEqual(observe(r4.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: 4 });
  console.log('releaseFailureBlocks: ok');
}

// --- staleCompletionsIgnored: an id that doesn't match the pending op (or no
// pending op at all) leaves state/effects unchanged. ---
{
  const s0 = initial();
  const r1 = step(s0, { type: 'start', target: 'recording' }); // acquiring, id=1
  const staleOk = step(r1.state, { type: 'ok', id: 999 });
  assert.equal(staleOk.state, r1.state);
  assert.deepEqual(staleOk.effects, []);
  const staleFail = step(r1.state, { type: 'fail', id: 999 });
  assert.equal(staleFail.state, r1.state);
  assert.deepEqual(staleFail.effects, []);
  // a stale ok/fail after the real completion (id already consumed) is also ignored
  const r2 = step(r1.state, { type: 'ok', id: 1 }); // active, operationId null
  const lateOk = step(r2.state, { type: 'ok', id: 1 });
  assert.equal(lateOk.state, r2.state);
  assert.deepEqual(lateOk.effects, []);
  console.log('staleCompletionsIgnored: ok');
}

// --- unknownAndProfileEventsIgnored: unknown event types and the independent
// profile-editor event never touch this Mediator's decision state. ---
{
  const active = run([{ type: 'start', target: 'recording' }, { type: 'ok', id: 1 }]);
  const r1 = step(active, { type: 'profile' });
  assert.equal(r1.state, active);
  assert.deepEqual(r1.effects, []);
  const r2 = step(active, { type: 'unknown-event' });
  assert.equal(r2.state, active);
  assert.deepEqual(r2.effects, []);
  console.log('unknownAndProfileEventsIgnored: ok');
}

console.log('ALL CHECKS PASSED');
