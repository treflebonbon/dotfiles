import assert from "node:assert/strict";

const initialState = () => ({
  currentRequestId: null,
  nextRequestId: 0,
  pending: false,
  result: { kind: "idle" },
});

// UI result-acceptance owner: the existing binding executes these effects.
const searchResultAcceptanceMediator = (state, text) => {
  const requestId = state.nextRequestId + 1;
  const effects = [{ requestId, text, type: "binding.execute" }];

  if (state.currentRequestId !== null) {
    effects.unshift({
      requestId: state.currentRequestId,
      type: "binding.cancelBestEffort",
    });
  }

  return {
    effects,
    state: {
      ...state,
      currentRequestId: requestId,
      nextRequestId: requestId,
      pending: true,
    },
  };
};

const acceptBindingCompletion = (state, completion) => {
  if (completion.requestId !== state.currentRequestId) {
    return state;
  }

  if (completion.kind === "success") {
    return {
      ...state,
      pending: false,
      result: { data: completion.data, kind: "success" },
    };
  }

  return {
    ...state,
    pending: false,
    result: { error: completion.error, kind: "failure" },
  };
};

let state = initialState();
const { state: firstState } = searchResultAcceptanceMediator(state, "cat");
state = firstState;
const { effects: newestEffects, state: newestState } =
  searchResultAcceptanceMediator(state, "cat");
state = newestState;

assert.notEqual(firstState.currentRequestId, newestState.currentRequestId);
assert.deepEqual(newestEffects, [
  { requestId: firstState.currentRequestId, type: "binding.cancelBestEffort" },
  {
    requestId: newestState.currentRequestId,
    text: "cat",
    type: "binding.execute",
  },
]);

const pendingNewest = state;
state = acceptBindingCompletion(state, {
  data: ["stale cat"],
  kind: "success",
  requestId: firstState.currentRequestId,
});
assert.deepEqual(state, pendingNewest);

state = acceptBindingCompletion(state, {
  error: "stale failure",
  kind: "failure",
  requestId: firstState.currentRequestId,
});
assert.deepEqual(state, pendingNewest);

state = acceptBindingCompletion(state, {
  data: ["current cat"],
  kind: "success",
  requestId: newestState.currentRequestId,
});
assert.deepEqual(state, {
  currentRequestId: 2,
  nextRequestId: 2,
  pending: false,
  result: { data: ["current cat"], kind: "success" },
});

const { state: failingState } = searchResultAcceptanceMediator(state, "dog");
state = acceptBindingCompletion(failingState, {
  error: "current failure",
  kind: "failure",
  requestId: failingState.currentRequestId,
});
assert.deepEqual(state, {
  currentRequestId: 3,
  nextRequestId: 3,
  pending: false,
  result: { error: "current failure", kind: "failure" },
});

console.log("r5s self-check: passed");
