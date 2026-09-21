import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";

/* oxlint-disable eslint/complexity, eslint/curly, eslint/func-style, eslint/no-nested-ternary, eslint/prefer-destructuring, eslint/sort-keys, unicorn/prefer-import-meta-properties */

const targets = new Set(["recording", "calibration"]);

export function initial() {
  return {
    phase: "idle",
    owner: null,
    desired: null,
    operationId: null,
    nextId: 1,
  };
}

export function observe(state) {
  const { phase, owner, desired, operationId } = state;
  return { phase, owner, desired, operationId };
}

function begin(state, phase, target) {
  const id = `device-${state.nextId}`;
  return {
    state: {
      ...state,
      phase,
      operationId: id,
      stageTarget: target,
      failedStage: null,
      nextId: state.nextId + 1,
    },
    effects: [
      {
        type:
          phase === "acquiring"
            ? "acquire"
            : phase === "stopping"
              ? "stop"
              : "release",
        target,
        id,
      },
    ],
  };
}

function acquire(state, target) {
  return begin({ ...state, desired: target }, "acquiring", target);
}

function stop(state) {
  return begin(state, "stopping", state.owner);
}

function release(state) {
  return begin(state, "releasing", state.owner);
}

function unchanged(state) {
  return { state, effects: [] };
}

export function transition(state, event) {
  if (event.type === "profile") return unchanged(state);

  if (event.type === "start" && targets.has(event.target)) {
    if (state.phase === "idle") return acquire(state, event.target);
    if (state.phase === "active" && state.owner === event.target)
      return unchanged(state);
    if (state.phase === "active")
      return stop({ ...state, desired: event.target });
    if (state.phase === "blocked")
      return unchanged({ ...state, desired: event.target });
    return unchanged({ ...state, desired: event.target });
  }

  if (event.type === "retry" && state.phase === "blocked") {
    return state.failedStage === "stop" ? stop(state) : release(state);
  }

  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operationId
  ) {
    return unchanged(state);
  }

  if (event.type === "fail") {
    if (state.phase === "acquiring")
      return {
        state: {
          ...state,
          phase: "idle",
          owner: null,
          desired: null,
          operationId: null,
          stageTarget: null,
        },
        effects: [],
      };
    return {
      state: {
        ...state,
        phase: "blocked",
        operationId: null,
        failedStage: state.phase === "stopping" ? "stop" : "release",
      },
      effects: [],
    };
  }

  if (state.phase === "acquiring") {
    const owner = state.stageTarget;
    const active = {
      ...state,
      phase: "active",
      owner,
      operationId: null,
      stageTarget: null,
    };
    return active.desired === owner
      ? { state: active, effects: [] }
      : stop(active);
  }
  if (state.phase === "stopping") return release(state);
  if (state.phase === "releasing")
    return acquire({ ...state, owner: null }, state.desired);
  return unchanged(state);
}

function step(state, event) {
  const result = transition(state, event);
  return result;
}

function runChecks() {
  let state = initial();
  let result = step(state, { type: "start", target: "recording" });
  assert.deepEqual(result.effects, [
    { type: "acquire", target: "recording", id: "device-1" },
  ]);
  state = result.state;
  result = step(state, { type: "ok", id: "device-1" });
  assert.deepEqual(observe(result.state), {
    phase: "active",
    owner: "recording",
    desired: "recording",
    operationId: null,
  });
  state = result.state;
  assert.deepEqual(step(state, { type: "start", target: "recording" }), {
    state,
    effects: [],
  });
  result = step(state, { type: "start", target: "calibration" });
  assert.deepEqual(result.effects, [
    { type: "stop", target: "recording", id: "device-2" },
  ]);
  result = step(result.state, { type: "ok", id: "device-2" });
  assert.deepEqual(result.effects, [
    { type: "release", target: "recording", id: "device-3" },
  ]);
  result = step(result.state, { type: "ok", id: "device-3" });
  assert.deepEqual(result.effects, [
    { type: "acquire", target: "calibration", id: "device-4" },
  ]);

  state = initial();
  state = step(state, { type: "start", target: "recording" }).state;
  state = step(state, { type: "start", target: "calibration" }).state;
  result = step(state, { type: "start", target: "recording" });
  assert.deepEqual(result.effects, []);
  result = step(result.state, { type: "ok", id: "device-1" });
  assert.deepEqual(observe(result.state), {
    phase: "active",
    owner: "recording",
    desired: "recording",
    operationId: null,
  });

  state = initial();
  state = step(state, { type: "start", target: "recording" }).state;
  state = step(state, { type: "ok", id: "device-1" }).state;
  state = step(state, { type: "start", target: "calibration" }).state;
  state = step(state, { type: "start", target: "recording" }).state;
  state = step(state, { type: "start", target: "calibration" }).state;
  result = step(state, { type: "ok", id: "device-2" });
  assert.deepEqual(result.effects, [
    { type: "release", target: "recording", id: "device-3" },
  ]);
  result = step(result.state, { type: "start", target: "recording" });
  assert.deepEqual(result.effects, []);
  result = step(result.state, { type: "ok", id: "device-3" });
  assert.deepEqual(result.effects, [
    { type: "acquire", target: "recording", id: "device-4" },
  ]);

  state = initial();
  state = step(state, { type: "start", target: "recording" }).state;
  state = step(state, { type: "ok", id: "device-1" }).state;
  state = step(state, { type: "start", target: "calibration" }).state;
  result = step(state, { type: "fail", id: "device-2" });
  assert.deepEqual(observe(result.state), {
    phase: "blocked",
    owner: "recording",
    desired: "calibration",
    operationId: null,
  });
  state = result.state;
  result = step(state, { type: "start", target: "recording" });
  assert.deepEqual(result.effects, []);
  result = step(result.state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { type: "stop", target: "recording", id: "device-3" },
  ]);
  state = result.state;
  assert.deepEqual(step(state, { type: "ok", id: "device-2" }), {
    state,
    effects: [],
  });
  result = step(state, { type: "ok", id: "device-3" });
  assert.deepEqual(result.effects, [
    { type: "release", target: "recording", id: "device-4" },
  ]);
  result = step(result.state, { type: "fail", id: "device-4" });
  result = step(result.state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { type: "release", target: "recording", id: "device-5" },
  ]);
  result = step(result.state, { type: "ok", id: "device-5" });
  assert.deepEqual(result.effects, [
    { type: "acquire", target: "recording", id: "device-6" },
  ]);
  result = step(result.state, { type: "fail", id: "device-6" });
  assert.deepEqual(observe(result.state), {
    phase: "idle",
    owner: null,
    desired: null,
    operationId: null,
  });

  state = initial();
  assert.deepEqual(step(state, { type: "profile" }), { state, effects: [] });
  assert.deepEqual(step(state, { type: "ok", id: "device-99" }), {
    state,
    effects: [],
  });
  return "all assertions passed";
}

if (process.argv[1] === fileURLToPath(import.meta.url))
  console.log(runChecks());
