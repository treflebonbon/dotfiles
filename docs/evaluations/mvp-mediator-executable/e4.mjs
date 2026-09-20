import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  operationTarget: null,
  owner: null,
  phase: "idle",
  stage: null,
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const unchanged = (state) => ({ effects: [], state });

const withOperation = (state, phase, stage, target, owner = state.owner) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type: stage }],
    state: {
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      operationTarget: target,
      owner,
      phase,
      stage,
    },
  };
};

const acquire = (state, target) =>
  withOperation(state, "acquiring", "acquire", target, null);

const stop = (state) => withOperation(state, "stopping", "stop", state.owner);

const release = (state) =>
  withOperation(state, "releasing", "release", state.owner);

const idle = (state) => ({
  ...state,
  desired: null,
  failedStage: null,
  operationId: null,
  operationTarget: null,
  owner: null,
  phase: "idle",
  stage: null,
});

const blocked = (state, failedStage) => ({
  ...state,
  failedStage,
  operationId: null,
  operationTarget: null,
  phase: "blocked",
  stage: null,
});

const transitionStart = (state, event) => {
  if (!targets.has(event.target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire(state, event.target);
  }
  if (state.phase === "active" && event.target === state.owner) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return stop({ ...state, desired: event.target });
  }
  if (state.desired === event.target) {
    return unchanged(state);
  }
  return { effects: [], state: { ...state, desired: event.target } };
};

const transitionRetry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return state.failedStage === "stop" ? stop(state) : release(state);
};

const transitionCompletion = (state, event) => {
  const succeeded = event.type === "ok";
  if (state.phase === "acquiring") {
    if (!succeeded) {
      return { effects: [], state: idle(state) };
    }
    const acquired = state.operationTarget;
    const settled = {
      ...state,
      operationId: null,
      operationTarget: null,
      owner: acquired,
      phase: "active",
      stage: null,
    };
    return acquired === state.desired
      ? { effects: [], state: settled }
      : stop(settled);
  }

  if (state.phase === "stopping") {
    return succeeded
      ? release(state)
      : { effects: [], state: blocked(state, "stop") };
  }

  if (state.phase === "releasing") {
    if (!succeeded) {
      return { effects: [], state: blocked(state, "release") };
    }
    return acquire(
      {
        ...state,
        operationId: null,
        operationTarget: null,
        owner: null,
        stage: null,
      },
      state.desired
    );
  }

  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || typeof event.type !== "string" || event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return transitionStart(state, event);
  }
  if (event.type === "retry") {
    return transitionRetry(state);
  }
  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }
  return transitionCompletion(state, event);
};

const selfCheck = () => {
  let state = initial();
  const step = (event) => {
    const result = transition(state, event);
    ({ state } = result);
    return result;
  };

  Object.freeze(state);
  let result = step({ target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);

  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ id: 1, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  result = step({ id: 2, type: "fail" });
  assert.equal(observe(state).phase, "blocked");
  result = step({ target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  result = step({ id: 3, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  result = step({ id: 4, type: "fail" });
  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 5, target: "recording", type: "release" },
  ]);
  result = step({ id: 5, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 6, target: "calibration", type: "acquire" },
  ]);
  result = step({ id: 1, type: "fail" });
  assert.deepEqual(result.effects, []);
  result = step({ id: 6, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "calibration",
    phase: "active",
  });
  result = step({ target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 7, target: "calibration", type: "stop" },
  ]);
  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ id: 7, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 8, target: "calibration", type: "release" },
  ]);
  result = step({ target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = step({ id: 8, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 9, target: "calibration", type: "acquire" },
  ]);
  result = step({ id: 9, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "calibration",
    phase: "active",
  });
  assert.deepEqual(transition(state, { type: "profile" }), {
    effects: [],
    state,
  });
};

if (import.meta.url === `file://${process.argv[1]}`) {
  selfCheck();
  console.log("e4 self-check passed");
}
