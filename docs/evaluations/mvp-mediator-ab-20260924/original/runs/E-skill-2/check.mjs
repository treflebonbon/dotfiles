// Self-check for model.mjs. No framework: plain assertions, run with `node check.mjs`.
//
// Every transition below runs through `step()`, which both (a) advances the
// scenario and (b) proves purity for that exact (state, event) pair using the
// sequence the skill prescribes: call transition twice from the same original
// input, assert the input was untouched after each call, snapshot the first
// result before the second call, and assert the second call reproduces it.
// `structuredClone` is the snapshot, `assert.deepStrictEqual` is the equality
// check. A thrown AssertionError aborts the script with a non-zero exit code,
// so reaching "ALL CHECKS PASSED" is itself the evidence, not a hardcoded flag.
import assert from 'node:assert/strict';
import { initial, transition, observe } from './model.mjs';

let stepCount = 0;
const log = [];

function step(state, event, label) {
  const before = structuredClone(state);
  const first = transition(state, event);
  assert.deepStrictEqual(state, before, `${label}: state mutated by 1st transition() call`);
  const firstBefore = structuredClone(first);
  const second = transition(state, event);
  assert.deepStrictEqual(state, before, `${label}: state mutated by 2nd transition() call`);
  assert.deepStrictEqual(first, firstBefore, `${label}: 1st result changed after 2nd call`);
  assert.deepStrictEqual(second, firstBefore, `${label}: 2nd call result != 1st call result`);
  stepCount += 1;
  log.push(`[step] ${label} :: event=${JSON.stringify(event)} -> observe=${JSON.stringify(observe(second.state))} effects=${JSON.stringify(second.effects)}`);
  return second;
}

function note(caseName, text) {
  log.push(`[case] ${caseName}: ${text}`);
}

// ---- normalPath (independent: fresh state, one start, one normal completion)
{
  const s0 = initial();
  let r = step(s0, { type: 'start', target: 'recording' }, 'normalPath.start');
  assert.deepStrictEqual(observe(r.state), { phase: 'acquiring', owner: null, desired: 'recording', operationId: 1 });
  assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'recording', id: 1 }]);
  r = step(r.state, { type: 'ok', id: 1 }, 'normalPath.ok');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  assert.deepStrictEqual(r.effects, []);
  note('normalPath', 'start(recording) -> acquire#1 -> ok(1) -> active/recording');
}

// ---- caseAcquireSwitch: latest-start-wins while acquiring, target differs --
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'acqSwitch.start1');
  const op1 = r.effects[0].id;
  r = step(r.state, { type: 'start', target: 'calibration' }, 'acqSwitch.start2');
  assert.deepStrictEqual(observe(r.state), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: op1 });
  assert.deepStrictEqual(r.effects, [], 'in-flight acquire keeps its id; no new effect');

  r = step(r.state, { type: 'ok', id: op1 }, 'acqSwitch.ok_mismatch');
  const opStop = r.effects[0]?.id;
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'calibration', operationId: opStop });
  assert.deepStrictEqual(r.effects, [{ type: 'stop', target: 'recording', id: opStop }]);

  r = step(r.state, { type: 'ok', id: opStop }, 'acqSwitch.ok_stop');
  const opRelease = r.effects[0].id;
  assert.deepStrictEqual(r.effects, [{ type: 'release', target: 'recording', id: opRelease }]);

  r = step(r.state, { type: 'ok', id: opRelease }, 'acqSwitch.ok_release');
  const opAcq2 = r.effects[0].id;
  assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: opAcq2 }]);

  r = step(r.state, { type: 'ok', id: opAcq2 }, 'acqSwitch.ok_acquire2');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'calibration', desired: 'calibration', operationId: null });
  note('caseAcquireSwitch', `acquired recording != desired calibration -> stop#${opStop} -> release#${opRelease} -> acquire#${opAcq2} -> active/calibration`);
}

// ---- caseAcquireReturn: switch away then back before the acquire completes -
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'acqReturn.start1');
  const op1 = r.effects[0].id;
  r = step(r.state, { type: 'start', target: 'calibration' }, 'acqReturn.start2');
  r = step(r.state, { type: 'start', target: 'recording' }, 'acqReturn.start3_back');
  assert.deepStrictEqual(observe(r.state), { phase: 'acquiring', owner: null, desired: 'recording', operationId: op1 });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'ok', id: op1 }, 'acqReturn.ok');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  assert.deepStrictEqual(r.effects, [], 'desired matches what was acquired again: no stop/release needed');
  note('caseAcquireReturn', 'start(rec)->start(cal)->start(rec) then ok(1) -> active/recording directly, no stop effect emitted');
}

