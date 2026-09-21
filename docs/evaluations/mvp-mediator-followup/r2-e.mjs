import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  owner: null,
  pendingTarget: null,
  phase: "idle",
});

export const observe = (state) => {
  const { phase, owner, desired, operationId } = state;
  return { desired, operationId, owner, phase };
};

const unchanged = (state) => ({ effects: [], state });

const begin = (state, phase, type, target) => {
  const id = `device-${state.nextId}`;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      failedStage: null,
      nextId: state.nextId + 1,
      operationId: id,
      pendingTarget: target,
      phase,
    },
  };
};

const acquire = (state, target) =>
  begin(
    { ...state, desired: target, owner: null },
    "acquiring",
    "acquire",
    target
  );

const updateIntent = (state, target) =>
  target === state.desired
    ? unchanged(state)
    : { effects: [], state: { ...state, desired: target } };

const complete = (state, event) => {
  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }

  if (event.type === "fail") {
    if (state.phase === "acquiring") {
      return {
        effects: [],
        state: {
          ...state,
          desired: null,
          operationId: null,
          pendingTarget: null,
          phase: "idle",
        },
      };
    }
    return {
      effects: [],
      state: {
        ...state,
        failedStage: state.phase === "stopping" ? "stop" : "release",
        operationId: null,
        pendingTarget: null,
        phase: "blocked",
      },
    };
  }

  if (state.phase === "acquiring") {
    const acquired = state.pendingTarget;
    if (acquired === state.desired) {
      return {
        effects: [],
        state: {
          ...state,
          operationId: null,
          owner: acquired,
          pendingTarget: null,
          phase: "active",
        },
      };
    }
    return begin(
      { ...state, owner: acquired, pendingTarget: null },
      "stopping",
      "stop",
      acquired
    );
  }
  if (state.phase === "stopping") {
    return begin(
      { ...state, pendingTarget: null },
      "releasing",
      "release",
      state.owner
    );
  }
  if (state.phase === "releasing") {
    return acquire({ ...state, pendingTarget: null }, state.desired);
  }
  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || typeof event.type !== "string" || event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    if (!targets.has(event.target)) {
      return unchanged(state);
    }
    if (state.phase === "idle") {
      return acquire(state, event.target);
    }
    if (state.phase === "active" && state.owner === event.target) {
      return unchanged(state);
    }
    if (state.phase === "active") {
      return begin(
        { ...state, desired: event.target },
        "stopping",
        "stop",
        state.owner
      );
    }
    return updateIntent(state, event.target);
  }
  if (event.type === "retry" && state.phase === "blocked") {
    return begin(
      state,
      state.failedStage === "stop" ? "stopping" : "releasing",
      state.failedStage,
      state.owner
    );
  }
  return complete(state, event);
};

const send = (state, event) => transition(state, event);

const normalPath = () => {
  let result = send(initial(), { target: "recording", type: "start" });
  const acquireId = result.effects[0].id;
  result = send(result.state, { id: acquireId, type: "ok" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });
};

const latestIntentAndFreshIds = () => {
  let result = send(initial(), { target: "recording", type: "start" });
  const acquireId = result.effects[0].id;
  result = send(result.state, { target: "calibration", type: "start" });
  result = send(result.state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = send(result.state, { id: acquireId, type: "ok" });
  assert.equal(result.state.phase, "active");
  assert.equal(result.state.owner, "recording");
  assert.notEqual(acquireId, result.state.operationId);
};

const releaseBeforeNextAcquireAndRetry = () => {
  let result = send(initial(), { target: "recording", type: "start" });
  result = send(result.state, { id: result.effects[0].id, type: "ok" });
  result = send(result.state, { target: "calibration", type: "start" });
  const stopId = result.effects[0].id;
  result = send(result.state, { id: stopId, type: "ok" });
  const releaseId = result.effects[0].id;
  assert.equal(result.effects[0].type, "release");
  result = send(result.state, { id: releaseId, type: "fail" });
  assert.equal(result.state.phase, "blocked");
  result = send(result.state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = send(result.state, { type: "retry" });
  assert.equal(result.effects[0].type, "release");
  assert.notEqual(result.effects[0].id, releaseId);
  result = send(result.state, { id: result.effects[0].id, type: "ok" });
  assert.equal(result.effects[0].type, "acquire");
  assert.equal(result.effects[0].target, "recording");
};

const staleAndProfileAreIgnored = () => {
  const result = send(initial(), { target: "recording", type: "start" });
  const { state } = result;
  assert.deepEqual(send(state, { id: "stale", type: "ok" }), {
    effects: [],
    state,
  });
  assert.deepEqual(send(state, { type: "profile" }), { effects: [], state });
};

if (import.meta.url === `file://${process.argv[1]}`) {
  for (const check of [
    normalPath,
    latestIntentAndFreshIds,
    releaseBeforeNextAcquireAndRetry,
    staleAndProfileAreIgnored,
  ]) {
    check();
  }
  console.log("4 assertions passed");
}
