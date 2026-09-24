// Abstract decision model for device-exclusion between recording/calibration.
// Pure state machine: no I/O, no module-global mutable state. Emits effects
// as data; the real execution boundary (Effect runtime) performs them and
// reports back via 'ok'/'fail' events.

function isTarget(v) {
  return v === 'recording' || v === 'calibration';
}

function freeze(state) {
  return Object.freeze(state);
}

// Builds a new state object from `state` with `patch` fields overridden.
// Never mutates `state`.
function next(state, patch) {
  return freeze({
    phase: 'phase' in patch ? patch.phase : state.phase,
    owner: 'owner' in patch ? patch.owner : state.owner,
    desired: 'desired' in patch ? patch.desired : state.desired,
    operationId: 'operationId' in patch ? patch.operationId : state.operationId,
    pendingTarget: 'pendingTarget' in patch ? patch.pendingTarget : state.pendingTarget,
    stage: 'stage' in patch ? patch.stage : state.stage,
    nextId: 'nextId' in patch ? patch.nextId : state.nextId,
  });
}

function unchanged(state) {
  return { state, effects: [] };
}

export function initial() {
  return freeze({
    phase: 'idle',
    owner: null,
    desired: null,
    operationId: null, // id of the in-flight effect, or null if none pending
    pendingTarget: null, // target of the current/failed operation, or null
    stage: null, // 'acquire' | 'stop' | 'release' | null: effect type of pendingTarget's operation
    nextId: 1, // monotonic counter; every emitted effect id is unique within the run
  });
}

export function transition(state, event) {
  if (!event || typeof event.type !== 'string') return unchanged(state);

  switch (event.type) {
    case 'start':
      return handleStart(state, event.target);
    case 'ok':
      return handleCompletion(state, event.id, true);
    case 'fail':
      return handleCompletion(state, event.id, false);
    case 'retry':
      return handleRetry(state);
    case 'profile':
      // Profile editor is independent of device exclusion; it never touches this machine.
      return unchanged(state);
    default:
      return unchanged(state);
  }
}

function handleStart(state, target) {
  if (!isTarget(target)) return unchanged(state);

  switch (state.phase) {
    case 'idle': {
      const id = state.nextId;
      const s = next(state, {
        phase: 'acquiring',
        desired: target,
        operationId: id,
        pendingTarget: target,
        stage: 'acquire',
        nextId: id + 1,
      });
      return { state: s, effects: [{ type: 'acquire', target, id }] };
    }
    case 'active': {
      if (target === state.owner) return unchanged(state); // same-owner start is a no-op
      const id = state.nextId;
      const s = next(state, {
        phase: 'stopping',
        desired: target,
        operationId: id,
        pendingTarget: state.owner,
        stage: 'stop',
        nextId: id + 1,
      });
      return { state: s, effects: [{ type: 'stop', target: state.owner, id }] };
    }
    case 'acquiring':
    case 'stopping':
    case 'releasing':
    case 'blocked': {
      // Latest start request wins: update intent only. In-flight work (or the
      // blocked failure) keeps its identity unchanged; no new effect issued.
      if (target === state.desired) return unchanged(state);
      return { state: next(state, { desired: target }), effects: [] };
    }
    default:
      return unchanged(state);
  }
}

function handleCompletion(state, id, ok) {
  // Stale/unknown completions (no pending op, or id doesn't match it) are ignored.
  if (state.operationId === null || id !== state.operationId) return unchanged(state);

  return ok ? handleOk(state) : handleFail(state);
}

function handleOk(state) {
  switch (state.phase) {
    case 'acquiring': {
      // Acquisition just succeeded for pendingTarget.
      if (state.pendingTarget === state.desired) {
        // Keep this owner: it matches latest intent.
        const s = next(state, {
          phase: 'active',
          owner: state.pendingTarget,
          operationId: null,
          pendingTarget: null,
          stage: null,
        });
        return { state: s, effects: [] };
      }
      // Intent moved on while acquiring: stop then release before acquiring the latest target.
      const newId = state.nextId;
      const s = next(state, {
        phase: 'stopping',
        owner: state.pendingTarget,
        operationId: newId,
        stage: 'stop',
        nextId: newId + 1,
      });
      return { state: s, effects: [{ type: 'stop', target: state.pendingTarget, id: newId }] };
    }
    case 'stopping': {
      const newId = state.nextId;
      const s = next(state, {
        phase: 'releasing',
        operationId: newId,
        stage: 'release',
        nextId: newId + 1,
      });
      return { state: s, effects: [{ type: 'release', target: state.pendingTarget, id: newId }] };
    }
    case 'releasing': {
      // Released; nothing is reserved anymore. Acquire whatever is currently desired.
      const newId = state.nextId;
      const s = next(state, {
        phase: 'acquiring',
        owner: null,
        operationId: newId,
        pendingTarget: state.desired,
        stage: 'acquire',
        nextId: newId + 1,
      });
      return { state: s, effects: [{ type: 'acquire', target: state.desired, id: newId }] };
    }
    default:
      return unchanged(state);
  }
}

function handleFail(state) {
  switch (state.phase) {
    case 'acquiring': {
      // Acquisition failure returns idle without auto-retrying.
      const s = next(state, {
        phase: 'idle',
        owner: null,
        desired: null,
        operationId: null,
        pendingTarget: null,
        stage: null,
      });
      return { state: s, effects: [] };
    }
    case 'stopping':
    case 'releasing': {
      // Stop/release failure blocks new acquisition until explicit retry of the failed stage.
      // Old owner (pendingTarget) and stage stay reserved for retry().
      const s = next(state, { phase: 'blocked', operationId: null });
      return { state: s, effects: [] };
    }
    default:
      return unchanged(state);
  }
}

function handleRetry(state) {
  if (state.phase !== 'blocked') return unchanged(state);
  const newId = state.nextId;
  if (state.stage === 'stop') {
    const s = next(state, { phase: 'stopping', operationId: newId, nextId: newId + 1 });
    return { state: s, effects: [{ type: 'stop', target: state.pendingTarget, id: newId }] };
  }
  if (state.stage === 'release') {
    const s = next(state, { phase: 'releasing', operationId: newId, nextId: newId + 1 });
    return { state: s, effects: [{ type: 'release', target: state.pendingTarget, id: newId }] };
  }
  return unchanged(state);
}

export function observe(state) {
  return {
    phase: state.phase,
    owner: state.owner,
    desired: state.desired,
    operationId: state.operationId,
  };
}
