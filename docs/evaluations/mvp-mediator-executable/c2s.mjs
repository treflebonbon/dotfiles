import assert from "node:assert/strict";

// Existing Query binding: execution and each request's pending/result live here.
const createSearchBinding = () => {
  const states = new Map();
  return {
    settle: ({ id, status, value }) => states.set(id, { status, value }),
    start: (id, text) => states.set(id, { status: "pending", text }),
    state: (id) => states.get(id),
  };
};

// The one result-acceptance owner. It adds identity coordination, not a scheduler.
class SearchMediator {
  #nextId = 0;
  #latestId;

  constructor(binding) {
    this.binding = binding;
  }

  search(text) {
    this.#nextId += 1;
    const id = this.#nextId;
    this.#latestId = id;
    this.binding.start(id, text);
    return id;
  }

  outcome(event) {
    this.binding.settle(event);
    return event.id === this.#latestId;
  }

  view() {
    return this.binding.state(this.#latestId);
  }
}

const make = () => new SearchMediator(createSearchBinding());

const normalPath = () => {
  const mediator = make();
  const id = mediator.search("alpha");
  assert.deepEqual(mediator.view(), { status: "pending", text: "alpha" });
  assert.equal(
    mediator.outcome({ id, status: "success", value: ["alpha"] }),
    true
  );
  assert.deepEqual(mediator.view(), { status: "success", value: ["alpha"] });
};

const overlappingRequests = () => {
  const mediator = make();
  const stale = mediator.search("old");
  const current = mediator.search("new");

  assert.equal(
    mediator.outcome({ id: stale, status: "success", value: ["old"] }),
    false
  );
  assert.deepEqual(mediator.view(), { status: "pending", text: "new" });
  assert.equal(
    mediator.outcome({ id: current, status: "success", value: ["new"] }),
    true
  );
  assert.deepEqual(mediator.view(), { status: "success", value: ["new"] });
};

const repeatedTextAndLocalTooltip = () => {
  const mediator = make();
  const first = mediator.search("same");
  const current = mediator.search("same");
  // Passive View-local state.
  let tooltipOpen = false;

  tooltipOpen = !tooltipOpen;
  assert.equal(tooltipOpen, true);
  assert.equal(
    mediator.outcome({ id: first, status: "failure", value: "old error" }),
    false
  );
  assert.deepEqual(mediator.view(), { status: "pending", text: "same" });
  assert.equal(
    mediator.outcome({
      id: current,
      status: "failure",
      value: "current error",
    }),
    true
  );
  assert.deepEqual(mediator.view(), {
    status: "failure",
    value: "current error",
  });
};

normalPath();
overlappingRequests();
repeatedTextAndLocalTooltip();
console.log("c2s: all assertions passed");
