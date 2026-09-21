import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const targets = new Set(["recording", "calibration"]);
const effectTypes = {
  acquiring: "acquire",
  releasing: "release",
  stopping: "stop",
};
const unchanged = (state) => ({ effects: [], state });
const validTarget = (target) => targets.has(target);
const settled = (state, phase, owner) => ({
  ...state,
  failedStage: null,
  operationId: null,
  owner,
  phase,
  stage: null,
  stageTarget: null,
});
const stage = (state, phase, target, owner) => {
  const id = state.nextId;
  return {
    effects: [{ id, target, type: effectTypes[phase] }],
    state: {
      ...state,
      failedStage: null,
      nextId: id + 1,
      operationId: id,
      owner,
      phase,
      stage: phase,
      stageTarget: target,
    },
  };
};

export const initial = () => ({
  desired: null,
  failedStage: null,
  nextId: 1,
  operationId: null,
  owner: null,
  phase: "idle",
  stage: null,
  stageTarget: null,
});

export const observe = ({ desired, operationId, owner, phase }) => ({
  desired,
  operationId,
  owner,
  phase,
});

const start = (state, target) => {
  if (!validTarget(target)) {
    return unchanged(state);
  }
  if (state.phase === "idle") {
    return stage({ ...state, desired: target }, "acquiring", target, null);
  }
  if (state.phase === "active" && state.owner === target) {
    return unchanged(state);
  }
  if (state.phase === "active") {
    return stage(
      { ...state, desired: target },
      "stopping",
      state.owner,
      state.owner
    );
  }
  return state.desired === target
    ? unchanged(state)
    : { effects: [], state: { ...state, desired: target } };
};

const completed = (state) => {
  if (state.phase === "acquiring") {
    return state.desired === state.stageTarget
      ? unchanged(settled(state, "active", state.stageTarget))
      : stage(state, "stopping", state.stageTarget, state.stageTarget);
  }
  if (state.phase === "stopping") {
    return stage(state, "releasing", state.owner, state.owner);
  }
  if (state.phase === "releasing") {
    return stage(
      settled(state, "idle", null),
      "acquiring",
      state.desired,
      null
    );
  }
  return unchanged(state);
};

const failed = (state) => {
  if (state.phase === "acquiring") {
    return unchanged(settled(state, "idle", null));
  }
  if (state.phase === "stopping" || state.phase === "releasing") {
    return unchanged({
      ...settled(state, "blocked", state.owner),
      failedStage: state.phase,
    });
  }
  return unchanged(state);
};

export const transition = (state, event) => {
  if (!event || typeof event !== "object") {
    return unchanged(state);
  }
  if (event.type === "profile") {
    return unchanged(state);
  }
  if (event.type === "start") {
    return start(state, event.target);
  }
  if (event.type === "retry" && state.phase === "blocked") {
    return stage(state, state.failedStage, state.owner, state.owner);
  }
  if (
    (event.type === "ok" || event.type === "fail") &&
    event.id === state.operationId
  ) {
    return event.type === "ok" ? completed(state) : failed(state);
  }
  return unchanged(state);
};

const command = (id, target, type) => ({ id, target, type });
const snapshot = (desired, operationId, owner, phase, effect = null) => ({
  effects: effect ? [effect] : [],
  observe: { desired, operationId, owner, phase },
});
const view = ({ effects, state }) => ({ effects, observe: observe(state) });
const startEvent = (target) => ({ target, type: "start" });
const resultEvent = (id, type) => ({ id, type });
const run = ({ events, expected, name }) => {
  let state = initial();
  const actual = events.map((event) => {
    const result = transition(state, event);
    const { state: next } = result;
    state = next;
    return view(result);
  });
  assert.deepEqual(actual, expected);
  console.log(
    JSON.stringify({ actual, events, expected, name, result: "passed" })
  );
};

