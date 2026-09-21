import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const targets = new Set(["recording", "calibration"]);

export const initial = () => ({
  blockedStage: null,
  desired: null,
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

const issue = (state, phase, type, target, owner, desired) => {
  const id = `operation-${state.nextId}`;
  return {
    effects: [{ id, target, type }],
    state: {
      ...state,
      blockedStage: null,
      desired,
      nextId: state.nextId + 1,
      operationId: id,
      owner,
      pendingTarget: target,
      phase,
    },
  };
};

const withDesired = (state, desired) =>
  state.desired === desired
    ? unchanged(state)
    : { effects: [], state: { ...state, desired } };

const start = (state, target) => {
  if (!targets.has(target)) {
    return unchanged(state);
  }

  switch (state.phase) {
    case "idle": {
      return issue(state, "acquiring", "acquire", target, null, target);
    }
    case "active": {
      return state.owner === target
        ? unchanged(state)
        : issue(state, "stopping", "stop", state.owner, state.owner, target);
    }
    case "acquiring":
    case "blocked":
    case "releasing":
    case "stopping": {
      return withDesired(state, target);
    }
    default: {
      return unchanged(state);
    }
  }
};

const completion = (state, event) => {
  if (
    !["acquiring", "stopping", "releasing"].includes(state.phase) ||
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
          operationId: null,
          owner: null,
          pendingTarget: null,
          phase: "idle",
        },
      };
    }

    return {
      effects: [],
      state: {
        ...state,
        blockedStage: state.phase,
        operationId: null,
        pendingTarget: null,
        phase: "blocked",
      },
    };
  }

  if (state.phase === "acquiring") {
    const acquired = state.pendingTarget;
    if (state.desired === acquired) {
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
    return issue(state, "stopping", "stop", acquired, acquired, state.desired);
  }

  if (state.phase === "stopping") {
    return issue(
      state,
      "releasing",
      "release",
      state.owner,
      state.owner,
      state.desired
    );
  }

  return issue(
    state,
    "acquiring",
    "acquire",
    state.desired,
    null,
    state.desired
  );
};

const retry = (state) => {
  if (state.phase !== "blocked") {
    return unchanged(state);
  }

  return state.blockedStage === "stopping"
    ? issue(state, "stopping", "stop", state.owner, state.owner, state.desired)
    : issue(
        state,
        "releasing",
        "release",
        state.owner,
        state.owner,
        state.desired
      );
};

export const transition = (state, event) => {
  if (!event || typeof event !== "object") {
    return unchanged(state);
  }

  switch (event.type) {
    case "start": {
      return start(state, event.target);
    }
    case "fail":
    case "ok": {
      return completion(state, event);
    }
    case "retry": {
      return retry(state);
    }
    default: {
      return unchanged(state);
    }
  }
};

const effect = (id, target, type) => ({ id, target, type });
const event = (id, type) => ({ id, type });
const startEvent = (target) => ({ target, type: "start" });
const row = (desired, effects, operationId, owner, phase) => ({
  desired,
  effects,
  operationId,
  owner,
  phase,
});

const drive = (events) => {
  let state = initial();
  return events.map((input) => {
    const { effects, state: nextState } = transition(state, input);
    state = nextState;
    const { desired, operationId, owner, phase } = observe(state);
    return row(desired, effects, operationId, owner, phase);
  });
};

