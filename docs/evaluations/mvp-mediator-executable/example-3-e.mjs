import assert from "node:assert/strict";
import path from "node:path";

const TARGETS = new Set(["recording", "calibration"]);

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  owner: null,
  pendingTarget: null,
  phase: "idle",
});

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.operationId,
  owner: state.owner,
  phase: state.phase,
});

const unchanged = (state) => ({ effects: [], state });

const startStage = (state, phase, type, target) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      pendingTarget: type === "acquire" ? target : null,
      phase,
    },
  };
};

const acquire = (state) =>
  startStage(
    { ...state, operationId: null, owner: null, pendingTarget: null },
    "acquiring",
    "acquire",
    state.desired
  );

const stop = (state) =>
  startStage(
    { ...state, operationId: null, pendingTarget: null },
    "stopping",
    "stop",
    state.owner
  );

const release = (state) =>
  startStage(
    { ...state, operationId: null, pendingTarget: null },
    "releasing",
    "release",
    state.owner
  );

const withDesired = (state, desired) =>
  state.desired === desired ? state : { ...state, desired };

const onStart = (state, target) => {
  if (!TARGETS.has(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return acquire({ ...state, desired: target });
  }
  if (state.phase !== "active") {
    return unchanged(withDesired(state, target));
  }
  return state.owner === target
    ? unchanged(state)
    : stop(withDesired(state, target));
};

const onRetry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }
  if (state.failedStage === "stop") {
    return stop(state);
  }
  return state.failedStage === "release" ? release(state) : unchanged(state);
};

const onCompletion = (state, event) => {
  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }

  const succeeded = event.type === "ok";
  if (state.phase === "acquiring") {
    if (!succeeded) {
      return unchanged({
        ...state,
        desired: null,
        failedStage: null,
        operationId: null,
        owner: null,
        pendingTarget: null,
        phase: "idle",
      });
    }

    const active = {
      ...state,
      operationId: null,
      owner: state.pendingTarget,
      pendingTarget: null,
      phase: "active",
    };
    return active.owner === active.desired ? unchanged(active) : stop(active);
  }

  if (state.phase === "stopping") {
    if (succeeded) {
      return release(state);
    }
    return unchanged({
      ...state,
      failedStage: "stop",
      operationId: null,
      pendingTarget: null,
      phase: "blocked",
    });
  }

  if (state.phase === "releasing") {
    if (!succeeded) {
      return unchanged({
        ...state,
        failedStage: "release",
        operationId: null,
        pendingTarget: null,
        phase: "blocked",
      });
    }
    return acquire({
      ...state,
      operationId: null,
      owner: null,
      pendingTarget: null,
    });
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
    return onStart(state, event.target);
  }
  if (event.type === "retry") {
    return onRetry(state);
  }
  return onCompletion(state, event);
};

const command = (type, target, id) => [{ id, target, type }];

const runCase = (name, steps) => {
  let state = initial();
  const actual = steps.map(({ event, expected, effects }) => {
    const { effects: actualEffects, state: nextState } = transition(
      state,
      event
    );
    state = nextState;
    const snapshot = { ...observe(state), effects: actualEffects };
    assert.deepEqual(snapshot, { ...expected, effects });
    return snapshot;
  });
  console.log(JSON.stringify({ actual, name, result: "passed" }));
};

