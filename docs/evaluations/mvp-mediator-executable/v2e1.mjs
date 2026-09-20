import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);
const freeze = (state) => Object.freeze(state);
const unchanged = (state) => ({ effects: [], state });

const initial = () =>
  freeze({
    desired: null,
    failedStage: null,
    nextId: 1,
    operationId: null,
    owner: null,
    phase: "idle",
    stageTarget: null,
  });

const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const stage = (state, phase, type, target) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: freeze({
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      phase,
      stageTarget: target,
    }),
  };
};

const acquire = (state, target) =>
  stage(
    { ...state, desired: target, owner: null },
    "acquiring",
    "acquire",
    target
  );

const blocked = (state, failedStage) =>
  freeze({
    ...state,
    failedStage,
    operationId: null,
    phase: "blocked",
    stageTarget: null,
  });

const onStart = (state, event) => {
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
    return stage(
      { ...state, desired: event.target },
      "stopping",
      "stop",
      state.owner
    );
  }
  if (state.desired === event.target) {
    return unchanged(state);
  }
  return { effects: [], state: freeze({ ...state, desired: event.target }) };
};

const onRetry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return state.failedStage === "stop"
    ? stage(state, "stopping", "stop", state.owner)
    : stage(state, "releasing", "release", state.owner);
};

const onCompletion = (state, event) => {
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
        state: freeze({
          ...state,
          desired: null,
          failedStage: null,
          operationId: null,
          owner: null,
          phase: "idle",
          stageTarget: null,
        }),
      };
    }
    if (state.stageTarget === state.desired) {
      return {
        effects: [],
        state: freeze({
          ...state,
          operationId: null,
          owner: state.stageTarget,
          phase: "active",
          stageTarget: null,
        }),
      };
    }
    return stage(
      { ...state, owner: state.stageTarget },
      "stopping",
      "stop",
      state.stageTarget
    );
  }

  if (state.phase === "stopping") {
    return event.type === "fail"
      ? { effects: [], state: blocked(state, "stop") }
      : stage(state, "releasing", "release", state.owner);
  }

  if (state.phase === "releasing") {
    return event.type === "fail"
      ? { effects: [], state: blocked(state, "release") }
      : acquire(
          {
            ...state,
            operationId: null,
            owner: null,
            stageTarget: null,
          },
          state.desired
        );
  }

  return unchanged(state);
};

const transition = (state, event) => {
  if (!event || typeof event !== "object" || event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return onStart(state, event);
  }
  if (event.type === "retry") {
    return onRetry(state);
  }
  return onCompletion(state, event);
};

const selfCheck = () => {
  let normal = transition(initial(), { target: "recording", type: "start" });
  assert.deepEqual(normal.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  const { state: normalAcquiring } = normal;
  normal = transition(normalAcquiring, { id: 1, type: "ok" });
  const { state: normalActive } = normal;
  assert.deepEqual(observe(normalActive), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  let mismatch = transition(initial(), { target: "recording", type: "start" });
  ({ state: mismatch } = transition(mismatch.state, {
    target: "calibration",
    type: "start",
  }));
  const mismatchResult = transition(mismatch, { id: 1, type: "ok" });
  assert.deepEqual(mismatchResult.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);

  let state = initial();
  let step = transition(state, { target: "recording", type: "start" });
  ({ state } = step);
  const [{ id: acquireRecording }] = step.effects;
  ({ state } = transition(state, { target: "calibration", type: "start" }));
  step = transition(state, { target: "recording", type: "start" });
  assert.deepEqual(step.effects, []);
  ({ state } = step);
  assert.equal(observe(state).operationId, acquireRecording);
  assert.equal(observe(state).desired, "recording");
  assert.strictEqual(transition(state, { id: 999, type: "ok" }).state, state);
  ({ state } = transition(state, { id: acquireRecording, type: "ok" }));

  step = transition(state, { target: "calibration", type: "start" });
  const [{ id: stopRecording }] = step.effects;
  ({ state } = transition(step.state, { target: "recording", type: "start" }));
  step = transition(state, { id: stopRecording, type: "fail" });
  const { state: stopBlocked } = step;
  assert.deepEqual(observe(stopBlocked), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  ({ state } = transition(stopBlocked, {
    target: "calibration",
    type: "start",
  }));
  step = transition(state, { type: "retry" });
  assert.deepEqual(step.effects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  ({ state } = transition(step.state, { id: 3, type: "ok" }));
  ({ state } = transition(state, { target: "recording", type: "start" }));
  assert.equal(observe(state).desired, "recording");
  step = transition(state, { id: 4, type: "fail" });
  const { state: releaseBlocked } = step;
  assert.equal(observe(releaseBlocked).phase, "blocked");
  const retryPreview = transition(releaseBlocked, { type: "retry" });
  const [{ type: retryType }] = retryPreview.effects;
  assert.equal(retryType, "release");
  step = transition(releaseBlocked, { type: "retry" });
  assert.deepEqual(step.effects, [
    { id: 5, target: "recording", type: "release" },
  ]);
  step = transition(step.state, { id: 5, type: "ok" });
  assert.deepEqual(step.effects, [
    { id: 6, target: "recording", type: "acquire" },
  ]);

  const profile = transition(step.state, { type: "profile" });
  assert.strictEqual(profile.state, step.state);
  assert.deepEqual(profile.effects, []);
  assert.deepEqual(
    observe(transition(initial(), { type: "retry" }).state),
    observe(initial())
  );
};

export { initial, observe, selfCheck, transition };

if (process.argv[1] === import.meta.filename) {
  selfCheck();
  console.log("v2e1 self-check: OK");
}