// ---- caseAcquireFailAfterSwitch: acquisition fails after intent changed ----
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'acqFailSwitch.start1');
  const op1 = r.effects[0].id;
  r = step(r.state, { type: 'start', target: 'calibration' }, 'acqFailSwitch.start2');
  r = step(r.state, { type: 'fail', id: op1 }, 'acqFailSwitch.fail');
  assert.deepStrictEqual(observe(r.state), { phase: 'idle', owner: null, desired: null, operationId: null });
  assert.deepStrictEqual(r.effects, [], 'no auto-acquire of the now-latest target (calibration)');
  note('caseAcquireFailAfterSwitch', 'fail(1) while desired had moved to calibration -> idle, desired reset to null, no auto-retry of calibration');
}

// ---- caseStopReleaseSwitch: latest intent flips during stop AND release ---
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'stopRelSwitch.start1');
  r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'stopRelSwitch.ok_acquire'); // active/recording
  r = step(r.state, { type: 'start', target: 'calibration' }, 'stopRelSwitch.start_cal'); // stopping
  const opStop = r.effects[0].id;
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'calibration', operationId: opStop });

  // flip back to 'recording' while the stop is still in flight: id/effects unaffected
  r = step(r.state, { type: 'start', target: 'recording' }, 'stopRelSwitch.flip_during_stop');
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: opStop });
  assert.deepStrictEqual(r.effects, [], 'in-flight stop keeps its identity regardless of desired flips');

  r = step(r.state, { type: 'ok', id: opStop }, 'stopRelSwitch.ok_stop');
  const opRelease = r.effects[0].id;
  assert.deepStrictEqual(r.effects, [{ type: 'release', target: 'recording', id: opRelease }], 'stop completion always proceeds to release, independent of desired');

  // flip again to 'calibration' while the release is in flight
  r = step(r.state, { type: 'start', target: 'calibration' }, 'stopRelSwitch.flip_during_release');
  assert.deepStrictEqual(observe(r.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: opRelease });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'ok', id: opRelease }, 'stopRelSwitch.ok_release');
  const opAcq = r.effects[0].id;
  assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: opAcq }], 'release completion acquires whatever is desired at that moment');
  r = step(r.state, { type: 'ok', id: opAcq }, 'stopRelSwitch.ok_acquire2');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'calibration', desired: 'calibration', operationId: null });
  note('caseStopReleaseSwitch', `flips during stopping and releasing never change operationId/effects mid-stage; final target follows desired at each completion (stop#${opStop}, release#${opRelease}, acquire#${opAcq})`);
}

// ---- caseSameOwnerNoOp: same-owner start while active is a no-op ----------
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'sameOwner.start');
  r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'sameOwner.ok');
  const activeState = r.state;
  const out = step(activeState, { type: 'start', target: 'recording' }, 'sameOwner.noop');
  assert.deepStrictEqual(out.state, activeState);
  assert.deepStrictEqual(out.effects, []);
  note('caseSameOwnerNoOp', 'active/owner=recording + start(recording) -> unchanged state, effects=[]');
}

