import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

const make = (
  phase,
  owner,
  desired,
  operationId,
  nextId,
  failedStage = null,
  operationTarget = null
) =>
  Object.freeze({
    desired,
    failedStage,
    nextId,
    operationId,
    operationTarget,
    owner,
    phase,
  });

const unchanged = (state) => ({ effects: [], state });

const command = (state, phase, type, target, failedStage = null) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: make(
      phase,
      state.owner,
      state.desired,
      id,
      id + 1,
      failedStage,
      target
    ),
  };
};

const acquire = (state) =>
  command(
    make(state.phase, null, state.desired, state.operationId, state.nextId),
    "acquiring",
    "acquire",
    state.desired
  );

const stop = (state) => command(state, "stopping", "stop", state.owner);

const release = (state) => command(state, "releasing", "release", state.owner);

export const initial = () => make("idle", null, null, null, 1);

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const startRequest = (state, event) => {
  if (!targets.has(event.target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire(make("idle", null, event.target, null, state.nextId));
  }
  if (state.phase === "active" && state.owner === event.target) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return stop(make("active", state.owner, event.target, null, state.nextId));
  }
  if (["acquiring", "stopping", "releasing", "blocked"].includes(state.phase)) {
    return {
      effects: [],
      state: make(
        state.phase,
        state.owner,
        event.target,
        state.operationId,
        state.nextId,
        state.failedStage,
        state.operationTarget
      ),
    };
  }
  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || typeof event !== "object") {
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
    return state.failedStage === "stop"
      ? stop(make("blocked", state.owner, state.desired, null, state.nextId))
      : release(
          make("blocked", state.owner, state.desired, null, state.nextId)
        );
  }

  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }

  if (state.phase === "acquiring") {
    if (event.type === "fail") {
      return {
        effects: [],
        state: make("idle", null, null, null, state.nextId),
      };
    }
    const owner = state.operationTarget;
    if (owner === state.desired) {
      return {
        effects: [],
        state: make("active", owner, state.desired, null, state.nextId),
      };
    }
    return stop(make("active", owner, state.desired, null, state.nextId));
  }

  if (state.phase === "stopping") {
    if (event.type === "fail") {
      return {
        effects: [],
        state: make(
          "blocked",
          state.owner,
          state.desired,
          null,
          state.nextId,
          "stop"
        ),
      };
    }
    return release(
      make("stopping", state.owner, state.desired, null, state.nextId)
    );
  }

  if (state.phase === "releasing") {
    if (event.type === "fail") {
      return {
        effects: [],
        state: make(
          "blocked",
          state.owner,
          state.desired,
          null,
          state.nextId,
          "release"
        ),
      };
    }
    return acquire(make("releasing", null, state.desired, null, state.nextId));
  }

  return unchanged(state);
};

const demo = () => {
  let state = initial();
  let result = transition(state, { target: "recording", type: "start" });
  ({ state } = result);
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);

  result = transition(state, { target: "calibration", type: "start" });
  ({ state } = result);
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: 1,
    owner: null,
    phase: "acquiring",
  });
  assert.deepEqual(result.effects, []);
  result = transition(state, { target: "recording", type: "start" });
  ({ state } = result);
  assert.equal(observe(state).operationId, 1);
  assert.deepEqual(result.effects, []);

  result = transition(state, { id: 1, type: "ok" });
  ({ state } = result);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });
  result = transition(state, { target: "calibration", type: "start" });
  ({ state } = result);
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  result = transition(state, { target: "recording", type: "start" });
  ({ state } = result);
  assert.equal(observe(state).operationId, 2);
  assert.deepEqual(result.effects, []);

  result = transition(state, { id: 2, type: "ok" });
  ({ state } = result);
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "release" },
  ]);
  result = transition(state, { id: 3, type: "fail" });
  ({ state } = result);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  result = transition(state, { target: "calibration", type: "start" });
  ({ state } = result);
  assert.equal(result.effects.length, 0);
  const stale = transition(state, { id: 3, type: "ok" });
  assert.equal(stale.state, state);
  assert.deepEqual(stale.effects, []);
  result = transition(state, { type: "retry" });
  ({ state } = result);
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  result = transition(state, { id: 4, type: "ok" });
  ({ state } = result);
  assert.deepEqual(result.effects, [
    { id: 5, target: "calibration", type: "acquire" },
  ]);

  const profile = transition(state, { type: "profile" });
  assert.equal(profile.state, state);
  assert.deepEqual(profile.effects, []);
  result = transition(state, { id: 5, type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });
  assert.deepEqual(transition(result.state, { type: "retry" }).effects, []);

  let switched = transition(initial(), {
    target: "recording",
    type: "start",
  }).state;
  switched = transition(switched, {
    target: "calibration",
    type: "start",
  }).state;
  result = transition(switched, { id: 1, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  assert.deepEqual(observe(result.state), {
    desired: "calibration",
    operationId: 2,
    owner: "recording",
    phase: "stopping",
  });
};

if (process.argv[1] === import.meta.filename) {
  demo();
  console.log("e2.mjs: assertions passed");
}
