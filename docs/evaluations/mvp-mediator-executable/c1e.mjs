import assert from "node:assert/strict";

const targetSet = new Set(["recording", "calibration"]);
const stageType = {
  acquiring: "acquire",
  releasing: "release",
  stopping: "stop",
};
const retryPhase = { release: "releasing", stop: "stopping" };

export const initial = () => ({
  desired: null,
  nextId: 1,
  operation: null,
  owner: null,
  phase: "idle",
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operation?.id ?? null,
  owner: state.owner,
  phase: state.phase,
});

const unchanged = (state) => ({ effects: [], state });

const begin = (state, phase, target) => {
  const id = state.nextId;
  const type = stageType[phase];
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      nextId: id + 1,
      operation: { id, target, type },
      phase,
    },
  };
};

const acquire = (state, target) =>
  begin({ ...state, owner: null }, "acquiring", target);

const start = (state, event) => {
  if (!targetSet.has(event.target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire({ ...state, desired: event.target }, event.target);
  }
  if (state.phase === "active" && state.owner === event.target) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return begin({ ...state, desired: event.target }, "stopping", state.owner);
  }
  return { effects: [], state: { ...state, desired: event.target } };
};

const fail = (state, operation) => {
  if (operation.type === "acquire") {
    return {
      effects: [],
      state: { ...state, operation: null, owner: null, phase: "idle" },
    };
  }
  return {
    effects: [],
    state: {
      ...state,
      failedStage: operation.type,
      operation: null,
      phase: "blocked",
    },
  };
};

const succeed = (state, operation) => {
  if (operation.type === "acquire") {
    if (operation.target === state.desired) {
      return {
        effects: [],
        state: {
          ...state,
          operation: null,
          owner: operation.target,
          phase: "active",
        },
      };
    }
    return begin(
      { ...state, owner: operation.target },
      "stopping",
      operation.target
    );
  }
  if (operation.type === "stop") {
    return begin(state, "releasing", state.owner);
  }
  return acquire({ ...state, owner: null }, state.desired);
};

const completion = (state, event) => {
  if (state.operation?.id !== event.id) {
    return unchanged(state);
  }
  return event.type === "fail"
    ? fail(state, state.operation)
    : succeed(state, state.operation);
};

export const transition = (state, event) => {
  if (!event || typeof event !== "object") {
    return unchanged(state);
  }
  if (event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event);
  }
  if (event.type === "retry") {
    return state.phase === "blocked"
      ? begin(state, retryPhase[state.failedStage], state.owner)
      : unchanged(state);
  }
  if (event.type === "ok" || event.type === "fail") {
    return completion(state, event);
  }
  return unchanged(state);
};

const selfCheck = () => {
  let state = initial();
  const profile = transition(state, { type: "profile" });
  assert.equal(profile.state, state);
  assert.deepEqual(profile.effects, []);
  let step = transition(state, { target: "recording", type: "start" });
  assert.deepEqual(step.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  ({ state } = step);

  step = transition(state, { id: 1, type: "ok" });
  ({ state } = step);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  step = transition(state, { target: "calibration", type: "start" });
  assert.deepEqual(step.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  step = transition(step.state, { id: 2, type: "ok" });
  assert.deepEqual(step.effects, [
    { id: 3, target: "recording", type: "release" },
  ]);
  step = transition(step.state, { id: 3, type: "ok" });
  assert.deepEqual(step.effects, [
    { id: 4, target: "calibration", type: "acquire" },
  ]);
  step = transition(step.state, { id: 4, type: "ok" });
  assert.equal(observe(step.state).owner, "calibration");

  ({ state } = transition(initial(), { target: "recording", type: "start" }));
  step = transition(state, { target: "calibration", type: "start" });
  assert.equal(step.effects.length, 0);
  step = transition(step.state, { target: "recording", type: "start" });
  assert.equal(step.effects.length, 0);
  const { state: acquiredState } = transition(step.state, {
    id: 1,
    type: "ok",
  });
  assert.equal(observe(acquiredState).owner, "recording");

  ({ state } = transition(initial(), { target: "recording", type: "start" }));
  ({ state } = transition(state, { id: 1, type: "ok" }));
  ({ state } = transition(state, { target: "calibration", type: "start" }));
  ({ state } = transition(state, { id: 2, type: "fail" }));
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  step = transition(state, { target: "recording", type: "start" });
  assert.equal(step.effects.length, 0);
  step = transition(step.state, { type: "retry" });
  assert.deepEqual(step.effects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  const { state: staleState } = transition(step.state, { id: 2, type: "ok" });
  assert.equal(staleState, step.state);

  ({ state } = transition(initial(), { target: "recording", type: "start" }));
  ({ state } = transition(state, { id: 1, type: "ok" }));
  ({ state } = transition(state, { target: "calibration", type: "start" }));
  ({ state } = transition(state, { id: 2, type: "ok" }));
  ({ state } = transition(state, { id: 3, type: "fail" }));
  step = transition(state, { type: "retry" });
  assert.deepEqual(step.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
};

if (process.argv[1] && import.meta.url.endsWith(process.argv[1])) {
  selfCheck();
  console.log("c1e self-check: OK");
}