const cases = [
  {
    events: [startEvent("recording"), event("operation-1", "ok")],
    expected: [
      row(
        "recording",
        [effect("operation-1", "recording", "acquire")],
        "operation-1",
        null,
        "acquiring"
      ),
      row("recording", [], null, "recording", "active"),
    ],
    name: "normal-completes",
  },
  {
    events: [
      startEvent("recording"),
      startEvent("calibration"),
      startEvent("recording"),
      event("operation-1", "ok"),
      startEvent("calibration"),
      startEvent("recording"),
      event("operation-2", "ok"),
      startEvent("calibration"),
      startEvent("recording"),
      event("operation-3", "ok"),
      event("operation-4", "ok"),
    ],
    expected: [
      row(
        "recording",
        [effect("operation-1", "recording", "acquire")],
        "operation-1",
        null,
        "acquiring"
      ),
      row("calibration", [], "operation-1", null, "acquiring"),
      row("recording", [], "operation-1", null, "acquiring"),
      row("recording", [], null, "recording", "active"),
      row(
        "calibration",
        [effect("operation-2", "recording", "stop")],
        "operation-2",
        "recording",
        "stopping"
      ),
      row("recording", [], "operation-2", "recording", "stopping"),
      row(
        "recording",
        [effect("operation-3", "recording", "release")],
        "operation-3",
        "recording",
        "releasing"
      ),
      row("calibration", [], "operation-3", "recording", "releasing"),
      row("recording", [], "operation-3", "recording", "releasing"),
      row(
        "recording",
        [effect("operation-4", "recording", "acquire")],
        "operation-4",
        null,
        "acquiring"
      ),
      row("recording", [], null, "recording", "active"),
    ],
    name: "latest-intent-wins-through-waiting",
  },
  {
    events: [
      startEvent("recording"),
      event("operation-1", "fail"),
      { type: "retry" },
      event("operation-1", "ok"),
      startEvent("recording"),
    ],
    expected: [
      row(
        "recording",
        [effect("operation-1", "recording", "acquire")],
        "operation-1",
        null,
        "acquiring"
      ),
      row("recording", [], null, null, "idle"),
      row("recording", [], null, null, "idle"),
      row("recording", [], null, null, "idle"),
      row(
        "recording",
        [effect("operation-2", "recording", "acquire")],
        "operation-2",
        null,
        "acquiring"
      ),
    ],
    name: "acquisition-failure-needs-a-new-start",
  },
  {
    events: [
      startEvent("recording"),
      event("operation-1", "ok"),
      startEvent("calibration"),
      event("operation-2", "fail"),
      startEvent("recording"),
      { type: "retry" },
      event("operation-3", "ok"),
      event("operation-4", "fail"),
      startEvent("calibration"),
      { type: "retry" },
      event("operation-4", "ok"),
      event("operation-5", "ok"),
      event("operation-6", "ok"),
    ],
    expected: [
      row(
        "recording",
        [effect("operation-1", "recording", "acquire")],
        "operation-1",
        null,
        "acquiring"
      ),
      row("recording", [], null, "recording", "active"),
      row(
        "calibration",
        [effect("operation-2", "recording", "stop")],
        "operation-2",
        "recording",
        "stopping"
      ),
      row("calibration", [], null, "recording", "blocked"),
      row("recording", [], null, "recording", "blocked"),
      row(
        "recording",
        [effect("operation-3", "recording", "stop")],
        "operation-3",
        "recording",
        "stopping"
      ),
      row(
        "recording",
        [effect("operation-4", "recording", "release")],
        "operation-4",
        "recording",
        "releasing"
      ),
      row("recording", [], null, "recording", "blocked"),
      row("calibration", [], null, "recording", "blocked"),
      row(
        "calibration",
        [effect("operation-5", "recording", "release")],
        "operation-5",
        "recording",
        "releasing"
      ),
      row("calibration", [], "operation-5", "recording", "releasing"),
      row(
        "calibration",
        [effect("operation-6", "calibration", "acquire")],
        "operation-6",
        null,
        "acquiring"
      ),
      row("calibration", [], null, "calibration", "active"),
    ],
    name: "blocked-stages-retry-only-the-failure",
  },
];

export const runSelfCheck = () =>
  cases.map(({ events, expected, name }) => {
    const actual = drive(events);
    assert.deepEqual(actual, expected);
    const result = { actual, events, expected, name, result: "passed" };
    console.log(JSON.stringify(result));
    return result;
  });

export const checkProfileIsIndependent = () => {
  const state = initial();
  const result = transition(state, { type: "profile" });
  assert.strictEqual(result.state, state);
  assert.deepEqual(result.effects, []);
  return { name: "profile-is-independent", result: "passed" };
};

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  runSelfCheck();
  console.log(JSON.stringify(checkProfileIsIndependent()));
}
