import assert from "node:assert/strict";

const stageEffect = (stage, target, nextId) => ({
  effect: { id: nextId, target, type: stage },
  nextId: nextId + 1,
  operation: { id: nextId, stage, target },
});

const unchanged = (state) => ({ effects: [], state });

const begin = (state, stage, target, patch = {}) => {
  const next = stageEffect(stage, target, state.nextId);
  return {
    effects: [next.effect],
    state: {
      ...state,
      ...patch,
      nextId: next.nextId,
      operation: next.operation,
      phase: stage === "acquire" ? "acquiring" : `${stage}ping`,
    },
  };
};

export const initial = () => ({
  blockedStage: null,
  desired: null,
  nextId: 1,
  operation: null,
  owner: null,
  phase: "idle",
});

export const observe = ({ phase, owner, desired, operation }) => ({
  desired,
  operationId: operation?.id ?? null,
  owner,
  phase,
});

export const transition = (state, event) => {
  if (event.type === "profile") {
    return unchanged(state);
  }

  if (event.type === "start") {
    if (state.phase === "idle") {
      return begin(state, "acquire", event.target, { desired: event.target });
    }
    if (state.phase === "active" && state.owner === event.target) {
      return unchanged(state);
    }
    if (state.phase === "active") {
      return begin(state, "stop", state.owner, { desired: event.target });
    }
    return { effects: [], state: { ...state, desired: event.target } };
  }

  if (event.type === "retry" && state.phase === "blocked") {
    return begin(state, state.blockedStage, state.owner, {
      blockedStage: null,
    });
  }

  if (
    (event.type !== "ok" && event.type !== "fail") ||
    event.id !== state.operation?.id
  ) {
    return unchanged(state);
  }

  const { stage, target } = state.operation;
  if (event.type === "fail") {
    if (stage === "acquire") {
      return { effects: [], state: initial() };
    }
    return {
      effects: [],
      state: {
        ...state,
        blockedStage: stage,
        operation: null,
        phase: "blocked",
      },
    };
  }

  if (stage === "acquire") {
    if (state.desired === target) {
      return {
        effects: [],
        state: { ...state, operation: null, owner: target, phase: "active" },
      };
    }
    return begin(state, "stop", target, { owner: target });
  }
  if (stage === "stop") {
    return begin(state, "release", target);
  }
  if (state.desired === null) {
    return { effects: [], state: initial() };
  }
  return begin(state, "acquire", state.desired, { owner: null });
};

const step = (state, event) => transition(state, event);
const advance = (state, event) => step(state, event).state;

const selfCheck = () => {
  let state = initial();
  let result = step(state, { target: "recording", type: "start" });
  state = advance(state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);

  state = advance(state, { target: "calibration", type: "start" });
  state = advance(state, { target: "recording", type: "start" });
  result = step(state, { id: 1, type: "ok" });
  state = advance(state, { id: 1, type: "ok" });
  assert.equal(observe(state).phase, "active");
  assert.equal(observe(state).owner, "recording");
  assert.deepEqual(result.effects, []);

  result = step(state, { target: "calibration", type: "start" });
  state = advance(state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 2, target: "recording", type: "stop" },
  ]);
  state = advance(state, { target: "recording", type: "start" });
  result = step(state, { id: 2, type: "ok" });
  state = advance(state, { id: 2, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "release" },
  ]);
  state = advance(state, { target: "calibration", type: "start" });
  state = advance(state, { target: "recording", type: "start" });
  result = step(state, { id: 3, type: "ok" });
  state = advance(state, { id: 3, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "acquire" },
  ]);

  const stale = step(state, { id: 3, type: "ok" });
  assert.equal(stale.state, state);
  assert.deepEqual(stale.effects, []);
  result = step(state, { id: 4, type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: null,
    operationId: null,
    owner: null,
    phase: "idle",
  });

  state = advance(initial(), { target: "recording", type: "start" });
  state = advance(state, { id: 1, type: "ok" });
  state = advance(state, { target: "calibration", type: "start" });
  result = step(state, { id: 2, type: "fail" });
  state = advance(state, { id: 2, type: "fail" });
  assert.equal(observe(state).phase, "blocked");
  state = advance(state, { target: "recording", type: "start" });
  result = step(state, { type: "retry" });
  state = advance(state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 3, target: "recording", type: "stop" },
  ]);
  result = step(state, { id: 3, type: "ok" });
  state = advance(state, { id: 3, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  result = step(state, { id: 4, type: "fail" });
  state = advance(state, { id: 4, type: "fail" });
  result = step(state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 5, target: "recording", type: "release" },
  ]);

  state = advance(initial(), { target: "recording", type: "start" });
  const beforeProfile = state;
  result = step(state, { type: "profile" });
  assert.equal(result.state, beforeProfile);
  assert.deepEqual(result.effects, []);
};

if (process.argv[1] === import.meta.filename) {
  selfCheck();
  console.log("E self-check: passed (5 cases)");
}
