import assert from "node:assert/strict";
import path from "node:path";

// SearchResultMediator owns only result-acceptance policy. Query owns execution.
export const initialMediator = () => ({ latestRequestId: null });

export const beginSearch = (mediator, requestId) => {
  if (!Number.isInteger(requestId)) {
    throw new TypeError("requestId must be an integer");
  }

  return { latestRequestId: requestId };
};

export const acceptsResult = (mediator, requestId) =>
  mediator.latestRequestId === requestId;

// This is a Query-binding mock: pending/result/failure are execution-layer state.
export const initialBinding = () => ({
  failure: null,
  pending: null,
  result: null,
});

export const issue = (binding, mediator, requestId, text) => ({
  binding: { ...binding, pending: { requestId, text } },
  mediator: beginSearch(mediator, requestId),
});

export const settle = (binding, mediator, completion) => {
  if (!acceptsResult(mediator, completion.requestId)) {
    return { accepted: false, binding };
  }

  return completion.kind === "success"
    ? {
        accepted: true,
        binding: {
          failure: null,
          pending: null,
          result: completion.value,
        },
      }
    : {
        accepted: true,
        binding: {
          failure: completion.value,
          pending: null,
          result: null,
        },
      };
};

export const runSelfCheck = () => {
  let mediator = initialMediator();
  let binding = initialBinding();

  // Normal path: initial state -> request -> current success.
  ({ binding, mediator } = issue(binding, mediator, 1, "alpha"));
  let completion = settle(binding, mediator, {
    kind: "success",
    requestId: 1,
    value: ["alpha"],
  });
  assert.equal(completion.accepted, true);
  ({ binding } = completion);
  assert.deepEqual(binding, {
    failure: null,
    pending: null,
    result: ["alpha"],
  });

  // A stale success cannot replace a newer request's pending state or result.
  ({ binding, mediator } = issue(binding, mediator, 2, "old"));
  ({ binding, mediator } = issue(binding, mediator, 3, "new"));
  const beforeStaleSuccess = binding;
  completion = settle(binding, mediator, {
    kind: "success",
    requestId: 2,
    value: ["old"],
  });
  assert.equal(completion.accepted, false);
  assert.deepEqual(completion.binding, beforeStaleSuccess);
  completion = settle(binding, mediator, {
    kind: "success",
    requestId: 3,
    value: ["new"],
  });
  assert.equal(completion.accepted, true);
  ({ binding } = completion);
  assert.deepEqual(binding, {
    failure: null,
    pending: null,
    result: ["new"],
  });

  // Equal text still creates distinct requests; stale failure is rejected by ID.
  ({ binding, mediator } = issue(binding, mediator, 4, "again"));
  ({ binding, mediator } = issue(binding, mediator, 5, "again"));
  const beforeStaleFailure = binding;
  completion = settle(binding, mediator, {
    kind: "failure",
    requestId: 4,
    value: "old failure",
  });
  assert.equal(completion.accepted, false);
  assert.deepEqual(completion.binding, beforeStaleFailure);
  completion = settle(binding, mediator, {
    kind: "failure",
    requestId: 5,
    value: "current failure",
  });
  assert.equal(completion.accepted, true);
  assert.deepEqual(completion.binding, {
    failure: "current failure",
    pending: null,
    result: null,
  });

  return [
    "normal-current-success",
    "stale-success",
    "repeated-text-stale-failure",
  ];
};

if (process.argv[1] && path.resolve(process.argv[1]) === import.meta.filename) {
  console.log(`confirm-s self-check: PASS (${runSelfCheck().join(", ")})`);
}