// ---- caseStopFailure: blocked, repeated starts, stale ids, explicit retry -
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'stopFail.start1');
  r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'stopFail.ok_acquire'); // active/recording
  r = step(r.state, { type: 'start', target: 'calibration' }, 'stopFail.start_cal'); // stopping
  const opStop = r.effects[0].id;

  r = step(r.state, { type: 'fail', id: opStop }, 'stopFail.fail');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  assert.deepStrictEqual(r.effects, []);
  note('caseStopFailure', `fail(stop#${opStop}) -> blocked, owner stays reserved=recording, no new acquisition until retry`);

  // the very id that just failed arrives again while blocked: operationId is
  // already null, so this is stale by construction and must be a no-op.
  r = step(r.state, { type: 'ok', id: opStop }, 'stopFail.stale_ok_of_failed_id_while_blocked');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  assert.deepStrictEqual(r.effects, []);

  // repeated start while blocked updates intent, does not auto-retry
  r = step(r.state, { type: 'start', target: 'recording' }, 'stopFail.repeated_start_1');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'recording', operationId: null });
  assert.deepStrictEqual(r.effects, []);
  r = step(r.state, { type: 'start', target: 'recording' }, 'stopFail.repeated_start_2_same_target');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'recording', operationId: null });
  assert.deepStrictEqual(r.effects, []);
  note('caseStopFailure_repeatedStart', 'two repeated start()s while blocked only ever update desired; no effect is ever produced');

  // explicit retry re-issues the failed stage with a fresh id
  r = step(r.state, { type: 'retry' }, 'stopFail.retry');
  const opStop2 = r.effects[0].id;
  assert.notEqual(opStop2, opStop);
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: opStop2 });
  assert.deepStrictEqual(r.effects, [{ type: 'stop', target: 'recording', id: opStop2 }]);
  note('caseStopFailure_retry', `retry -> stop#${opStop2} (fresh id, != failed id ${opStop}), same target=recording`);

  // the failed id arriving again now that a new stage is in flight: still stale
  r = step(r.state, { type: 'ok', id: opStop }, 'stopFail.stale_ok_of_old_failed_id_after_retry');
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: opStop2 });
  assert.deepStrictEqual(r.effects, []);
  r = step(r.state, { type: 'fail', id: opStop }, 'stopFail.stale_fail_of_old_failed_id_after_retry');
  assert.deepStrictEqual(observe(r.state), { phase: 'stopping', owner: 'recording', desired: 'recording', operationId: opStop2 });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'ok', id: opStop2 }, 'stopFail.ok_stop2');
  const opRelease = r.effects[0].id;
  r = step(r.state, { type: 'ok', id: opRelease }, 'stopFail.ok_release');
  const opAcq = r.effects[0].id;
  assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'recording', id: opAcq }]);
  r = step(r.state, { type: 'ok', id: opAcq }, 'stopFail.ok_acquire2');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  note('caseStopFailure_recovery', `full recovery chain re-lands on active/recording (returning to the earlier requested target): stop#${opStop2}, release#${opRelease}, acquire#${opAcq}`);
}

// ---- caseReleaseFailure: blocked, retry, stale ids, lands on new target ---
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'relFail.start1');
  r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'relFail.ok_acquire'); // active/recording
  r = step(r.state, { type: 'start', target: 'calibration' }, 'relFail.start_cal'); // stopping
  const opStop = r.effects[0].id;
  r = step(r.state, { type: 'ok', id: opStop }, 'relFail.ok_stop'); // releasing
  const opRelease = r.effects[0].id;

  // stale: the stop-stage id, which already completed successfully, is
  // redelivered late while release is now in flight -- the most realistic
  // stale event in an Effect runtime (a slow completion racing the next stage).
  r = step(r.state, { type: 'ok', id: opStop }, 'relFail.stale_ok_of_completed_stop_id_during_releasing');
  assert.deepStrictEqual(observe(r.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: opRelease });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'fail', id: opRelease }, 'relFail.fail');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  assert.deepStrictEqual(r.effects, []);
  note('caseReleaseFailure', `fail(release#${opRelease}) -> blocked, owner stays reserved=recording (release did not take effect)`);

  // stale: the failed release id arriving again while blocked
  r = step(r.state, { type: 'ok', id: opRelease }, 'relFail.stale_ok_while_blocked');
  assert.deepStrictEqual(observe(r.state), { phase: 'blocked', owner: 'recording', desired: 'calibration', operationId: null });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'retry' }, 'relFail.retry');
  const opRelease2 = r.effects[0].id;
  assert.notEqual(opRelease2, opRelease);
  assert.deepStrictEqual(observe(r.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: opRelease2 });
  assert.deepStrictEqual(r.effects, [{ type: 'release', target: 'recording', id: opRelease2 }], 'retry re-issues the failed stage (release) with a fresh id, same target');
  note('caseReleaseFailure_retry', `retry -> release#${opRelease2} (fresh id, != failed id ${opRelease}), same target=recording`);

  // stale: old failed release id arriving again now that a new one is in flight
  r = step(r.state, { type: 'fail', id: opRelease }, 'relFail.stale_fail_of_old_id_after_retry');
  assert.deepStrictEqual(observe(r.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: opRelease2 });
  assert.deepStrictEqual(r.effects, []);

  // stale: an id that was never issued at all, delivered during releasing
  r = step(r.state, { type: 'ok', id: opRelease2 + 1000 }, 'relFail.stale_never_issued_id_during_releasing');
  assert.deepStrictEqual(observe(r.state), { phase: 'releasing', owner: 'recording', desired: 'calibration', operationId: opRelease2 });
  assert.deepStrictEqual(r.effects, []);

  r = step(r.state, { type: 'ok', id: opRelease2 }, 'relFail.ok_release2');
  const opAcq = r.effects[0].id;
  assert.deepStrictEqual(observe(r.state), { phase: 'acquiring', owner: null, desired: 'calibration', operationId: opAcq });
  assert.deepStrictEqual(r.effects, [{ type: 'acquire', target: 'calibration', id: opAcq }]);
  r = step(r.state, { type: 'ok', id: opAcq }, 'relFail.ok_acquire2');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'calibration', desired: 'calibration', operationId: null });
  note('caseReleaseFailure_recovery', `release retry succeeds -> acquire#${opAcq} calibration -> active/calibration`);
}

