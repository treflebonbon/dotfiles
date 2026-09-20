import assert from "node:assert/strict";

const initialState = {
  latestRequestId: null,
  nextRequestId: 1,
  view: { error: null, pending: false, result: null },
};

/**
 * The search-result Mediator's pure coordination rule. The existing Query
 * binding executes `run` and supplies its normal pending/result notifications.
 */
export const transition = (state, event) => {
  switch (event.type) {
    case "search": {
      const requestId = state.nextRequestId;
      return {
        run: { requestId, text: event.text },
        state: {
          latestRequestId: requestId,
          nextRequestId: requestId + 1,
          view: { error: null, pending: true, result: null },
        },
      };
    }
    case "success": {
      if (event.requestId !== state.latestRequestId) {
        return { state };
      }
      return {
        state: {
          ...state,
          view: { error: null, pending: false, result: event.result },
        },
      };
    }
    case "failure": {
      if (event.requestId !== state.latestRequestId) {
        return { state };
      }
      return {
        state: {
          ...state,
          view: { error: event.error, pending: false, result: null },
        },
      };
    }
    default: {
      throw new Error(`Unknown event: ${event.type}`);
    }
  }
};

const apply = (state, event) => transition(state, event).state;

export const selfCheck = () => {
  let state = initialState;

  const { run: firstRun, state: firstState } = transition(state, {
    text: "cats",
    type: "search",
  });
  state = firstState;
  assert.deepEqual(firstRun, { requestId: 1, text: "cats" });
  state = apply(state, { requestId: 1, result: ["cat-1"], type: "success" });
  assert.deepEqual(state.view, {
    error: null,
    pending: false,
    result: ["cat-1"],
  });

  const { state: secondState } = transition(state, {
    text: "dogs",
    type: "search",
  });
  state = secondState;
  assert.deepEqual(state.view, { error: null, pending: true, result: null });
  const afterStaleSuccess = apply(state, {
    requestId: 1,
    result: ["stale-cat"],
    type: "success",
  });
  assert.deepEqual(afterStaleSuccess, state);
  const afterStaleFailure = apply(state, {
    error: "stale failure",
    requestId: 1,
    type: "failure",
  });
  assert.deepEqual(afterStaleFailure, state);
  state = apply(state, { requestId: 2, result: ["dog-1"], type: "success" });
  assert.deepEqual(state.view, {
    error: null,
    pending: false,
    result: ["dog-1"],
  });

  const { run: sameTextAgainRun, state: sameTextAgainState } = transition(
    state,
    {
      text: "dogs",
      type: "search",
    }
  );
  state = sameTextAgainState;
  assert.deepEqual(sameTextAgainRun, { requestId: 3, text: "dogs" });
  assert.deepEqual(
    apply(state, {
      error: "old dogs failure",
      requestId: 2,
      type: "failure",
    }),
    state
  );
  state = apply(state, {
    error: "current failure",
    requestId: 3,
    type: "failure",
  });
  assert.deepEqual(state.view, {
    error: "current failure",
    pending: false,
    result: null,
  });
};

if (import.meta.main) {
  selfCheck();
  console.log("s3 self-check: ok");
}
