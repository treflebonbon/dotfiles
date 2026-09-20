import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);
const noop = (state) => ({ effects: [], state });
const next = (state, phase, updates, effect) => {
  const id = state.nextId;
  return {
    effects: [{ id, target: effect.target, type: effect.type }],
    state: { ...state, ...updates, id, nextId: id + 1, phase },
  };
};

export const initial = () => ({
  blockedStage: null,
  desired: null,
  id: null,
  nextId: 1,
  owner: null,
  phase: "idle",
  stageTarget: null,
});

export const observe = ({ desired, id, owner, phase }) => ({
  desired,
  operationId: id,
  owner,
  phase,
});

const beginAcquire = (state, target = state.desired) =>
  next(
    state,
    "acquiring",
    { blockedStage: null, owner: null, stageTarget: target },
    { target, type: "acquire" }
  );

const beginStop = (state, owner = state.owner) =>
  next(
    state,
    "stopping",
    { owner, stageTarget: owner },
    { target: owner, type: "stop" }
  );

const beginRelease = (state) =>
  next(
    state,
    "releasing",
    { stageTarget: state.owner },
    { target: state.owner, type: "release" }
  );

const onStart = (state, event) => {
  if (!targets.has(event.target)) {
    return noop(state);
  }
  if (state.phase === "idle") {
    return beginAcquire({ ...state, desired: event.target }, event.target);
  }
  if (state.phase === "active") {
    if (state.owner === event.target) {
      return noop(state);
    }
    const updated = { ...state, desired: event.target };
    return beginStop(updated);
  }
  return { effects: [], state: { ...state, desired: event.target } };
};

const onRetry = (state) => {
  if (state.phase !== "blocked") {
    return noop(state);
  }
  return state.blockedStage === "stop" ? beginStop(state) : beginRelease(state);
};

const onFailure = (state) => {
  if (state.phase === "acquiring") {
    return {
      effects: [],
      state: {
        ...state,
        id: null,
        owner: null,
        phase: "idle",
        stageTarget: null,
      },
    };
  }
  if (state.phase !== "stopping" && state.phase !== "releasing") {
    return noop(state);
  }
  return {
    effects: [],
    state: {
      ...state,
      blockedStage: state.phase === "stopping" ? "stop" : "release",
      id: null,
      phase: "blocked",
    },
  };
};

const onSuccess = (state) => {
  if (state.phase === "acquiring") {
    const acquired = {
      ...state,
      id: null,
      owner: state.stageTarget,
      stageTarget: null,
    };
    return acquired.desired === acquired.owner
      ? { effects: [], state: { ...acquired, phase: "active" } }
      : beginStop(acquired);
  }
  if (state.phase === "stopping") {
    return beginRelease(state);
  }
  if (state.phase === "releasing") {
    const released = { ...state, id: null, owner: null, stageTarget: null };
    return released.desired
      ? beginAcquire(released)
      : { effects: [], state: { ...released, phase: "idle" } };
  }
  return noop(state);
};

const onCompletion = (state, event) => {
  if (event.type !== "ok" && event.type !== "fail") {
    return noop(state);
  }
  if (event.id !== state.id) {
    return noop(state);
  }
  return event.type === "fail" ? onFailure(state) : onSuccess(state);
};

export const transition = (state, event) => {
  if (event.type === "profile") {
    return noop(state);
  }
  if (event.type === "start") {
    return onStart(state, event);
  }
  if (event.type === "retry") {
    return onRetry(state);
  }
  return onCompletion(state, event);
};

const send = (state, event) => transition(state, event).state;
const command = (state, event) => transition(state, event);

const check = () => {
  let state = initial();
  let result = command(state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  ({ state } = result);
  state = send(state, { target: "calibration", type: "start" });
  state = send(state, { target: "recording", type: "start" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: 1,
    owner: null,
    phase: "acquiring",
  });
  state = send(state, { id: 1, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = command(state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  ({ state } = result);
  state = send(state, { target: "recording", type: "start" });
  state = send(state, { id: 2, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: 3,
    owner: "recording",
    phase: "releasing",
  });
  state = send(state, { target: "calibration", type: "start" });
  state = send(state, { target: "recording", type: "start" });
  result = command(state, { id: 3, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "acquire" },
  ]);
  ({ state } = result);
  const stale = transition(state, { id: 3, type: "fail" });
  assert.equal(stale.state, state);
  assert.deepEqual(stale.effects, []);

  state = send(state, { id: 4, type: "ok" });
  result = command(state, { target: "calibration", type: "start" });
  ({ state } = result);
  state = send(state, { id: 5, type: "fail" });
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  state = send(state, { target: "recording", type: "start" });
  result = command(state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 6, target: "recording", type: "stop" },
  ]);
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: 6,
    owner: "recording",
    phase: "stopping",
  });
  assert.deepEqual(transition(result.state, { type: "profile" }), {
    effects: [],
    state: result.state,
  });
};

check();
console.log("E self-check: ok");