export const selfcheck = () => {
  const frozen = Object.freeze(initial());
  const afterStart = transition(frozen, startEvent("recording"));
  assert.deepEqual(observe(frozen), snapshot(null, null, null, "idle").observe);
  assert.deepEqual(
    view(afterStart),
    snapshot(
      "recording",
      1,
      null,
      "acquiring",
      command(1, "recording", "acquire")
    )
  );
  console.log(
    JSON.stringify({ name: "does-not-mutate-input", result: "passed" })
  );

  run({
    events: [startEvent("recording"), resultEvent(1, "ok")],
    expected: [
      snapshot(
        "recording",
        1,
        null,
        "acquiring",
        command(1, "recording", "acquire")
      ),
      snapshot("recording", null, "recording", "active"),
    ],
    name: "normal-uninterrupted",
  });
  run({
    events: [
      startEvent("recording"),
      startEvent("calibration"),
      startEvent("recording"),
      resultEvent(1, "ok"),
    ],
    expected: [
      snapshot(
        "recording",
        1,
        null,
        "acquiring",
        command(1, "recording", "acquire")
      ),
      snapshot("calibration", 1, null, "acquiring"),
      snapshot("recording", 1, null, "acquiring"),
      snapshot("recording", null, "recording", "active"),
    ],
    name: "latest-intent-changes-back-without-duplicate-io",
  });
  run({
    events: [
      startEvent("recording"),
      startEvent("calibration"),
      resultEvent(1, "ok"),
      resultEvent(2, "ok"),
      resultEvent(3, "ok"),
      resultEvent(4, "ok"),
    ],
    expected: [
      snapshot(
        "recording",
        1,
        null,
        "acquiring",
        command(1, "recording", "acquire")
      ),
      snapshot("calibration", 1, null, "acquiring"),
      snapshot(
        "calibration",
        2,
        "recording",
        "stopping",
        command(2, "recording", "stop")
      ),
      snapshot(
        "calibration",
        3,
        "recording",
        "releasing",
        command(3, "recording", "release")
      ),
      snapshot(
        "calibration",
        4,
        null,
        "acquiring",
        command(4, "calibration", "acquire")
      ),
      snapshot("calibration", null, "calibration", "active"),
    ],
    name: "switch-stops-releases-then-acquires",
  });
  run({
    events: [
      startEvent("recording"),
      startEvent("calibration"),
      resultEvent(1, "ok"),
      resultEvent(2, "fail"),
      startEvent("recording"),
      { type: "retry" },
      resultEvent(3, "ok"),
      resultEvent(4, "fail"),
      startEvent("calibration"),
      { type: "retry" },
      resultEvent(5, "ok"),
      resultEvent(6, "fail"),
    ],
    expected: [
      snapshot(
        "recording",
        1,
        null,
        "acquiring",
        command(1, "recording", "acquire")
      ),
      snapshot("calibration", 1, null, "acquiring"),
      snapshot(
        "calibration",
        2,
        "recording",
        "stopping",
        command(2, "recording", "stop")
      ),
      snapshot("calibration", null, "recording", "blocked"),
      snapshot("recording", null, "recording", "blocked"),
      snapshot(
        "recording",
        3,
        "recording",
        "stopping",
        command(3, "recording", "stop")
      ),
      snapshot(
        "recording",
        4,
        "recording",
        "releasing",
        command(4, "recording", "release")
      ),
      snapshot("recording", null, "recording", "blocked"),
      snapshot("calibration", null, "recording", "blocked"),
      snapshot(
        "calibration",
        5,
        "recording",
        "releasing",
        command(5, "recording", "release")
      ),
      snapshot(
        "calibration",
        6,
        null,
        "acquiring",
        command(6, "calibration", "acquire")
      ),
      snapshot("calibration", null, null, "idle"),
    ],
    name: "failure-blocks-until-retry-and-acquire-failure-idles",
  });
  run({
    events: [
      startEvent("recording"),
      { type: "profile" },
      resultEvent(99, "ok"),
      resultEvent(99, "fail"),
      resultEvent(1, "ok"),
      startEvent("calibration"),
      resultEvent(1, "ok"),
      resultEvent(2, "ok"),
      resultEvent(3, "ok"),
      resultEvent(3, "fail"),
      resultEvent(4, "ok"),
    ],
    expected: [
      snapshot(
        "recording",
        1,
        null,
        "acquiring",
        command(1, "recording", "acquire")
      ),
      snapshot("recording", 1, null, "acquiring"),
      snapshot("recording", 1, null, "acquiring"),
      snapshot("recording", 1, null, "acquiring"),
      snapshot("recording", null, "recording", "active"),
      snapshot(
        "calibration",
        2,
        "recording",
        "stopping",
        command(2, "recording", "stop")
      ),
      snapshot("calibration", 2, "recording", "stopping"),
      snapshot(
        "calibration",
        3,
        "recording",
        "releasing",
        command(3, "recording", "release")
      ),
      snapshot(
        "calibration",
        4,
        null,
        "acquiring",
        command(4, "calibration", "acquire")
      ),
      snapshot("calibration", 4, null, "acquiring"),
      snapshot("calibration", null, "calibration", "active"),
    ],
    name: "profile-and-stale-completions-are-independent",
  });
};

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  selfcheck();
}
