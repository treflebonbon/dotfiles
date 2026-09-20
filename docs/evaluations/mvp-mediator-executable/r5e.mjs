import assert from "node:assert/strict";

const targets = new Set(["calibration", "recording"]);

const makeState = (state) => Object.freeze(state);

const idle = (nextId) =>
  makeState({
    desired: null,
    failedStage: null,
    nextId,
    operationId: null,
    operationTarget: null,
    owner: null,
    phase: "idle",
  });

const effect = (id, target, type) => Object.freeze({ id, target, type });

const begin = (state, phase, target, type) => {
  const id = state.nextId;
  return {
    effects: [effect(id, target, type)],
    state: makeState({
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      operationTarget: target,
      phase,
    }),
  };
};

const unchanged = (state) => ({ effects: [], state });

const setDesired = (state, desired) =>
  state.desired === desired
    ? unchanged(state)
    : { effects: [], state: makeState({ ...state, desired }) };

const isCurrent = (state, event) => event?.id === state.operationId;

export const initial = () => idle(1);

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const start = (state, target) => {
  if (state.phase === "idle") {
    return begin(
      makeState({ ...state, desired: target }),
      "acquiring",
      target,
      "acquire"
    );
  }
  if (state.phase === "active" && target === state.owner) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return begin(
      makeState({ ...state, desired: target }),
      "stopping",
      state.owner,
      "stop"
    );
  }
  return setDesired(state, target);
};

const retry = (state) =>
  begin(
    state,
    state.failedStage === "stop" ? "stopping" : "releasing",
    state.owner,
    state.failedStage
  );

const fail = (state) => {
  if (state.phase === "acquiring") {
    return unchanged(idle(state.nextId));
  }
  if (state.phase !== "stopping" && state.phase !== "releasing") {
    return unchanged(state);
  }
  return {
    effects: [],
    state: makeState({
      ...state,
      failedStage: state.phase === "stopping" ? "stop" : "release",
      operationId: null,
      operationTarget: null,
      phase: "blocked",
    }),
  };
};

const succeed = (state) => {
  if (state.phase === "acquiring") {
    if (state.desired === state.operationTarget) {
      return {
        effects: [],
        state: makeState({
          ...state,
          operationId: null,
          operationTarget: null,
          owner: state.operationTarget,
          phase: "active",
        }),
      };
    }
    return begin(
      makeState({ ...state, owner: state.operationTarget }),
      "stopping",
      state.operationTarget,
      "stop"
    );
  }
  if (state.phase === "stopping") {
    return begin(state, "releasing", state.owner, "release");
  }
  if (state.phase !== "releasing") {
    return unchanged(state);
  }
  const released = makeState({
    ...state,
    operationId: null,
    operationTarget: null,
    owner: null,
  });
  return released.desired === null
    ? { effects: [], state: idle(released.nextId) }
    : begin(released, "acquiring", released.desired, "acquire");
};

export const transition = (state, event) => {
  if (event?.type === "profile") {
    return unchanged(state);
  }
  if (event?.type === "start" && targets.has(event.target)) {
    return start(state, event.target);
  }
  if (event?.type === "retry" && state.phase === "blocked") {
    return retry(state);
  }
  if (!isCurrent(state, event)) {
    return unchanged(state);
  }
  if (event.type === "fail") {
    return fail(state);
  }
  if (event.type === "ok") {
    return succeed(state);
  }
  return unchanged(state);
};

const step = (state, event) => transition(state, event);

const check = () => {
  let result = step(initial(), { target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  result = step(result.state, { target: "calibration", type: "start" });
  result = step(result.state, { target: "recording", type: "start" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: 1,
    owner: null,
    phase: "acquiring",
  });
  result = step(result.state, { id: 1, type: "ok" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = step(result.state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  result = step(result.state, { target: "recording", type: "start" });
  result = step(result.state, { id: 2, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "release" },
  ]);
  result = step(result.state, { id: 3, type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  result = step(result.state, { target: "calibration", type: "start" });
  assert.equal(result.effects.length, 0);
  result = step(result.state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  const unchangedResult = step(result.state, { id: 3, type: "ok" });
  assert.equal(unchangedResult.state, result.state);
  result = step(result.state, { id: 4, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 5, target: "calibration", type: "acquire" },
  ]);
  result = step(result.state, { id: 5, type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });
  assert.equal(step(result.state, { type: "profile" }).state, result.state);
};

if (process.argv[1] === import.meta.filename) {
  check();
  console.log("r5e self-check: OK");
}
