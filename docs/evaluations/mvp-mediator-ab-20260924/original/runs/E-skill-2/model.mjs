// Abstract decision model for the recording/calibration device-exclusion Mediator.
// Pure state machine only: it decides, it never performs I/O. `effects` are
// commands for the existing execution boundary to carry out and report back
// via `ok`/`fail` events. The profile editor is an independent flow: it never
// competes for the device, so `profile` events are a no-op here by design.
//
// Phases: idle -> acquiring -> active -> stopping -> releasing -> (blocked) -> ...
// `owner` is reserved (kept) from the moment acquisition succeeds until a
// release succeeds; `desired` is the latest requested target ("latest start
// wins"); `operationId` identifies the single in-flight effect, if any, so
// stale completions can be dropped; `opTarget` is the target that in-flight
// effect concerns (needed because `desired` may keep changing while the
// current acquire/stop/release keeps its own identity); `blockedStage` records
// which stage ('stop' | 'release') must be explicitly retried.

function isTarget(t) {
  return t === 'recording' || t === 'calibration';
}

export function initial() {
  return {
    phase: 'idle',
    owner: null,
    desired: null,
    operationId: null,
    opTarget: null,
    blockedStage: null,
    nextId: 1,
  };
}

export function observe(state) {
  return {
    phase: state.phase,
    owner: state.owner,
    desired: state.desired,
    operationId: state.operationId,
  };
}

export function transition(state, event) {
  if (!event || typeof event.type !== 'string') return unchanged(state);

  switch (event.type) {
    case 'profile':
      // Profile editor is independent: never affects device exclusion.
      return unchanged(state);
    case 'start': {
      if (!isTarget(event.target)) return unchanged(state);
      return handleStart(state, event.target);
    }
    case 'ok':
      return handleCompletion(state, event.id, true);
    case 'fail':
      return handleCompletion(state, event.id, false);
    case 'retry':
      return handleRetry(state);
    default:
      return unchanged(state);
  }
}

function unchanged(state) {
  return { state, effects: [] };
}

function handleStart(state, target) {
  switch (state.phase) {
    case 'idle': {
      const id = state.nextId;
      return {
        state: {
          phase: 'acquiring',
          owner: null,
          desired: target,
          operationId: id,
          opTarget: target,
          blockedStage: null,
          nextId: id + 1,
        },
        effects: [{ type: 'acquire', target, id }],
      };
    }

    // In-flight acquire/stop/release keeps its own identity; a new start
    // only updates the latest-intent field. Repeated starts while blocked
    // update intent too, but do not auto-retry the failed stage.
    case 'acquiring':
    case 'stopping':
    case 'releasing':
    case 'blocked': {
      if (state.desired === target) return unchanged(state);
      return { state: { ...state, desired: target }, effects: [] };
    }

    case 'active': {
      if (state.owner === target) return unchanged(state); // same-owner start is a no-op
      const id = state.nextId;
      return {
        state: {
          phase: 'stopping',
          owner: state.owner, // reserved until release succeeds
          desired: target,
          operationId: id,
          opTarget: state.owner,
          blockedStage: null,
          nextId: id + 1,
        },
        effects: [{ type: 'stop', target: state.owner, id }],
      };
    }

    default:
      return unchanged(state);
  }
}

function handleCompletion(state, id, ok) {
  if (state.operationId === null || state.operationId !== id) return unchanged(state); // stale/unknown

  switch (state.phase) {
    case 'acquiring': {
      if (!ok) {
        // Acquisition failure returns idle without auto-retrying.
        return {
          state: {
            phase: 'idle',
            owner: null,
            desired: null,
            operationId: null,
            opTarget: null,
            blockedStage: null,
            nextId: state.nextId,
          },
          effects: [],
        };
      }
      const acquired = state.opTarget;
      if (state.desired === acquired) {
        return {
          state: {
            phase: 'active',
            owner: acquired,
            desired: acquired,
            operationId: null,
            opTarget: null,
            blockedStage: null,
            nextId: state.nextId,
          },
          effects: [],
        };
      }
      // Owner acquired no longer matches latest intent: stop then release
      // before acquiring the latest target.
      const nid = state.nextId;
      return {
        state: {
          phase: 'stopping',
          owner: acquired,
          desired: state.desired,
          operationId: nid,
          opTarget: acquired,
          blockedStage: null,
          nextId: nid + 1,
        },
        effects: [{ type: 'stop', target: acquired, id: nid }],
      };
    }

    case 'stopping': {
      if (!ok) {
        return {
          state: { ...state, phase: 'blocked', operationId: null, blockedStage: 'stop' },
          effects: [],
        };
      }
      const nid = state.nextId;
      return {
        state: { ...state, phase: 'releasing', operationId: nid, blockedStage: null, nextId: nid + 1 },
        effects: [{ type: 'release', target: state.opTarget, id: nid }],
      };
    }

    case 'releasing': {
      if (!ok) {
        return {
          state: { ...state, phase: 'blocked', operationId: null, blockedStage: 'release' },
          effects: [],
        };
      }
      // Released: acquire the latest desired target (may be the same target
      // that was just released, i.e. returning to an earlier request).
      const nid = state.nextId;
      const target = state.desired;
      return {
        state: {
          phase: 'acquiring',
          owner: null,
          desired: target,
          operationId: nid,
          opTarget: target,
          blockedStage: null,
          nextId: nid + 1,
        },
        effects: [{ type: 'acquire', target, id: nid }],
      };
    }

    default:
      return unchanged(state);
  }
}

function handleRetry(state) {
  if (state.phase !== 'blocked' || state.blockedStage === null) return unchanged(state);
  const nid = state.nextId;
  const stage = state.blockedStage;
  const nextPhase = stage === 'stop' ? 'stopping' : 'releasing';
  return {
    state: { ...state, phase: nextPhase, operationId: nid, blockedStage: null, nextId: nid + 1 },
    effects: [{ type: stage, target: state.opTarget, id: nid }],
  };
}
