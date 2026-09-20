import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);
const unchanged = (state) => ({ effects: [], state });
const snapshot = (state) => Object.freeze({ ...state });
const next = (state, patch, effect) => ({
  effects: effect ? [effect] : [],
  state: snapshot({ ...state, ...patch }),
});
const phaseFor = (type) => {
  if (type === "acquire") {
    return "acquiring";
  }
  if (type === "stop") {
    return "stopping";
  }
  return "releasing";
};
const issue = (state, type, target) => {
  const id = state.nextId;
  return next(
    state,
    {
      nextId: id + 1,
      operationId: id,
      phase: phaseFor(type),
    },
    { id, target, type }
  );
};

export const initial = () =>
  snapshot({
    desired: null,
    failedStage: null,
    nextId: 1,
    operationId: null,
    owner: null,
    phase: "idle",
    target: null,
  });

export const observe = ({ phase, owner, desired, operationId }) => ({
  desired,
  operationId,
  owner,
  phase,
});

const start = (state, target) => {
  if (!targets.has(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return issue({ ...state, desired: target, target }, "acquire", target);
  }
  if (state.phase === "active") {
    if (state.owner === target) {
      return unchanged(state);
    }
    return issue(
      { ...state, desired: target, target: state.owner },
      "stop",
      state.owner
    );
  }
  if (state.desired === target) {
    return unchanged(state);
  }
  return next(state, { desired: target });
};

const complete = (state, event) => {
  if (state.phase === "acquiring") {
    if (event.type === "fail") {
      return next(state, {
        desired: null,
        operationId: null,
        owner: null,
        phase: "idle",
        target: null,
      });
    }
    if (state.target === state.desired) {
      return next(state, {
        operationId: null,
        owner: state.target,
        phase: "active",
      });
    }
    return issue(
      { ...state, operationId: null, owner: state.target, phase: "active" },
      "stop",
      state.target
    );
  }

  if (state.phase === "stopping") {
    if (event.type === "fail") {
      return next(state, {
        failedStage: "stop",
        operationId: null,
        phase: "blocked",
      });
    }
    return issue({ ...state, operationId: null }, "release", state.owner);
  }

  if (state.phase === "releasing") {
    if (event.type === "fail") {
      return next(state, {
        failedStage: "release",
        operationId: null,
        phase: "blocked",
      });
    }
    return issue(
      { ...state, operationId: null, owner: null, target: state.desired },
      "acquire",
      state.desired
    );
  }

  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || typeof event.type !== "string") {
    return unchanged(state);
  }
  if (event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event.target);
  }
  if (event.type === "retry") {
    return state.phase === "blocked"
      ? issue(state, state.failedStage, state.owner)
      : unchanged(state);
  }
  if (event.type !== "ok" && event.type !== "fail") {
    return unchanged(state);
  }
  return event.id === state.operationId
    ? complete(state, event)
    : unchanged(state);
};

const apply = (state, event) => transition(state, event);
const only = (result) => result.effects[0];

export const selfcheck = () => {
  let state = initial();
  const step = (event) => {
    const result = apply(state, event);
    ({ state } = result);
    return result;
  };
  let result = step({ target: "recording", type: "start" });
  assert.deepEqual(only(result), {
    id: 1,
    target: "recording",
    type: "acquire",
  });
  result = step({ target: "calibration", type: "start" });
  assert.equal(result.effects.length, 0);
  result = step({ target: "recording", type: "start" });
  assert.equal(result.effects.length, 0);
  result = step({ id: 1, type: "ok" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  result = step({ target: "calibration", type: "start" });
  assert.deepEqual(only(result), { id: 2, target: "recording", type: "stop" });
  result = step({ target: "recording", type: "start" });
  assert.equal(observe(state).desired, "recording");
  const stale = apply(state, { id: 1, type: "fail" });
  assert.strictEqual(stale.state, state);
  assert.deepEqual(stale.effects, []);
  result = step({ id: 2, type: "ok" });
  assert.deepEqual(only(result), {
    id: 3,
    target: "recording",
    type: "release",
  });
  result = step({ id: 3, type: "fail" });
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  result = step({ target: "calibration", type: "start" });
  assert.equal(result.effects.length, 0);
  result = step({ type: "retry" });
  assert.deepEqual(only(result), {
    id: 4,
    target: "recording",
    type: "release",
  });
  result = step({ id: 4, type: "ok" });
  assert.deepEqual(only(result), {
    id: 5,
    target: "calibration",
    type: "acquire",
  });
  result = step({ id: 5, type: "fail" });
  assert.deepEqual(observe(state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });

  state = initial();
  step({ target: "recording", type: "start" });
  step({ id: 1, type: "ok" });
  result = step({ target: "calibration", type: "start" });
  result = step({ id: 2, type: "fail" });
  assert.equal(observe(state).phase, "blocked");
  result = step({ type: "retry" });
  assert.deepEqual(only(result), { id: 3, target: "recording", type: "stop" });

  state = initial();
  const beforeProfile = state;
  result = step({ type: "profile" });
  assert.strictEqual(result.state, beforeProfile);
  assert.deepEqual(result.effects, []);
  return "selfcheck: 4 scenarios passed";
};

if (import.meta.main) {
  console.log(selfcheck());
}
