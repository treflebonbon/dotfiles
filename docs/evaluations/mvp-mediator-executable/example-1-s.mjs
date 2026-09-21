import assert from "node:assert/strict";

const initial = () => ({
  binding: { requests: {} },
  mediator: { latestRequestId: null, nextRequestId: 1 },
});

const issue = (binding, request) => ({
  requests: {
    ...binding.requests,
    [request.id]: { ...request, error: null, pending: true, result: null },
  },
});

const settle = (binding, { id, type, value }) => ({
  requests: {
    ...binding.requests,
    [id]: {
      ...binding.requests[id],
      error: type === "failure" ? value : null,
      pending: false,
      result: type === "success" ? value : null,
    },
  },
});

const step = (state, event) => {
  if (event.type === "search") {
    const id = state.mediator.nextRequestId;
    return [
      {
        binding: issue(state.binding, { id, text: event.text }),
        mediator: { latestRequestId: id, nextRequestId: id + 1 },
      },
      "Query binding が request を発行",
    ];
  }

  const binding = settle(state.binding, event);
  const accepted = event.id === state.mediator.latestRequestId;
  return [
    { ...state, binding },
    accepted
      ? "Query binding が完了を記録し、Mediator が表示に採用"
      : "Query binding が完了を記録し、Mediator が表示から除外",
  ];
};

const observe = (state) => {
  const request = state.binding.requests[state.mediator.latestRequestId];
  return {
    displayed: request && {
      error: request.error,
      pending: request.pending,
      result: request.result,
    },
    latestRequestId: state.mediator.latestRequestId,
  };
};

const run = (events) => {
  let state = initial();
  return events.map((event) => {
    const [next, effect] = step(state, event);
    state = next;
    return {
      after: observe(state),
      effect,
      event,
      resourceOwner: "Query binding",
    };
  });
};

const pending = (id) => ({
  displayed: { error: null, pending: true, result: null },
  latestRequestId: id,
});

const cases = [
  {
    events: [
      { text: "tea", type: "search" },
      { id: 1, type: "success", value: ["tea-1"] },
    ],
    expected: [
      pending(1),
      {
        displayed: { error: null, pending: false, result: ["tea-1"] },
        latestRequestId: 1,
      },
    ],
    name: "normal-current-success",
  },
  {
    events: [
      { text: "tea", type: "search" },
      { id: 1, type: "failure", value: "timeout" },
    ],
    expected: [
      pending(1),
      {
        displayed: { error: "timeout", pending: false, result: null },
        latestRequestId: 1,
      },
    ],
    name: "current-failure-applies",
  },
  {
    events: [
      { text: "tea", type: "search" },
      { text: "tea", type: "search" },
      { id: 1, type: "success", value: ["old-tea"] },
      { id: 2, type: "success", value: ["new-tea"] },
    ],
    expected: [
      pending(1),
      pending(2),
      pending(2),
      {
        displayed: { error: null, pending: false, result: ["new-tea"] },
        latestRequestId: 2,
      },
    ],
    name: "stale-success-cannot-replace-repeated-text",
  },
  {
    events: [
      { text: "tea", type: "search" },
      { text: "coffee", type: "search" },
      { id: 1, type: "failure", value: "old-timeout" },
      { id: 2, type: "success", value: ["coffee-1"] },
    ],
    expected: [
      pending(1),
      pending(2),
      pending(2),
      {
        displayed: { error: null, pending: false, result: ["coffee-1"] },
        latestRequestId: 2,
      },
    ],
    name: "stale-failure-cannot-replace-newer-pending",
  },
];

for (const { name, events, expected } of cases) {
  const actual = run(events);
  assert.deepEqual(
    actual.map(({ after }) => after),
    expected
  );
  console.log(JSON.stringify({ actual, expected, name, result: "passed" }));
}
