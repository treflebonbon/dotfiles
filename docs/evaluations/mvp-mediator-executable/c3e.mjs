import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

export const initial = () => ({
  desired: null,
  nextId: 1,
  operationId: null,
  owner: null,
  phase: "idle",
  stage: null,
  stageTarget: null,
});

export const observe = (state) => {
  const { phase, owner, desired, operationId } = state;
  return { desired, operationId, owner, phase };
};

const unchanged = (state) => ({ effects: [], state });

const withDesired = (state, desired) => ({ ...state, desired });

const issue = (state, phase, type, target, owner) => {
  const id = state.nextId;
  const next = {
    ...state,
    nextId: id + 1,
    operationId: id,
    owner,
    phase,
    stage: type,
    stageTarget: target,
  };
  return { effects: [{ id, target, type }], state: next };
};

const acquire = (state) =>
  issue(state, "acquiring", "acquire", state.desired, null);

const stop = (state) =>
  issue(state, "stopping", "stop", state.owner, state.owner);

const release = (state) =>
  issue(state, "releasing", "release", state.owner, state.owner);

const start = (state, target) => {
  if (!targets.has(target)) {
    return unchanged(state);
  }

  const requested = withDesired(state, target);
  if (requested.phase === "idle") {
    return acquire(requested);
  }
  if (requested.phase === "active" && requested.owner !== target) {
    return stop(requested);
  }
  return { effects: [], state: requested };
};

const complete = (state, event) => {
  if (event.id !== state.operationId) {
    return unchanged(state);
  }

  if (event.type === "fail") {
    if (state.phase === "acquiring") {
      return {
        effects: [],
        state: {
          ...state,
          operationId: null,
          phase: "idle",
          stage: null,
          stageTarget: null,
        },
      };
    }
    return {
      effects: [],
      state: { ...state, operationId: null, phase: "blocked" },
    };
  }

  if (state.phase === "acquiring") {
    if (state.desired === state.stageTarget) {
      return {
        effects: [],
        state: {
          ...state,
          operationId: null,
          owner: state.stageTarget,
          phase: "active",
          stage: null,
          stageTarget: null,
        },
      };
    }
    return stop({ ...state, operationId: null, owner: state.stageTarget });
  }
  if (state.phase === "stopping") {
    return release({ ...state, operationId: null });
  }
  if (state.phase === "releasing") {
    return acquire({
      ...state,
      operationId: null,
      owner: null,
      stage: null,
      stageTarget: null,
    });
  }
  return unchanged(state);
};

const retry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return state.stage === "stop" ? stop(state) : release(state);
};

export const transition = (state, event) => {
  if (event?.type === "profile") {
    return unchanged(state);
  }
  if (event?.type === "start") {
    return start(state, event.target);
  }
  if (event?.type === "retry") {
    return retry(state);
  }
  if (event?.type === "ok" || event?.type === "fail") {
    return complete(state, event);
  }
  return unchanged(state);
};

const step = (state, event) => transition(state, event).state;

const check = () => {
  let state = initial();
  let result = transition(state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  ({ state } = result);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: 1,
    owner: null,
    phase: "acquiring",
  });

  state = step(state, { target: "calibration", type: "start" });
  state = step(state, { target: "recording", type: "start" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: 1,
    owner: null,
    phase: "acquiring",
  });
  state = step(state, { id: 1, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = transition(state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  ({ state } = result);
  state = step(state, { id: 2, type: "fail" });
  assert.equal(observe(state).phase, "blocked");
  state = step(state, { target: "recording", type: "start" });
  assert.equal(observe(state).operationId, null);
  result = transition(state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  ({ state } = result);
  state = step(state, { id: 2, type: "ok" });
  assert.equal(observe(state).phase, "stopping");
  result = transition(state, { id: 3, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  ({ state } = result);
  state = step(state, { id: 4, type: "fail" });
  assert.equal(observe(state).phase, "blocked");
  state = step(state, { target: "calibration", type: "start" });
  result = transition(state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 5, target: "recording", type: "release" },
  ]);
  ({ state } = result);
  state = step(state, { id: 4, type: "ok" });
  assert.equal(observe(state).phase, "releasing");
  result = transition(state, { id: 5, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 6, target: "calibration", type: "acquire" },
  ]);
  ({ state } = result);
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: 6,
    owner: null,
    phase: "acquiring",
  });
  assert.deepEqual(transition(state, { type: "profile" }), {
    effects: [],
    state,
  });

  state = step(state, { id: 6, type: "fail" });
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: null,
    phase: "idle",
  });
};

if (
  process.argv[1] &&
  import.meta.url === new URL(`file://${process.argv[1]}`).href
) {
  check();
  console.log("c3e self-check: passed");
}
