import assert from "node:assert/strict";

// Existing React/Query binding and execution layer: it owns every request's normal status.
const createQueryBinding = () => {
  const requests = new Map();

  return {
    abort(id) {
      const request = requests.get(id);
      if (request?.status === "pending") {
        request.abortRequested = true;
      }
      return `abort:${id}:best-effort:no-rollback`;
    },
    execute(request) {
      requests.set(request.id, { ...request, status: "pending" });
      return `execute:${request.id}`;
    },
    read(id) {
      return requests.get(id);
    },
    settle(id, status, payload) {
      const request = requests.get(id);
      assert.ok(request, `unknown request: ${id}`);
      Object.assign(
        request,
        status === "success"
          ? { status, value: payload }
          : { error: payload, status }
      );
      return `settle:${status}:${id}`;
    },
  };
};

// Added mediator state is only the request identity whose binding state may be displayed.
const createSearchMediator = (binding) => {
  let currentRequestId;
  let nextRequestNumber = 0;

  return {
    currentRequestId() {
      return currentRequestId;
    },
    settle(id, status, payload) {
      return {
        adopted: id === currentRequestId,
        effects: [binding.settle(id, status, payload)],
      };
    },
    submit(text) {
      const previousRequestId = currentRequestId;
      nextRequestNumber += 1;
      currentRequestId = `request-${nextRequestNumber}`;
      const effects = previousRequestId
        ? [binding.abort(previousRequestId)]
        : [];
      effects.push(binding.execute({ id: currentRequestId, text }));
      return { adopted: true, effects };
    },
  };
};

const createModel = () => {
  const binding = createQueryBinding();
  const mediator = createSearchMediator(binding);
  let helpOpen = false;

  const view = () => {
    const request = binding.read(mediator.currentRequestId());
    return {
      error: request?.status === "error" ? request.error : null,
      helpOpen,
      pending: request?.status === "pending",
      requestId: request?.id ?? null,
      result: request?.status === "success" ? request.value : null,
      text: request?.text ?? "",
    };
  };

  return {
    dispatch(event) {
      if (event.type === "submit") {
        const decision = mediator.submit(event.text);
        return {
          after: view(),
          ...decision,
          resourceOwner: `binding:${mediator.currentRequestId()}`,
        };
      }
      if (event.type === "help") {
        helpOpen = event.open;
        return {
          adopted: false,
          after: view(),
          effects: [],
          resourceOwner: "view:help-tooltip",
        };
      }
      const decision = mediator.settle(event.id, event.type, event.payload);
      return {
        after: view(),
        ...decision,
        resourceOwner: `binding:${event.id}`,
      };
    },
  };
};

const state = (requestId, text, pending, result, error, helpOpen = false) => ({
  error,
  helpOpen,
  pending,
  requestId,
  result,
  text,
});

const event = {
  error: (id, payload) => ({ id, payload, type: "error" }),
  help: (open) => ({ open, type: "help" }),
  submit: (text) => ({ text, type: "submit" }),
  success: (id, payload) => ({ id, payload, type: "success" }),
};

const expected = (after, adopted, effects, resourceOwner) => ({
  adopted,
  after,
  effects,
  resourceOwner,
});

const cases = [
  {
    events: [event.submit("alpha"), event.success("request-1", "alpha result")],
    expected: [
      expected(
        state("request-1", "alpha", true, null, null),
        true,
        ["execute:request-1"],
        "binding:request-1"
      ),
      expected(
        state("request-1", "alpha", false, "alpha result", null),
        true,
        ["settle:success:request-1"],
        "binding:request-1"
      ),
    ],
    name: "normal-completes",
  },
  {
    events: [event.submit("broken"), event.error("request-1", "network")],
    expected: [
      expected(
        state("request-1", "broken", true, null, null),
        true,
        ["execute:request-1"],
        "binding:request-1"
      ),
      expected(
        state("request-1", "broken", false, null, "network"),
        true,
        ["settle:error:request-1"],
        "binding:request-1"
      ),
    ],
    name: "failure-is-visible",
  },
  {
    events: [
      event.submit("tea"),
      event.submit("tea"),
      event.submit("tea"),
      event.success("request-1", "stale success"),
      event.error("request-2", "stale failure"),
      event.success("request-3", "fresh result"),
    ],
    expected: [
      expected(
        state("request-1", "tea", true, null, null),
        true,
        ["execute:request-1"],
        "binding:request-1"
      ),
      expected(
        state("request-2", "tea", true, null, null),
        true,
        ["abort:request-1:best-effort:no-rollback", "execute:request-2"],
        "binding:request-2"
      ),
      expected(
        state("request-3", "tea", true, null, null),
        true,
        ["abort:request-2:best-effort:no-rollback", "execute:request-3"],
        "binding:request-3"
      ),
      expected(
        state("request-3", "tea", true, null, null),
        false,
        ["settle:success:request-1"],
        "binding:request-1"
      ),
      expected(
        state("request-3", "tea", true, null, null),
        false,
        ["settle:error:request-2"],
        "binding:request-2"
      ),
      expected(
        state("request-3", "tea", false, "fresh result", null),
        true,
        ["settle:success:request-3"],
        "binding:request-3"
      ),
    ],
    name: "same-text-reentry-ignores-stale-success-and-failure",
  },
  {
    events: [
      event.submit("guide"),
      event.help(true),
      event.success("request-1", "guide result"),
    ],
    expected: [
      expected(
        state("request-1", "guide", true, null, null),
        true,
        ["execute:request-1"],
        "binding:request-1"
      ),
      expected(
        state("request-1", "guide", true, null, null, true),
        false,
        [],
        "view:help-tooltip"
      ),
      expected(
        state("request-1", "guide", false, "guide result", null, true),
        true,
        ["settle:success:request-1"],
        "binding:request-1"
      ),
    ],
    name: "tooltip-is-local",
  },
];

for (const testCase of cases) {
  const model = createModel();
  const actual = testCase.events.map((item) => model.dispatch(item));
  assert.deepEqual(actual, testCase.expected);
  console.log(
    JSON.stringify({
      actual,
      events: testCase.events,
      expected: testCase.expected,
      name: testCase.name,
      result: "passed",
    })
  );
}
