import assert from "node:assert/strict";

export const initial = () => ({
  error: null,
  latestId: null,
  nextId: 1,
  pending: false,
  results: null,
});

export const observe = ({ error, latestId, pending, results }) => ({
  error,
  latestId,
  pending,
  results,
});

export const transition = (state, event) => {
  if (event.type === "search") {
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
  if (event.type !== "success" && event.type !== "failure") {
    return { effects: [], state };
  }
  if (event.id !== state.latestId) {
    return { effects: [], state };
  }
  return event.type === "success"
    ? {
        effects: [],
        state: {
          ...state,
          error: null,
          pending: false,
          results: event.results,
        },
      }
    : { effects: [], state: { ...state, error: event.error, pending: false } };
};

const check = () => {
  let state = initial();
  let result = transition(state, { text: "cat", type: "search" });
  assert.deepEqual(result.effects, [{ id: 1, text: "cat", type: "query" }]);
  ({ state } = result);
  result = transition(state, { text: "dog", type: "search" });
  ({ state } = result);
  assert.deepEqual(observe(state), {
    error: null,
    latestId: 2,
    pending: true,
    results: null,
  });
  assert.equal(
    transition(state, { id: 1, results: ["old"], type: "success" }).state,
    state
  );
  assert.equal(
    transition(state, { error: "old failure", id: 1, type: "failure" }).state,
    state
  );
  ({ state } = transition(state, { id: 2, results: ["new"], type: "success" }));
  assert.deepEqual(observe(state), {
    error: null,
    latestId: 2,
    pending: false,
    results: ["new"],
  });

  ({ state } = transition(state, { text: "dog", type: "search" }));
  assert.equal(state.latestId, 3);
  ({ state } = transition(state, {
    error: "current failure",
    id: 3,
    type: "failure",
  }));
  assert.deepEqual(observe(state), {
    error: "current failure",
    latestId: 3,
    pending: false,
    results: ["new"],
  });
};

check();
console.log("S self-check: ok");
