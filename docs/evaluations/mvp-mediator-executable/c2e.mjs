import assert from "node:assert/strict";

const EMPTY = Object.freeze([]);
const targets = new Set(["recording", "calibration"]);
const make = (values) => Object.freeze(values);

export const initial = () =>
  make({
    desired: null,
    failedStage: null,
    nextId: 1,
    operationId: null,
    owner: null,
    pendingTarget: null,
    phase: "idle",
  });

const idle = (state) => make({ ...initial(), nextId: state.nextId });
const unchanged = (state) => ({ effects: EMPTY, state });

const command = (state, phase, type, target) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: make({
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      pendingTarget: type === "acquire" ? target : null,
      phase,
    }),
  };
};

const acquire = (state) =>
  command(state, "acquiring", "acquire", state.desired);
const stop = (state) => command(state, "stopping", "stop", state.owner);
const release = (state) => command(state, "releasing", "release", state.owner);

const withDesired = (state, desired) =>
  state.desired === desired
    ? unchanged(state)
    : { effects: EMPTY, state: make({ ...state, desired }) };

const blocked = (state, failedStage) =>
  make({
    ...state,
    failedStage,
    operationId: null,
    pendingTarget: null,
    phase: "blocked",
  });

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const onStart = (state, target) => {
  if (!targets.has(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire(make({ ...state, desired: target }));
  }
  if (state.phase === "active") {
    return state.owner === target
      ? unchanged(state)
      : stop(make({ ...state, desired: target }));
  }
  return withDesired(state, target);
};

const onCompletion = (state, type) => {
  if (state.phase === "acquiring") {
    if (type === "fail") {
      return { effects: EMPTY, state: idle(state) };
    }
    const owner = state.pendingTarget;
    const settled = make({
      ...state,
      operationId: null,
      owner,
      pendingTarget: null,
      phase: "active",
    });
    return owner === settled.desired
      ? { effects: EMPTY, state: settled }
      : stop(settled);
  }
  if (state.phase === "stopping") {
    return type === "ok"
      ? release(state)
      : { effects: EMPTY, state: blocked(state, "stopping") };
  }
  if (state.phase === "releasing") {
    if (type === "fail") {
      return { effects: EMPTY, state: blocked(state, "releasing") };
    }
    return acquire(
      make({ ...state, operationId: null, owner: null, pendingTarget: null })
    );
  }
  return unchanged(state);
};

export const transition = (state, event) => {
  if (event?.type === "profile") {
    return unchanged(state);
  }
  if (event?.type === "start") {
    return onStart(state, event.target);
  }
  if (event?.type === "retry" && state.phase === "blocked") {
    return state.failedStage === "stopping" ? stop(state) : release(state);
  }
  if (event?.type !== "ok" && event?.type !== "fail") {
    return unchanged(state);
  }
  if (event.id !== state.operationId) {
    return unchanged(state);
  }
  return onCompletion(state, event.type);
};

const expectEffect = (result, effect) =>
  assert.deepEqual(result.effects, [effect]);
const stateOf = ({ state }) => state;

export const selfCheck = () => {
  let state = initial();

  let result = transition(state, { target: "recording", type: "start" });
  expectEffect(result, { id: 1, target: "recording", type: "acquire" });
  state = stateOf(transition(stateOf(result), { id: 1, type: "ok" }));
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });
  result = transition(state, { target: "calibration", type: "start" });
  expectEffect(result, { id: 2, target: "recording", type: "stop" });
  state = stateOf(transition(stateOf(result), { id: 2, type: "ok" }));
  result = transition(state, { id: 3, type: "ok" });
  expectEffect(result, { id: 4, target: "calibration", type: "acquire" });
  state = stateOf(transition(stateOf(result), { id: 4, type: "ok" }));
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "calibration",
    phase: "active",
  });

  state = initial();
  result = transition(state, { target: "recording", type: "start" });
  state = stateOf(
    transition(stateOf(result), { target: "calibration", type: "start" })
  );
  state = stateOf(transition(state, { target: "recording", type: "start" }));
  result = transition(state, { id: 1, type: "ok" });
  assert.deepEqual(result.effects, EMPTY);
  assert.deepEqual(observe(stateOf(result)), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  state = stateOf(
    transition(stateOf(result), { target: "calibration", type: "start" })
  );
  const stale = transition(state, { id: 1, type: "ok" });
  assert.strictEqual(stateOf(stale), state);
  assert.deepEqual(stale.effects, EMPTY);
  assert.strictEqual(stateOf(transition(state, { type: "profile" })), state);

  result = transition(state, { id: 2, type: "fail" });
  state = stateOf(result);
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  state = stateOf(transition(state, { target: "recording", type: "start" }));
  result = transition(state, { type: "retry" });
  expectEffect(result, { id: 3, target: "recording", type: "stop" });
  state = stateOf(transition(stateOf(result), { id: 3, type: "ok" }));
  result = transition(state, { id: 4, type: "fail" });
  state = stateOf(result);
  state = stateOf(transition(state, { target: "calibration", type: "start" }));
  result = transition(state, { type: "retry" });
  expectEffect(result, { id: 5, target: "recording", type: "release" });
  result = transition(stateOf(result), { id: 5, type: "ok" });
  expectEffect(result, { id: 6, target: "calibration", type: "acquire" });
  state = stateOf(result);
  result = transition(state, { id: 5, type: "ok" });
  assert.strictEqual(stateOf(result), state);
  assert.deepEqual(result.effects, EMPTY);
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: 6,
    owner: null,
    phase: "acquiring",
  });

  result = transition(initial(), { target: "recording", type: "start" });
  state = stateOf(transition(stateOf(result), { id: 1, type: "fail" }));
  assert.deepEqual(observe(state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });
  assert.strictEqual(stateOf(transition(state, { type: "retry" })), state);
  result = transition(state, { target: "calibration", type: "start" });
  expectEffect(result, { id: 2, target: "calibration", type: "acquire" });
};

if (process.argv[1] === import.meta.filename) {
  selfCheck();
  console.log("c2e self-check: ok");
}
