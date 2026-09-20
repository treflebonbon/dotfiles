import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);
const unchanged = (state) => ({ effects: [], state });
const validTarget = (target) => targets.has(target);

const command = (state, phase, type, target, extra = {}) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      ...extra,
      nextId: id + 1,
      operationId: id,
      phase,
    },
  };
};

const acquire = (state, target) =>
  command(state, "acquiring", "acquire", target, {
    desired: target,
    failedStage: null,
    owner: null,
    target,
  });

const stop = (state, owner, desired) =>
  command(state, "stopping", "stop", owner, {
    desired,
    failedStage: null,
    owner,
    target: null,
  });

const release = (state) =>
  command(state, "releasing", "release", state.owner, {
    failedStage: null,
    target: null,
  });

const idle = (state) => ({
  effects: [],
  state: {
    ...state,
    desired: null,
    failedStage: null,
    operationId: null,
    owner: null,
    phase: "idle",
    target: null,
  },
});

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  owner: null,
  phase: "idle",
  target: null,
});

export const observe = ({ desired, operationId, owner, phase }) => ({
  desired,
  operationId,
  owner,
  phase,
});

const start = (state, target) => {
  if (!validTarget(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire(state, target);
  }
  if (state.phase === "active") {
    return state.owner === target
      ? unchanged(state)
      : stop(state, state.owner, target);
  }
  if (state.desired === target) {
    return unchanged(state);
  }
  return { effects: [], state: { ...state, desired: target } };
};

const retry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return state.failedStage === "stop"
    ? stop(state, state.owner, state.desired)
    : release(state);
};

const completeAcquisition = (state, type) => {
  if (type === "fail") {
    return idle(state);
  }
  if (state.target !== state.desired) {
    return stop(state, state.target, state.desired);
  }
  return {
    effects: [],
    state: {
      ...state,
      operationId: null,
      owner: state.target,
      phase: "active",
      target: null,
    },
  };
};

const block = (state, failedStage) => ({
  effects: [],
  state: { ...state, failedStage, operationId: null, phase: "blocked" },
});

const complete = (state, event) => {
  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }
  if (state.phase === "acquiring") {
    return completeAcquisition(state, event.type);
  }
  if (state.phase === "stopping") {
    return event.type === "fail" ? block(state, "stop") : release(state);
  }
  if (state.phase === "releasing") {
    return event.type === "fail"
      ? block(state, "release")
      : acquire(state, state.desired);
  }
  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event.target);
  }
  if (event.type === "retry") {
    return retry(state);
  }
  return complete(state, event);
};

const step = (state, event) => {
  const { effects, state: nextState } = transition(state, event);
  return [nextState, effects];
};

export const selfCheck = () => {
  let state = initial();
  let effects;
  const originalState = state;
  const beforeStart = observe(state);
  [state, effects] = step(state, { target: "recording", type: "start" });
  assert.deepEqual(observe(originalState), beforeStart);
  assert.deepEqual(effects, [{ id: 1, target: "recording", type: "acquire" }]);

  [state] = step(state, { target: "calibration", type: "start" });
  [state, effects] = step(state, { target: "recording", type: "start" });
  const { operationId } = observe(state);
  assert.equal(operationId, 1);
  assert.deepEqual(effects, []);

  [state] = step(state, { id: 1, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  [state, effects] = step(state, { target: "calibration", type: "start" });
  assert.deepEqual(effects, [{ id: 2, target: "recording", type: "stop" }]);
  [state] = step(state, { target: "recording", type: "start" });
  [state, effects] = step(state, { id: 2, type: "ok" });
  assert.deepEqual(effects, [{ id: 3, target: "recording", type: "release" }]);

  [state] = step(state, { target: "calibration", type: "start" });
  [state] = step(state, { target: "recording", type: "start" });
  [state] = step(state, { id: 3, type: "fail" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  [state, effects] = step(state, { target: "calibration", type: "start" });
  assert.equal(observe(state).desired, "calibration");
  assert.deepEqual(effects, []);

  [state, effects] = step(state, { type: "retry" });
  assert.deepEqual(effects, [{ id: 4, target: "recording", type: "release" }]);
  [state] = step(state, { target: "recording", type: "start" });
  [, effects] = step(state, { id: 3, type: "fail" });
  assert.deepEqual(effects, []);
  [state, effects] = step(state, { id: 4, type: "ok" });
  assert.deepEqual(effects, [{ id: 5, target: "recording", type: "acquire" }]);
  [state] = step(state, { id: 5, type: "fail" });
  assert.deepEqual(observe(state), observe(initial()));
  [state, effects] = step(state, { target: "calibration", type: "start" });
  assert.deepEqual(effects, [
    { id: 6, target: "calibration", type: "acquire" },
  ]);

  const [profileState, profileEffects] = step(state, { type: "profile" });
  assert.equal(profileState, state);
  assert.deepEqual(profileEffects, []);
};

if (process.argv[1] === new URL(import.meta.url).pathname) {
  selfCheck();
}
