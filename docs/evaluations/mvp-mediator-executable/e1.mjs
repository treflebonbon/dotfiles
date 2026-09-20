const targets = new Set(["recording", "calibration"]);
const effectTypeByPhase = {
  acquiring: "acquire",
  releasing: "release",
  stopping: "stop",
};

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  operationTarget: null,
  owner: null,
  phase: "idle",
});

export const observe = (state) => {
  const { phase, owner, desired, operationId } = state;
  return { desired, operationId, owner, phase };
};

const unchanged = (state) => ({ effects: [], state });

const begin = (state, phase, target) => {
  const id = `device-${state.nextId}`;
  const type = effectTypeByPhase[phase];
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      failedStage: null,
      nextId: state.nextId + 1,
      operationId: id,
      operationTarget: target,
      phase,
    },
  };
};

const acquire = (state) =>
  begin({ ...state, owner: null }, "acquiring", state.desired);

const stop = (state) => begin(state, "stopping", state.owner);

const release = (state) => begin(state, "releasing", state.owner);

const block = (state, failedStage) => ({
  effects: [],
  state: {
    ...state,
    failedStage,
    operationId: null,
    operationTarget: null,
    phase: "blocked",
  },
});

const start = (state, target) => {
  if (!targets.has(target)) {
    return unchanged(state);
  }
  if (state.phase !== "idle" && state.desired === target) {
    return unchanged(state);
  }
  const updated = { ...state, desired: target };
  if (state.phase === "idle") {
    return acquire(updated);
  }
  if (state.phase === "active" && state.owner !== target) {
    return stop(updated);
  }
  return { effects: [], state: updated };
};

const retry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  if (state.failedStage === "stop") {
    return stop(state);
  }
  if (state.failedStage === "release") {
    return release(state);
  }
  return unchanged(state);
};

const fail = (state) => {
  if (state.phase === "acquiring") {
    return {
      effects: [],
      state: {
        ...state,
        failedStage: null,
        operationId: null,
        operationTarget: null,
        phase: "idle",
      },
    };
  }
  if (state.phase === "stopping") {
    return block(state, "stop");
  }
  if (state.phase === "releasing") {
    return block(state, "release");
  }
  return unchanged(state);
};

const succeed = (state) => {
  if (state.phase === "acquiring") {
    const acquired = {
      ...state,
      operationId: null,
      operationTarget: null,
      owner: state.operationTarget,
    };
    if (acquired.owner === acquired.desired) {
      return { effects: [], state: { ...acquired, phase: "active" } };
    }
    return stop(acquired);
  }
  if (state.phase === "stopping") {
    return release({ ...state, operationId: null, operationTarget: null });
  }
  if (state.phase === "releasing") {
    const released = {
      ...state,
      operationId: null,
      operationTarget: null,
      owner: null,
    };
    if (targets.has(released.desired)) {
      return acquire(released);
    }
    return { effects: [], state: { ...released, phase: "idle" } };
  }
  return unchanged(state);
};

const complete = (state, event) => {
  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }
  if (event.type === "fail") {
    return fail(state);
  }
  return succeed(state);
};

export const transition = (state, event) => {
  if (!event || typeof event.type !== "string" || event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event.target);
  }
  if (event.type === "retry") {
    return retry(state);
  }
  return complete(state, event);
};

const assert = (condition, message) => {
  if (!condition) {
    throw new Error(message);
  }
};

const step = (result, event) => transition(result.state, event);

const runSelfCheck = () => {
  let result = { effects: [], state: initial() };
  result = step(result, { target: "recording", type: "start" });
  const [acquireRecording] = result.effects;
  result = step(result, { target: "calibration", type: "start" });
  result = step(result, { target: "recording", type: "start" });
  assert(
    result.effects.length === 0 &&
      observe(result.state).operationId === acquireRecording.id,
    "intent return must retain acquisition"
  );
  result = step(result, { id: acquireRecording.id, type: "ok" });
  assert(
    observe(result.state).phase === "active" &&
      observe(result.state).owner === "recording",
    "matching acquisition must activate"
  );

  result = step(result, { target: "calibration", type: "start" });
  const [stopRecording] = result.effects;
  result = step(result, { target: "recording", type: "start" });
  result = step(result, { id: stopRecording.id, type: "fail" });
  assert(
    observe(result.state).phase === "blocked" &&
      observe(result.state).owner === "recording",
    "stop failure must block and retain owner"
  );
  result = step(result, { target: "calibration", type: "start" });
  assert(
    result.effects.length === 0 &&
      observe(result.state).desired === "calibration",
    "blocked start must only update intent"
  );
  result = step(result, { type: "retry" });
  const [retryStop] = result.effects;
  assert(
    retryStop.type === "stop" && retryStop.id !== stopRecording.id,
    "retry must use a fresh stop id"
  );
  result = step(result, { id: retryStop.id, type: "ok" });
  const [releaseRecording] = result.effects;
  result = step(result, { id: releaseRecording.id, type: "fail" });
  result = step(result, { type: "retry" });
  const [retryRelease] = result.effects;
  result = step(result, { id: retryRelease.id, type: "ok" });
  const [acquireCalibration] = result.effects;
  assert(
    acquireCalibration.type === "acquire" &&
      acquireCalibration.target === "calibration",
    "release must precede the latest acquisition"
  );
  const beforeStale = result.state;
  result = step(result, { id: acquireRecording.id, type: "ok" });
  assert(
    result.state === beforeStale && result.effects.length === 0,
    "stale completion must do nothing"
  );
  const beforeProfile = result.state;
  result = step(result, { type: "profile" });
  assert(
    result.state === beforeProfile && result.effects.length === 0,
    "profile must be independent"
  );
  console.log("e1 self-check: passed");
};

if (import.meta.url === `file://${process.argv[1]}`) {
  runSelfCheck();
}
