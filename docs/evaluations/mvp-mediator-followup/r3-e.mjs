import assert from "node:assert/strict";

const dataByState = new WeakMap();
const targets = new Set(["recording", "calibration"]);

const makeState = (data) => {
  const value = Object.freeze({});
  dataByState.set(value, Object.freeze(data));
  return value;
};

const dataOf = (value) => dataByState.get(value);

const unchanged = (value) => ({ effects: [], state: value });

const withCommand = (data, phase, target, type) => {
  const id = data.nextId;
  return {
    effects: [{ id, target, type }],
    state: makeState({
      ...data,
      nextId: id + 1,
      operationId: id,
      owner: type === "acquire" ? null : target,
      phase,
      stage: type,
      target,
    }),
  };
};

const idle = (data) =>
  makeState({
    ...data,
    operationId: null,
    owner: null,
    phase: "idle",
    stage: null,
    target: null,
  });

const blocked = (data, stage) =>
  makeState({ ...data, operationId: null, phase: "blocked", stage });

export const initial = () =>
  makeState({
    desired: null,
    nextId: 1,
    operationId: null,
    owner: null,
    phase: "idle",
    stage: null,
    target: null,
  });

export const observe = (value) => {
  const data = dataOf(value);
  return {
    desired: data.desired,
    operationId: data.operationId,
    owner: data.owner,
    phase: data.phase,
  };
};

const start = (data, value, event) => {
  if (!targets.has(event.target)) {
    return unchanged(value);
  }
  if (data.phase === "idle") {
    return withCommand(
      { ...data, desired: event.target },
      "acquiring",
      event.target,
      "acquire"
    );
  }
  if (
    data.desired === event.target ||
    (data.phase === "active" && data.owner === event.target)
  ) {
    return unchanged(value);
  }
  if (data.phase === "active") {
    return withCommand(
      { ...data, desired: event.target },
      "stopping",
      data.owner,
      "stop"
    );
  }
  return { effects: [], state: makeState({ ...data, desired: event.target }) };
};

const retry = (data, value) => {
  if (data.phase !== "blocked") {
    return unchanged(value);
  }
  const phase = data.stage === "stop" ? "stopping" : "releasing";
  return withCommand(data, phase, data.owner, data.stage);
};

const acquireCompleted = (data, event) => {
  if (event.type === "fail") {
    return { effects: [], state: idle(data) };
  }
  if (data.target !== data.desired) {
    return withCommand(data, "stopping", data.target, "stop");
  }
  return {
    effects: [],
    state: makeState({
      ...data,
      operationId: null,
      owner: data.target,
      phase: "active",
      stage: null,
      target: null,
    }),
  };
};

const stopCompleted = (data, event) =>
  event.type === "fail"
    ? { effects: [], state: blocked(data, "stop") }
    : withCommand(data, "releasing", data.owner, "release");

const releaseCompleted = (data, event) =>
  event.type === "fail"
    ? { effects: [], state: blocked(data, "release") }
    : withCommand(data, "acquiring", data.desired, "acquire");

const completion = (data, value, event) => {
  if (event.id !== data.operationId) {
    return unchanged(value);
  }
  if (data.phase === "acquiring") {
    return acquireCompleted(data, event);
  }
  if (data.phase === "stopping") {
    return stopCompleted(data, event);
  }
  if (data.phase === "releasing") {
    return releaseCompleted(data, event);
  }
  return unchanged(value);
};

export const transition = (value, event) => {
  const data = dataOf(value);
  if (!data || !event || typeof event.type !== "string") {
    return unchanged(value);
  }
  if (event.type === "start") {
    return start(data, value, event);
  }
  if (event.type === "retry") {
    return retry(data, value);
  }
  if (event.type === "ok" || event.type === "fail") {
    return completion(data, value, event);
  }
  return unchanged(value);
};

const check = () => {
  let value = initial();
  let result = transition(value, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, [
    { id: 1, target: "recording", type: "acquire" },
  ]);
  result = transition(result.state, { id: 1, type: "ok" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "active",
  });

  value = initial();
  result = transition(value, { target: "recording", type: "start" });
  const [acquire] = result.effects;
  result = transition(result.state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = transition(result.state, { id: acquire.id, type: "ok" });
  const [stop] = result.effects;
  assert.deepEqual(stop, { id: 2, target: "recording", type: "stop" });
  result = transition(result.state, { target: "recording", type: "start" });
  assert.deepEqual(result.effects, []);
  result = transition(result.state, { id: stop.id, type: "ok" });
  const [release] = result.effects;
  assert.deepEqual(release, { id: 3, target: "recording", type: "release" });
  result = transition(result.state, { id: release.id, type: "fail" });
  assert.deepEqual(observe(result.state), {
    desired: "recording",
    operationId: null,
    owner: "recording",
    phase: "blocked",
  });
  result = transition(result.state, { target: "calibration", type: "start" });
  assert.deepEqual(result.effects, []);
  result = transition(result.state, { type: "retry" });
  assert.deepEqual(result.effects, [
    { id: 4, target: "recording", type: "release" },
  ]);
  const stale = transition(result.state, { id: 3, type: "ok" });
  assert.equal(stale.state, result.state);
  assert.deepEqual(stale.effects, []);
  result = transition(result.state, { id: 4, type: "ok" });
  assert.deepEqual(result.effects, [
    { id: 5, target: "calibration", type: "acquire" },
  ]);
  const profile = transition(result.state, { type: "profile" });
  assert.equal(profile.state, result.state);
  assert.deepEqual(profile.effects, []);
  result = transition(result.state, { id: 5, type: "ok" });
  assert.deepEqual(observe(result.state), {
    desired: "calibration",
    operationId: null,
    owner: "calibration",
    phase: "active",
  });
};

if (process.argv[1] === import.meta.filename) {
  check();
  console.log("mvp mediator model checks passed");
}
