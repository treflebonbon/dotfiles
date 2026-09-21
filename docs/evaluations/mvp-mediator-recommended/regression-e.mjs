import assert from "node:assert/strict";

const targets = new Set(["recording", "calibration"]);

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operation: null,
  owner: null,
  phase: "idle",
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operation?.id ?? null,
  owner: state.owner,
  phase: state.phase,
});

const unchanged = (state) => ({ effects: [], state });

const command = (state, phase, type, target) => {
  const id = `device-${state.nextId}`;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      failedStage: null,
      nextId: state.nextId + 1,
      operation: { id, stage: type, target },
      phase,
    },
  };
};

const acquire = (state, target) =>
  command({ ...state, owner: null }, "acquiring", "acquire", target);

const stop = (state) => command(state, "stopping", "stop", state.owner);

const release = (state) => command(state, "releasing", "release", state.owner);

const onStart = (state, event) => {
  if (!targets.has(event.target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire({ ...state, desired: event.target }, event.target);
  }
  if (state.phase === "active" && state.owner === event.target) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return stop({ ...state, desired: event.target });
  }
  return { effects: [], state: { ...state, desired: event.target } };
};

const onRetry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  return state.failedStage === "stop" ? stop(state) : release(state);
};

const onCompletion = (state, event) => {
  if (
    (event?.type !== "ok" && event?.type !== "fail") ||
    event.id !== state.operation?.id
  ) {
    return unchanged(state);
  }

  const { stage, target } = state.operation;
  if (event.type === "fail") {
    if (stage === "acquire") {
      return {
        effects: [],
        state: { ...state, desired: null, operation: null, phase: "idle" },
      };
    }
    return {
      effects: [],
      state: {
        ...state,
        failedStage: stage,
        operation: null,
        phase: "blocked",
      },
    };
  }

  if (stage === "acquire") {
    if (target === state.desired) {
      return {
        effects: [],
        state: { ...state, operation: null, owner: target, phase: "active" },
      };
    }
    return stop({ ...state, operation: null, owner: target });
  }
  if (stage === "stop") {
    return release({ ...state, operation: null });
  }
  return acquire({ ...state, operation: null }, state.desired);
};

export const transition = (state, event) => {
  if (event?.type === "profile") {
    return unchanged(state);
  }
  if (event?.type === "start") {
    return onStart(state, event);
  }
  if (event?.type === "retry") {
    return onRetry(state);
  }
  return onCompletion(state, event);
};

const stateOf = ({ state }) => state;
const effectOf = ([effect]) => effect;

const runChecks = () => {
  let state = initial();
  let result = transition(state, { target: "recording", type: "start" });
  const acquireRecording = effectOf(result.effects);
  assert.deepEqual(result.effects, [
    { id: acquireRecording.id, target: "recording", type: "acquire" },
  ]);
  state = stateOf(result);
  assert.deepEqual(observe(state), {
    desired: "recording",
    operationId: acquireRecording.id,
    owner: null,
    phase: "acquiring",
  });

  // 1: The latest intent can return to the in-flight target without duplicate I/O.
  state = stateOf(transition(state, { target: "calibration", type: "start" }));
  result = transition(state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = transition(stateOf(result), { id: acquireRecording.id, type: "ok" });
  assert.deepEqual(observe(stateOf(result)), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });
  state = stateOf(result);

  // 2: A switch waits for stop and release; failures require an explicit retry.
  result = transition(state, { target: "calibration", type: "start" });
  const stopRecording = effectOf(result.effects);
  state = stateOf(result);
  result = transition(state, { id: stopRecording.id, type: "fail" });
  state = stateOf(result);
  assert.deepEqual(observe(state), {
    desired: "calibration",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  result = transition(state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = transition(stateOf(result), { type: "retry" });
  const retriedStop = effectOf(result.effects);
  assert.equal(retriedStop.type, "stop");
  assert.notEqual(retriedStop.id, stopRecording.id);
  state = stateOf(result);
  result = transition(state, { id: retriedStop.id, type: "ok" });
  const releaseRecording = effectOf(result.effects);
  state = stateOf(result);
  result = transition(state, { id: releaseRecording.id, type: "fail" });
  state = stateOf(result);
  result = transition(state, { type: "retry" });
  const retriedRelease = effectOf(result.effects);
  assert.equal(retriedRelease.type, "release");
  state = stateOf(result);
  result = transition(state, { id: retriedRelease.id, type: "ok" });
  const acquireRecordingAgain = effectOf(result.effects);
  assert.deepEqual(result.effects, [
    { id: acquireRecordingAgain.id, target: "recording", type: "acquire" },
  ]);
  state = stateOf(result);

  // 3: Old completions do not advance the current operation, and every command ID is fresh.
  const beforeStale = state;
  result = transition(state, { id: releaseRecording.id, type: "ok" });
  assert.strictEqual(stateOf(result), beforeStale);
  assert.deepEqual(result.effects, []);
  const ids = [
    acquireRecording.id,
    stopRecording.id,
    retriedStop.id,
    releaseRecording.id,
    retriedRelease.id,
    acquireRecordingAgain.id,
  ];
  assert.equal(new Set(ids).size, ids.length);

  // 4: This model only returns execution-boundary commands.
  assert.deepEqual(Object.keys(acquireRecording).toSorted(), [
    "id",
    "target",
    "type",
  ]);

  // 5: Profile is local and cannot alter the device flow.
  result = transition(state, { type: "profile" });
  assert.strictEqual(stateOf(result), state);
  assert.deepEqual(result.effects, []);

  // 6: Acquisition failure is idle without an automatic retry.
  result = transition(initial(), { target: "calibration", type: "start" });
  const failedAcquire = effectOf(result.effects);
  result = transition(stateOf(result), { id: failedAcquire.id, type: "fail" });
  assert.deepEqual(observe(stateOf(result)), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });
  assert.deepEqual(transition(stateOf(result), { type: "retry" }).effects, []);

  console.log("regression-e: 6 assertions passed");
};

const [, invokedPath] = process.argv;
if (invokedPath === import.meta.filename) {
  runChecks();
}
