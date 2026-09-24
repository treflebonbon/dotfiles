// Abstract decision model for the recording/calibration exclusion Mediator.
// Pure functions only: all decision state lives in `state`, nothing hidden in
// closures/module globals/WeakMaps. See memo.md for responsibility mapping.

export function initial() {
  return {
    phase: 'idle',        // idle | acquiring | active | stopping | releasing | blocked
    owner: null,          // 'recording' | 'calibration' | null - resource currently held
    desired: null,        // 'recording' | 'calibration' | null - latest requested target
    operationId: null,    // id of the in-flight command, or null
    pendingTarget: null,  // target the in-flight command (acquire/stop/release) is for
    blockedStage: null,   // 'stopping' | 'releasing' | null - which stage to retry
    nextId: 1,            // monotonic id issuance, never reset/reused within a run
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
  switch (event.type) {
    case 'start':
      return handleStart(state, event.target);
    case 'ok':
      return handleCompletion(state, event.id);
    case 'fail':
      return handleFailure(state, event.id);
    case 'retry':
      return handleRetry(state);
    default:
      // unknown events, including 'profile' (independent flow's own event):
      // this Mediator's decision state is untouched.
      return unchanged(state);
  }
}

function unchanged(state) {
  return { state, effects: [] };
}

function issueId(state) {
  return [state.nextId, { ...state, nextId: state.nextId + 1 }];
}

function idleState(nextId) {
  return {
    phase: 'idle', owner: null, desired: null,
    operationId: null, pendingTarget: null, blockedStage: null,
    nextId,
  };
}

function handleStart(state, target) {
  switch (state.phase) {
    case 'idle': {
      const [id, s] = issueId(state);
      return {
        state: { ...s, phase: 'acquiring', desired: target, operationId: id, pendingTarget: target },
        effects: [{ type: 'acquire', target, id }],
      };
    }
    case 'active': {
      if (target === state.owner) return unchanged(state); // same-owner start is a no-op
      const [id, s] = issueId(state);
      return {
        state: { ...s, phase: 'stopping', desired: target, operationId: id, pendingTarget: state.owner },
        effects: [{ type: 'stop', target: state.owner, id }],
      };
    }
    case 'acquiring':
    case 'stopping':
    case 'releasing':
    case 'blocked':
      // latest start wins as intent; in-flight/blocked stage keeps its identity,
      // no new effect is issued (blocked state: intent updates, no auto-retry).
      if (target === state.desired) return unchanged(state);
      return { state: { ...state, desired: target }, effects: [] };
    default:
      return unchanged(state);
  }
}

function handleCompletion(state, id) {
  if (state.operationId === null || id !== state.operationId) return unchanged(state); // stale
  switch (state.phase) {
    case 'acquiring': {
      const owner = state.pendingTarget;
      if (state.desired === owner) {
        return {
          state: { ...state, phase: 'active', owner, operationId: null, pendingTarget: null },
          effects: [],
        };
      }
      const [newId, s] = issueId(state);
      return {
        state: { ...s, phase: 'stopping', owner, operationId: newId, pendingTarget: owner },
        effects: [{ type: 'stop', target: owner, id: newId }],
      };
    }
    case 'stopping': {
      const [newId, s] = issueId(state);
      return {
        state: { ...s, phase: 'releasing', operationId: newId }, // pendingTarget (owner) unchanged
        effects: [{ type: 'release', target: state.pendingTarget, id: newId }],
      };
    }
    case 'releasing': {
      const [newId, s] = issueId(state);
      return {
        state: { ...s, phase: 'acquiring', owner: null, operationId: newId, pendingTarget: state.desired },
        effects: [{ type: 'acquire', target: state.desired, id: newId }],
      };
    }
    default:
      return unchanged(state);
  }
}

function handleFailure(state, id) {
  if (state.operationId === null || id !== state.operationId) return unchanged(state); // stale
  switch (state.phase) {
    case 'acquiring':
      // acquisition failure: nothing was ever owned; return idle, no auto-retry.
      return { state: idleState(state.nextId), effects: [] };
    case 'stopping':
      return {
        state: { ...state, phase: 'blocked', operationId: null, blockedStage: 'stopping' },
        effects: [],
      };
    case 'releasing':
      return {
        state: { ...state, phase: 'blocked', operationId: null, blockedStage: 'releasing' },
        effects: [],
      };
    default:
      return unchanged(state);
  }
}

function handleRetry(state) {
  if (state.phase !== 'blocked') return unchanged(state);
  const [id, s] = issueId(state);
  if (state.blockedStage === 'stopping') {
    return {
      state: { ...s, phase: 'stopping', operationId: id, blockedStage: null },
      effects: [{ type: 'stop', target: s.pendingTarget, id }],
    };
  }
  if (state.blockedStage === 'releasing') {
    return {
      state: { ...s, phase: 'releasing', operationId: id, blockedStage: null },
      effects: [{ type: 'release', target: s.pendingTarget, id }],
    };
  }
  return unchanged(state);
}
