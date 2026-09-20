import assert from "node:assert/strict";

export const initial = () => ({ latest: null, nextId: 1, result: null });

export const observe = ({ latest, result }) => ({
  pending: latest !== null,
  requestId: latest?.id ?? null,
  result,
  text: latest?.text ?? null,
});

export const transition = (state, event) => {
  if (event.type === "search") {
    const request = { id: state.nextId, text: event.text };
    return {
      request,
      state: {
        ...state,
        latest: request,
        nextId: state.nextId + 1,
        result: null,
      },
    };
  }
  if (
    (event.type === "ok" || event.type === "fail") &&
    event.id === state.latest?.id
  ) {
    return {
      request: null,
      state: {
        ...state,
        latest: null,
        result:
          event.type === "ok" ? { data: event.data } : { error: event.error },
      },
    };
  }
  return { request: null, state };
};

const selfCheck = () => {
  const advance = (state, event) => transition(state, event).state;
  let state = initial();
  let result = transition(state, { text: "first", type: "search" });
  state = advance(state, { text: "first", type: "search" });
  assert.deepEqual(result.request, { id: 1, text: "first" });
  result = transition(state, { text: "second", type: "search" });
  state = advance(state, { text: "second", type: "search" });
  assert.deepEqual(observe(state), {
    pending: true,
    requestId: 2,
    result: null,
    text: "second",
  });
  assert.equal(
    transition(state, { data: ["stale"], id: 1, type: "ok" }).state,
    state
  );
  assert.equal(
    transition(state, { error: "stale", id: 1, type: "fail" }).state,
    state
  );
  result = transition(state, { data: ["current"], id: 2, type: "ok" });
  assert.deepEqual(observe(result.state), {
    pending: false,
    requestId: null,
    result: { data: ["current"] },
    text: null,
  });

  state = advance(initial(), { text: "same", type: "search" });
  result = transition(state, { text: "same", type: "search" });
  state = advance(state, { text: "same", type: "search" });
  assert.deepEqual(result.request, { id: 2, text: "same" });
  assert.equal(
    transition(state, { data: ["old"], id: 1, type: "ok" }).state,
    state
  );
  result = transition(state, { error: "current failure", id: 2, type: "fail" });
  assert.deepEqual(observe(result.state).result, { error: "current failure" });
};

if (process.argv[1] === import.meta.filename) {
  selfCheck();
  console.log("S self-check: passed (2 cases)");
}
