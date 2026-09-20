import assert from "node:assert/strict";

const unchanged = (state) => ({ effects: [], state });
const validTarget = (target) =>
  target === "recording" || target === "calibration";
const phaseFor = (kind) => (kind === "stop" ? "stopping" : "releasing");

const withOperation = (state, phase, owner, desired, kind, target) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type: kind }],
    state: {
      ...state,
      desired,
      failed: null,
      id,
      kind,
      nextId: id + 1,
      owner,
      phase,
      target,
    },
  };
};

export const initial = () => ({
  desired: null,
  failed: null,
  id: null,
  kind: null,
  nextId: 1,
  owner: null,
  phase: "idle",
  target: null,
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.id,
  owner: state.owner,
  phase: state.phase,
});

const start = (state, target) => {
  if (!validTarget(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return withOperation(state, "acquiring", null, target, "acquire", target);
  }
  if (state.phase === "active") {
    if (target === state.owner) {
      return unchanged(state);
    }
    return withOperation(
      state,
      "stopping",
      state.owner,
      target,
      "stop",
      state.owner
    );
  }
  return { effects: [], state: { ...state, desired: target } };
};

const retry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return withOperation(
    state,
    phaseFor(state.failed),
    state.owner,
    state.desired,
    state.failed,
    state.owner
  );
};

const succeed = (state) => {
  if (state.kind === "acquire") {
    if (state.target === state.desired) {
      return {
        effects: [],
        state: {
          ...state,
          id: null,
          kind: null,
          owner: state.target,
          phase: "active",
          target: null,
        },
      };
    }
    return withOperation(
      state,
      "stopping",
      state.target,
      state.desired,
      "stop",
      state.target
    );
  }
  if (state.kind === "stop") {
    return withOperation(
      state,
      "releasing",
      state.owner,
      state.desired,
      "release",
      state.owner
    );
  }
  return withOperation(
    state,
    "acquiring",
    null,
    state.desired,
    "acquire",
    state.desired
  );
};

const complete = (state, event) => {
  if (event.id !== state.id || !state.kind) {
    return unchanged(state);
  }
  if (event.type === "ok") {
    return succeed(state);
  }
  if (state.kind === "acquire") {
    return { effects: [], state: { ...initial(), nextId: state.nextId } };
  }
  return {
    effects: [],
    state: {
      ...state,
      failed: state.kind,
      id: null,
      kind: null,
      phase: "blocked",
    },
  };
};

export const transition = (state, event) => {
  if (!event || typeof event !== "object") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event.target);
  }
  if (event.type === "retry") {
    return retry(state);
  }
  if (event.type === "ok" || event.type === "fail") {
    return complete(state, event);
  }
  return unchanged(state);
};

export const selfCheck = () => {
  let state = initial();
  const { effects: firstEffects, state: firstState } = transition(state, {
    target: "recording",
    type: "start",
  });
  state = firstState;
  assert.deepEqual(firstEffects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);

  ({ state } = transition(state, { target: "calibration", type: "start" }));
  ({ state } = transition(state, { target: "recording", type: "start" }));
  const { effects: activeEffects, state: activeState } = transition(state, {
    id: 1,
    type: "ok",
  });
  state = activeState;
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });
  assert.deepEqual(activeEffects, []);

  const { effects: stopEffects, state: stopState } = transition(state, {
    target: "calibration",
    type: "start",
  });
  state = stopState;
  assert.deepEqual(stopEffects, [{ id: 2, target: "recording", type: "stop" }]);
  ({ state } = transition(state, { id: 2, type: "fail" }));
  ({ state } = transition(state, { target: "recording", type: "start" }));
  const { effects: retryEffects, state: retryState } = transition(state, {
    type: "retry",
  });
  state = retryState;
  assert.deepEqual(retryEffects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  assert.equal(transition(state, { id: 2, type: "ok" }).state, state);
  assert.equal(transition(state, { type: "profile" }).state, state);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: 3,
    owner: "recording",
    phase: "stopping",
  });
};

if (process.argv[1] === new URL(import.meta.url).pathname) {
  selfCheck();
  console.log("confirm-e self-check: ok");
}
