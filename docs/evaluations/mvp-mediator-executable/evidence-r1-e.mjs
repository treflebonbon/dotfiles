const targets = new Set(["recording", "calibration"]);
const unchanged = (state) => ({ effects: [], state });
const execute = (state, phase, type, target, patch = {}) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      ...patch,
      nextId: id + 1,
      pending: { id, stage: type, target },
      phase,
    },
  };
};

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  owner: null,
  pending: null,
  phase: "idle",
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.pending?.id ?? null,
  owner: state.owner,
  phase: state.phase,
});

export const transition = (state, event) => {
  if (event.type === "profile") {
    return unchanged(state);
  }

  if (event.type === "start") {
    if (!targets.has(event.target)) {
      return unchanged(state);
    }
    if (state.phase === "idle") {
      return execute(state, "acquiring", "acquire", event.target, {
        desired: event.target,
        failedStage: null,
        owner: null,
      });
    }
    if (state.phase === "active") {
      if (event.target === state.owner) {
        return unchanged(state);
      }
      return execute(state, "stopping", "stop", state.owner, {
        desired: event.target,
        failedStage: null,
      });
    }
    return { effects: [], state: { ...state, desired: event.target } };
  }

  if (event.type === "retry") {
    if (state.phase !== "blocked") {
      return unchanged(state);
    }
    const phase = state.failedStage === "stop" ? "stopping" : "releasing";
    return execute(state, phase, state.failedStage, state.owner, {
      failedStage: null,
    });
  }

  if (event.type !== "ok" && event.type !== "fail") {
    return unchanged(state);
  }
  if (!state.pending || state.pending.id !== event.id) {
    return unchanged(state);
  }

  const { stage, target } = state.pending;
  if (event.type === "fail") {
    if (stage === "acquire") {
      return {
        effects: [],
        state: {
          ...state,
          desired: null,
          failedStage: null,
          owner: null,
          pending: null,
          phase: "idle",
        },
      };
    }
    return {
      effects: [],
      state: {
        ...state,
        failedStage: stage,
        pending: null,
        phase: "blocked",
      },
    };
  }

  if (stage === "acquire") {
    if (state.desired === target) {
      return {
        effects: [],
        state: {
          ...state,
          failedStage: null,
          owner: target,
          pending: null,
          phase: "active",
        },
      };
    }
    return execute(state, "stopping", "stop", target, {
      failedStage: null,
      owner: target,
    });
  }
  if (stage === "stop") {
    return execute(state, "releasing", "release", state.owner, {
      failedStage: null,
    });
  }
  return execute(state, "acquiring", "acquire", state.desired, {
    failedStage: null,
    owner: null,
  });
};

const assert = (condition, message) => {
  if (!condition) {
    throw new Error(message);
  }
};
const drive = (state, event) => transition(state, event);
const onlyEffect = ({ effects }) => {
  const [effect] = effects;
  return effect;
};
const stateOf = ({ state }) => state;

export const selfCheck = () => {
  let state = initial();
  let out = drive(state, { target: "recording", type: "start" });
  state = stateOf(out);
  const initialAcquire = onlyEffect(out);
  assert(
    initialAcquire?.type === "acquire" && initialAcquire.id === 1,
    "normal acquire"
  );
  out = drive(state, { id: 1, type: "ok" });
  state = stateOf(out);
  assert(
    observe(state).phase === "active" && observe(state).owner === "recording",
    "normal active"
  );

  state = initial();
  out = drive(state, { target: "recording", type: "start" });
  state = stateOf(out);
  const { id: acquireId } = onlyEffect(out);
  out = drive(state, { target: "calibration", type: "start" });
  state = stateOf(out);
  assert(
    onlyEffect(out) === undefined,
    "intent update does not duplicate acquire"
  );
  out = drive(state, { target: "recording", type: "start" });
  state = stateOf(out);
  assert(
    observe(state).operationId === acquireId,
    "in-flight identity survives intent return"
  );
  assert(
    stateOf(drive(state, { id: 999, type: "ok" })) === state,
    "stale acquire is ignored"
  );
  state = stateOf(drive(state, { id: acquireId, type: "ok" }));
  assert(
    observe(state).phase === "active",
    "matching latest intent remains active"
  );
  out = drive(state, { target: "calibration", type: "start" });
  state = stateOf(out);
  const { id: stopId } = onlyEffect(out);
  state = stateOf(drive(state, { target: "recording", type: "start" }));
  out = drive(state, { id: stopId, type: "ok" });
  state = stateOf(out);
  const { id: releaseId } = onlyEffect(out);
  state = stateOf(drive(state, { id: releaseId, type: "fail" }));
  assert(observe(state).phase === "blocked", "release failure blocks");
  state = stateOf(drive(state, { target: "calibration", type: "start" }));
  out = drive(state, { type: "retry" });
  state = stateOf(out);
  const retryRelease = onlyEffect(out);
  const { id: retryReleaseId } = retryRelease;
  assert(
    retryReleaseId > releaseId && retryRelease.type === "release",
    "retry repeats failed release"
  );
  out = drive(state, { id: retryReleaseId, type: "ok" });
  state = stateOf(out);
  const nextAcquire = onlyEffect(out);
  const { id: nextAcquireId } = nextAcquire;
  assert(
    nextAcquire.target === "calibration",
    "release precedes newest acquire"
  );
  assert(
    stateOf(drive(state, { id: releaseId, type: "fail" })) === state,
    "stale release cannot advance"
  );
  state = stateOf(drive(state, { id: nextAcquireId, type: "fail" }));
  assert(observe(state).phase === "idle", "acquire failure returns idle");
  assert(
    stateOf(drive(state, { type: "profile" })) === state,
    "profile is independent"
  );
  return "E self-check: 2 cases passed";
};

if (process.argv[1] === import.meta.filename) {
  console.log(selfCheck());
}
