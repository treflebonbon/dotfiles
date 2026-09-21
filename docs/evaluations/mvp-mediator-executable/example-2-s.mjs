import assert from "node:assert/strict";

let nextRequestId = 0;

// Existing Query-like binding: it executes requests and owns their normal status/result.
const createBinding = () => ({ effects: [], requests: new Map() });

const execute = (binding, text) => {
  nextRequestId += 1;
  const id = `request-${nextRequestId}`;
  binding.requests.set(id, { status: "pending", text });
  binding.effects.push(`execute:${id}`);
  return id;
};

const finish = (binding, id, outcome) => {
  binding.requests.set(id, { ...binding.requests.get(id), ...outcome });
  binding.effects.push(`${outcome.status}:${id}`);
};

const cancel = (binding, id) => {
  const request = binding.requests.get(id);
  if (request?.status === "pending") {
    request.cancelRequested = true;
  }
  binding.effects.push(`cancel-best-effort:${id}`);
};

// The only added result-admission state: one request identity, owned by this Mediator.
const createMediator = (binding) => ({ binding, currentRequestId: null });

const search = (mediator, text) => {
  if (mediator.currentRequestId) {
    cancel(mediator.binding, mediator.currentRequestId);
  }
  mediator.currentRequestId = execute(mediator.binding, text);
  return mediator.currentRequestId;
};

const view = (mediator) => {
  const request = mediator.binding.requests.get(mediator.currentRequestId);
  if (!request) {
    return { requestId: null, status: "idle" };
  }
  return Object.fromEntries(
    Object.entries({
      error: request.error,
      requestId: mediator.currentRequestId,
      result: request.result,
      status: request.status,
      text: request.text,
    }).filter(([, value]) => value !== undefined)
  );
};

// Passive View-local state; it never changes Mediator state.
const tooltip = (isOpen) => ({ isOpen });

const snapshot = (mediator) => ({
  owner: "mediator:currentRequestId",
  view: view(mediator),
});

const cases = [
  {
    name: "normal-current-success",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const id = search(mediator, "cats");
      const running = snapshot(mediator);
      finish(binding, id, { result: ["cat"], status: "success" });
      return {
        actual: [running.view, view(mediator)],
        effects: binding.effects,
        events: ["search(cats)", "success(current)"],
        expected: [
          { requestId: id, status: "pending", text: "cats" },
          { requestId: id, result: ["cat"], status: "success", text: "cats" },
        ],
        resourceOwner: "binding:request record",
      };
    },
  },
  {
    name: "normal-current-failure",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const id = search(mediator, "cats");
      const running = snapshot(mediator);
      finish(binding, id, { error: "offline", status: "error" });
      return {
        actual: [running.view, view(mediator)],
        effects: binding.effects,
        events: ["search(cats)", "failure(current)"],
        expected: [
          { requestId: id, status: "pending", text: "cats" },
          { error: "offline", requestId: id, status: "error", text: "cats" },
        ],
        resourceOwner: "binding:request record",
      };
    },
  },
  {
    name: "stale-success-keeps-new-request-pending",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const oldId = search(mediator, "cats");
      const currentId = search(mediator, "dogs");
      finish(binding, oldId, { result: ["cat"], status: "success" });
      const afterStale = view(mediator);
      finish(binding, currentId, { result: ["dog"], status: "success" });
      return {
        actual: [afterStale, view(mediator)],
        effects: binding.effects,
        events: [
          "search(cats)",
          "search(dogs)",
          "success(stale cats)",
          "success(current dogs)",
        ],
        expected: [
          { requestId: currentId, status: "pending", text: "dogs" },
          {
            requestId: currentId,
            result: ["dog"],
            status: "success",
            text: "dogs",
          },
        ],
        resourceOwner: "binding:request record",
      };
    },
  },
  {
    name: "stale-failure-keeps-new-request-pending",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const oldId = search(mediator, "cats");
      const currentId = search(mediator, "dogs");
      finish(binding, oldId, { error: "old timeout", status: "error" });
      const afterStale = view(mediator);
      finish(binding, currentId, { error: "new timeout", status: "error" });
      return {
        actual: [afterStale, view(mediator)],
        effects: binding.effects,
        events: [
          "search(cats)",
          "search(dogs)",
          "failure(stale cats)",
          "failure(current dogs)",
        ],
        expected: [
          { requestId: currentId, status: "pending", text: "dogs" },
          {
            error: "new timeout",
            requestId: currentId,
            status: "error",
            text: "dogs",
          },
        ],
        resourceOwner: "binding:request record",
      };
    },
  },
  {
    name: "same-text-reentry-has-a-new-identity",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const oldId = search(mediator, "cats");
      const currentId = search(mediator, "cats");
      assert.notEqual(oldId, currentId);
      finish(binding, oldId, { result: ["old cat"], status: "success" });
      const afterStale = view(mediator);
      finish(binding, currentId, { result: ["new cat"], status: "success" });
      return {
        actual: [afterStale, view(mediator)],
        effects: binding.effects,
        events: [
          "search(cats)",
          "search(cats again)",
          "success(stale)",
          "success(current)",
        ],
        expected: [
          { requestId: currentId, status: "pending", text: "cats" },
          {
            requestId: currentId,
            result: ["new cat"],
            status: "success",
            text: "cats",
          },
        ],
        resourceOwner: "binding:request record",
      };
    },
  },
  {
    name: "cancellation-is-best-effort-not-rollback",
    run() {
      const binding = createBinding();
      const mediator = createMediator(binding);
      const oldId = search(mediator, "cats");
      const currentId = search(mediator, "dogs");
      const oldRequest = binding.requests.get(oldId);
      return {
        actual: [view(mediator)],
        cancellation: {
          oldRequestCancelRequested: oldRequest.cancelRequested,
          serverRollback: false,
        },
        effects: binding.effects,
        events: ["search(cats)", "search(dogs): cancel old best-effort"],
        expected: [{ requestId: currentId, status: "pending", text: "dogs" }],
        resourceOwner: "binding:request record",
      };
    },
  },
];

for (const { name, run } of cases) {
  const record = run();
  assert.deepEqual(record.actual, record.expected);
  if (record.cancellation) {
    assert.deepEqual(record.cancellation, {
      oldRequestCancelRequested: true,
      serverRollback: false,
    });
  }
  console.log(JSON.stringify({ name, ...record, result: "passed" }));
}

assert.deepEqual(tooltip(true), { isOpen: true });
assert.deepEqual(tooltip(false), { isOpen: false });
console.log(JSON.stringify({ name: "tooltip-is-local", result: "passed" }));
