import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

const make = (state) => Object.freeze(state);
const unchanged = (state) => ({ effects: [], state });

const begin = (state, phase, type, target) => {
  const id = `device-${state.nextId}`;
  return {
    effects: [{ id, target, type }],
    state: make({
      desired: state.desired,
      nextId: state.nextId + 1,
      operationId: id,
      owner: phase === "acquiring" ? null : state.owner,
      phase,
      stage: type,
      target,
    }),
  };
};

const changeDesired = (state, desired) =>
  desired === state.desired
    ? unchanged(state)
    : { effects: [], state: make({ ...state, desired }) };

export const initial = () =>
  make({
    desired: null,
    nextId: 1,
    operationId: null,
    owner: null,
    phase: "idle",
    stage: null,
    target: null,
  });

export const observe = ({ phase, owner, desired, operationId }) => ({
  desired,
  operationId,
  owner,
  phase,
});

const startRequest = (state, event) => {
  if (!targets.has(event.target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    const requested = make({ ...state, desired: event.target });
    return begin(requested, "acquiring", "acquire", event.target);
  }
  if (state.phase === "active" && state.owner === event.target) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    const requested = make({ ...state, desired: event.target });
    return begin(requested, "stopping", "stop", state.owner);
  }
  return changeDesired(state, event.target);
};

export const transition = (state, event) => {
  if (!event || typeof event.type !== "string") {
    return unchanged(state);
  }
  if (event.type === "profile") {
    return unchanged(state);
  }

  if (event.type === "start") {
    return startRequest(state, event);
  }

  if (event.type === "retry") {
    if (state.phase !== "blocked") {
      return unchanged(state);
    }
    return begin(
      state,
      state.stage === "stop" ? "stopping" : "releasing",
      state.stage,
      state.owner
    );
  }

  if (
    (event.type !== "ok" && event.type !== "fail") ||
    state.operationId === null ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }

  if (event.type === "fail") {
    if (state.stage === "acquire") {
      return {
        effects: [],
        state: make({
          ...state,
          desired: null,
          operationId: null,
          phase: "idle",
          stage: null,
          target: null,
        }),
      };
    }
    return {
      effects: [],
      state: make({ ...state, operationId: null, phase: "blocked" }),
    };
  }

  if (state.stage === "acquire") {
    const acquired = make({
      ...state,
      operationId: null,
      owner: state.target,
      phase: "active",
      stage: null,
      target: null,
    });
    return acquired.owner === acquired.desired
      ? { effects: [], state: acquired }
      : begin(acquired, "stopping", "stop", acquired.owner);
  }
  if (state.stage === "stop") {
    return begin(state, "releasing", "release", state.owner);
  }
  if (state.stage === "release") {
    const released = make({
      ...state,
      operationId: null,
      owner: null,
      phase: "idle",
      stage: null,
      target: null,
    });
    return begin(released, "acquiring", "acquire", released.desired);
  }
  return unchanged(state);
};

const step = (state, event) => transition(state, event);
const effect = (result) => result.effects[0];

const selfCheck = () => {
  let state = initial();
  let result = step(state, { target: "recording", type: "start" });
  assert.deepEqual(effect(result), {
    id: "device-1",
    target: "recording",
    type: "acquire",
  });
  ({ state } = result);
  ({ state } = step(state, { target: "calibration", type: "start" }));
  result = step(state, { target: "recording", type: "start" });
  assert.equal(result.effects.length, 0);
  ({ state } = result);
  result = step(state, { id: "device-1", type: "ok" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = step(result.state, { target: "calibration", type: "start" });
  assert.deepEqual(effect(result), {
    id: "device-2",
    target: "recording",
    type: "stop",
  });
  ({ state } = step(result.state, { target: "recording", type: "start" }));
  result = step(state, { id: "device-2", type: "ok" });
  assert.deepEqual(effect(result), {
    id: "device-3",
    target: "recording",
    type: "release",
  });
  result = step(result.state, { id: "device-3", type: "ok" });
  assert.deepEqual(effect(result), {
    id: "device-4",
    target: "recording",
    type: "acquire",
  });

  ({ state } = result);
  const stale = step(state, { id: "device-1", type: "fail" });
  assert.equal(stale.state, state);
  assert.deepEqual(stale.effects, []);
  assert.equal(step(state, { id: null, type: "ok" }).state, state);
  result = step(state, { id: "device-4", type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });

  state = initial();
  result = step(state, { target: "recording", type: "start" });
  ({ state } = result);
  result = step(state, { id: "device-1", type: "ok" });
  result = step(result.state, { target: "calibration", type: "start" });
  ({ state } = result);
  result = step(state, { id: "device-2", type: "fail" });
  assert.equal(observe(result.state).phase, "blocked");
  ({ state } = step(result.state, { target: "recording", type: "start" }));
  assert.equal(observe(state).desired, "recording");
  result = step(state, { type: "retry" });
  assert.deepEqual(effect(result), {
    id: "device-3",
    target: "recording",
    type: "stop",
  });
  result = step(result.state, { id: "device-3", type: "ok" });
  ({ state } = result);
  result = step(state, { id: "device-4", type: "fail" });
  assert.equal(observe(result.state).phase, "blocked");
  result = step(result.state, { type: "retry" });
  assert.deepEqual(effect(result), {
    id: "device-5",
    target: "recording",
    type: "release",
  });

  ({ state } = result);
  const profile = step(state, { type: "profile" });
  assert.equal(profile.state, state);
  assert.deepEqual(profile.effects, []);
};

if (import.meta.main) {
  selfCheck();
  console.log("e3 self-check: passed");
}