const check = () => {
  runCase("normal-completes", [
    {
      effects: command("acquire", "recording", 1),
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 1, type: "ok" },
      expected: {
        desired: "recording",
        operationId: null,
        owner: "recording",
        phase: "active",
      },
    },
  ]);

  runCase("latest-intent-returns-to-inflight", [
    {
      effects: command("acquire", "recording", 1),
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { target: "calibration", type: "start" },
      expected: {
        desired: "calibration",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 1, type: "ok" },
      expected: {
        desired: "recording",
        operationId: null,
        owner: "recording",
        phase: "active",
      },
    },
  ]);

  runCase("release-before-next-acquire", [
    {
      effects: command("acquire", "recording", 1),
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 1, type: "ok" },
      expected: {
        desired: "recording",
        operationId: null,
        owner: "recording",
        phase: "active",
      },
    },
    {
      effects: command("stop", "recording", 2),
      event: { target: "calibration", type: "start" },
      expected: {
        desired: "calibration",
        operationId: 2,
        owner: "recording",
        phase: "stopping",
      },
    },
    {
      effects: [],
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 2,
        owner: "recording",
        phase: "stopping",
      },
    },
    {
      effects: command("release", "recording", 3),
      event: { id: 2, type: "ok" },
      expected: {
        desired: "recording",
        operationId: 3,
        owner: "recording",
        phase: "releasing",
      },
    },
    {
      effects: [],
      event: { target: "calibration", type: "start" },
      expected: {
        desired: "calibration",
        operationId: 3,
        owner: "recording",
        phase: "releasing",
      },
    },
    {
      effects: [],
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 3,
        owner: "recording",
        phase: "releasing",
      },
    },
    {
      effects: command("acquire", "recording", 4),
      event: { id: 3, type: "ok" },
      expected: {
        desired: "recording",
        operationId: 4,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 4, type: "ok" },
      expected: {
        desired: "recording",
        operationId: null,
        owner: "recording",
        phase: "active",
      },
    },
  ]);

  runCase("failures-require-explicit-stage-retry", [
    {
      effects: command("acquire", "recording", 1),
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 1,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 1, type: "fail" },
      expected: {
        desired: null,
        operationId: null,
        owner: null,
        phase: "idle",
      },
    },
    {
      effects: command("acquire", "calibration", 2),
      event: { target: "calibration", type: "start" },
      expected: {
        desired: "calibration",
        operationId: 2,
        owner: null,
        phase: "acquiring",
      },
    },
    {
      effects: [],
      event: { id: 2, type: "ok" },
      expected: {
        desired: "calibration",
        operationId: null,
        owner: "calibration",
        phase: "active",
      },
    },
    {
      effects: command("stop", "calibration", 3),
      event: { target: "recording", type: "start" },
      expected: {
        desired: "recording",
        operationId: 3,
        owner: "calibration",
        phase: "stopping",
      },
    },
    {
      effects: [],
      event: { id: 3, type: "fail" },
      expected: {
        desired: "recording",
        operationId: null,
        owner: "calibration",
        phase: "blocked",
      },
    },
    {
      effects: [],
      event: { target: "calibration", type: "start" },
      expected: {
        desired: "calibration",
        operationId: null,
        owner: "calibration",
        phase: "blocked",
      },
    },
    {
      effects: [],
      event: { type: "profile" },
      expected: {
        desired: "calibration",
        operationId: null,
        owner: "calibration",
        phase: "blocked",
      },
    },
    {
      effects: [],
      event: { id: 3, type: "ok" },
      expected: {
        desired: "calibration",
        operationId: null,
        owner: "calibration",
        phase: "blocked",
      },
    },
    {
      effects: command("stop", "calibration", 4),
      event: { type: "retry" },
      expected: {
        desired: "calibration",
        operationId: 4,
        owner: "calibration",
        phase: "stopping",
      },
    },
    {
      effects: command("release", "calibration", 5),
      event: { id: 4, type: "ok" },
      expected: {
        desired: "calibration",
        operationId: 5,
        owner: "calibration",
        phase: "releasing",
      },
    },
    {
      effects: [],
      event: { id: 5, type: "fail" },
      expected: {
        desired: "calibration",
        operationId: null,
        owner: "calibration",
        phase: "blocked",
      },
    },
    {
      effects: command("release", "calibration", 6),
      event: { type: "retry" },
      expected: {
        desired: "calibration",
        operationId: 6,
        owner: "calibration",
        phase: "releasing",
      },
    },
  ]);
};

if (process.argv[1] && import.meta.filename === path.resolve(process.argv[1])) {
  check();
}
