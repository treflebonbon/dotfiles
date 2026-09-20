const unchanged = (state) => ({ effects: [], state });

export const initial = () => ({
  error: null,
  latestId: null,
  nextId: 1,
  pending: false,
  result: null,
});

export const observe = (state) => ({
  error: state.error,
  latestId: state.latestId,
  pending: state.pending,
  result: state.result,
});

export const transition = (state, event) => {
  if (event.type === "search" && typeof event.text === "string") {
    const id = state.nextId;
    return {
      effects: [{ id, text: event.text, type: "query" }],
      state: {
        ...state,
        error: null,
        latestId: id,
        nextId: id + 1,
        pending: true,
      },
    };
  }
  if (
    (event.type !== "success" && event.type !== "failure") ||
    event.id !== state.latestId
  ) {
    return unchanged(state);
  }
  if (event.type === "success") {
    return {
      effects: [],
      state: { ...state, error: null, pending: false, result: event.result },
    };
  }
  return {
    effects: [],
    state: { ...state, error: event.error, pending: false },
  };
};

const assert = (condition, message) => {
  if (!condition) {
    throw new Error(message);
  }
};
const onlyEffect = ({ effects }) => {
  const [effect] = effects;
  return effect;
};
const stateOf = ({ state }) => state;

export const selfCheck = () => {
  let state = initial();
  let out = transition(state, { text: "tea", type: "search" });
  state = stateOf(out);
  const { id: teaId } = onlyEffect(out);
  state = stateOf(
    transition(state, {
      id: teaId,
      result: ["tea"],
      type: "success",
    })
  );
  const { pending: teaPending, result: teaResult } = observe(state);
  assert(teaResult[0] === "tea" && !teaPending, "normal current success");

  state = initial();
  const first = transition(state, { text: "alpha", type: "search" });
  state = stateOf(first);
  const second = transition(state, { text: "beta", type: "search" });
  state = stateOf(second);
  const third = transition(state, { text: "alpha", type: "search" });
  state = stateOf(third);
  const { id: firstId } = onlyEffect(first);
  const { id: secondId } = onlyEffect(second);
  const { id: thirdId } = onlyEffect(third);
  assert(firstId !== thirdId, "same text receives a new identity");
  const beforeStale = state;
  assert(
    stateOf(
      transition(state, {
        id: firstId,
        result: ["old"],
        type: "success",
      })
    ) === beforeStale,
    "stale success ignored"
  );
  assert(
    stateOf(
      transition(state, {
        error: "old failure",
        id: secondId,
        type: "failure",
      })
    ) === beforeStale,
    "stale failure ignored"
  );
  state = stateOf(
    transition(state, {
      id: thirdId,
      result: ["new alpha"],
      type: "success",
    })
  );
  const { pending: alphaPending, result: alphaResult } = observe(state);
  assert(
    alphaResult[0] === "new alpha" && !alphaPending,
    "current success accepted"
  );
  out = transition(state, { text: "gamma", type: "search" });
  state = stateOf(out);
  const { id: gammaId } = onlyEffect(out);
  assert(
    stateOf(
      transition(state, {
        id: thirdId,
        result: ["late alpha"],
        type: "success",
      })
    ) === state,
    "new pending survives stale success"
  );
  state = stateOf(
    transition(state, {
      error: "network",
      id: gammaId,
      type: "failure",
    })
  );
  const { error, pending } = observe(state);
  assert(error === "network" && !pending, "current failure accepted");
  return "S self-check: 2 cases passed";
};

if (process.argv[1] === import.meta.filename) {
  console.log(selfCheck());
}
