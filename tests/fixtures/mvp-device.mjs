// Reference decision model retained from v9 attempt04 (52-case parent check passed).
const targets = new Set(["recording", "calibration"]);
const none = (state) => ({ effects: [], state });
const validTarget = (target) => targets.has(target);

const make = (phase, owner, desired, pending, next, failed = null) =>
  Object.freeze({
    desired,
    failed,
    next,
    owner,
    pending: pending && Object.freeze(pending),
    phase,
  });

const begin = (state, phase, owner, desired, type, target) => {
  const id = state.next;
  return {
    effects: [{ id, target, type }],
    state: make(phase, owner, desired, { id, stage: type, target }, id + 1),
  };
};

const withDesired = (state, desired) =>
  desired === state.desired
    ? none(state)
    : {
        effects: [],
        state: make(
          state.phase,
          state.owner,
          desired,
          state.pending,
          state.next,
          state.failed
        ),
      };

/** A fresh run; internal fields deliberately remain private to this module's API. */
export const initial = () => make("idle", null, null, null, 1);

export const observe = (state) => ({
  desired: state.desired,
  operationId: state.pending ? state.pending.id : null,
  owner: state.owner,
  phase: state.phase,
});

const complete = (state, event) => {
  if (event.type !== "ok" && event.type !== "fail") {
    return none(state);
  }
  const { pending } = state;
  if (!pending || pending.id !== event.id) {
    return none(state);
  }

  if (event.type === "fail") {
    return pending.stage === "acquire"
      ? {
          effects: [],
          state: make("idle", null, state.desired, null, state.next),
        }
      : {
          effects: [],
          state: make(
            "blocked",
            state.owner,
            state.desired,
            null,
            state.next,
            pending.stage
          ),
        };
  }

  switch (pending.stage) {
    case "acquire": {
      return state.desired === pending.target
        ? {
            effects: [],
            state: make(
              "active",
              pending.target,
              state.desired,
              null,
              state.next
            ),
          }
        : begin(
            state,
            "stopping",
            pending.target,
            state.desired,
            "stop",
            pending.target
          );
    }
    case "stop": {
      return begin(
        state,
        "releasing",
        state.owner,
        state.desired,
        "release",
        state.owner
      );
    }
    case "release": {
      return begin(
        state,
        "acquiring",
        null,
        state.desired,
        "acquire",
        state.desired
      );
    }
    default: {
      return none(state);
    }
  }
};

/** Pure policy: the caller executes returned commands and feeds their completion back. */
export const transition = (state, event) => {
  if (!event || typeof event.type !== "string") {
    return none(state);
  }
  if (event.type === "profile") {
    return none(state);
  }

  if (event.type === "start") {
    if (!validTarget(event.target)) {
      return none(state);
    }
    switch (state.phase) {
      case "idle": {
        return begin(
          state,
          "acquiring",
          null,
          event.target,
          "acquire",
          event.target
        );
      }
      case "acquiring":
      case "stopping":
      case "releasing":
      case "blocked": {
        return withDesired(state, event.target);
      }
      case "active": {
        return state.owner === event.target
          ? none(state)
          : begin(
              state,
              "stopping",
              state.owner,
              event.target,
              "stop",
              state.owner
            );
      }
      default: {
        return none(state);
      }
    }
  }

  if (event.type === "retry") {
    if (state.phase !== "blocked") {
      return none(state);
    }
    return begin(
      state,
      state.failed === "stop" ? "stopping" : "releasing",
      state.owner,
      state.desired,
      state.failed,
      state.owner
    );
  }

  return complete(state, event);
};