// ---- caseAcquisitionFailure: returns idle, ids never reused ---------------
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'acqFail.start');
  const opAcq = r.effects[0].id;
  r = step(r.state, { type: 'fail', id: opAcq }, 'acqFail.fail');
  assert.deepStrictEqual(observe(r.state), { phase: 'idle', owner: null, desired: null, operationId: null });
  assert.deepStrictEqual(r.effects, []);
  note('caseAcquisitionFailure', `fail(acquire#${opAcq}) -> idle/owner=null/desired=null, no new effect (no auto-retry)`);

  r = step(r.state, { type: 'start', target: 'recording' }, 'acqFail.start_again');
  assert.equal(r.effects[0].id, opAcq + 1, 'ids stay monotonic/unique across a failure');
  note('caseAcquisitionFailure_idUniqueness', `failed id ${opAcq} is never reused; the next start got id ${r.effects[0].id}`);
}

// ---- caseStaleCompletion: an id that was never issued -------------------
{
  let r = step(initial(), { type: 'start', target: 'recording' }, 'staleNever.start');
  const realId = r.effects[0].id;
  const neverIssuedId = realId + 999;
  const acquiring = r.state;

  r = step(acquiring, { type: 'ok', id: neverIssuedId }, 'staleNever.ok');
  assert.deepStrictEqual(r.state, acquiring);
  assert.deepStrictEqual(r.effects, []);
  r = step(acquiring, { type: 'fail', id: neverIssuedId }, 'staleNever.fail');
  assert.deepStrictEqual(r.state, acquiring);
  assert.deepStrictEqual(r.effects, []);
  note('caseStaleCompletion_neverIssuedId', `ok/fail(id=${neverIssuedId}, never issued) while pending id=${realId} -> state/effects unchanged`);

  r = step(acquiring, { type: 'ok', id: realId }, 'staleNever.real_ok_still_works');
  assert.deepStrictEqual(observe(r.state), { phase: 'active', owner: 'recording', desired: 'recording', operationId: null });
  note('caseStaleCompletion_realStillWorks', `ok(${realId}) after unrelated stale notifications still lands on active/recording`);
}

// ---- caseProfile: independent flow, no-op across phases -------------------
{
  const phases = [];
  {
    phases.push(['idle', initial()]);
  }
  {
    let r = step(initial(), { type: 'start', target: 'recording' }, 'profile.setup_acquiring');
    phases.push(['acquiring', r.state]);
    r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'profile.setup_active');
    phases.push(['active', r.state]);
    r = step(r.state, { type: 'start', target: 'calibration' }, 'profile.setup_stopping');
    phases.push(['stopping', r.state]);
    r = step(r.state, { type: 'ok', id: r.effects[0].id }, 'profile.setup_releasing');
    phases.push(['releasing', r.state]);
    r = step(r.state, { type: 'fail', id: r.effects[0].id }, 'profile.setup_blocked');
    phases.push(['blocked', r.state]);
  }
  for (const [phaseName, st] of phases) {
    const out = step(st, { type: 'profile' }, `profile.noop_${phaseName}`);
    assert.deepStrictEqual(out.state, st, `profile must not change ${phaseName} state`);
    assert.deepStrictEqual(out.effects, []);
  }
  note('caseProfileIndependent', `profile event is a no-op across phases [${phases.map(p => p[0]).join(', ')}]; the profile editor holds no state in this model`);
}

// ---- caseUnknownAndOutOfPhaseRetry ----------------------------------------
{
  const s0 = initial();
  let r = step(s0, { type: 'bogus' }, 'unknown.event');
  assert.deepStrictEqual(r, { state: s0, effects: [] });
  r = step(s0, { type: 'retry' }, 'unknown.retryWithoutBlocked');
  assert.deepStrictEqual(r, { state: s0, effects: [] });
  note('caseUnknownEvents', 'unknown event type, and retry while not blocked, both leave state/effects unchanged');
}

console.log(log.join('\n'));
console.log(`\n${stepCount} purity-checked transitions executed, all assertions passed.`);
console.log('ALL CHECKS PASSED');
