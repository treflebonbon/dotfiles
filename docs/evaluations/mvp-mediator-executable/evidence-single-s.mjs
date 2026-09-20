import assert from "node:assert/strict";

const createSearchBinding = () => {
  let nextId = 1;
  const requests = new Map();

  return {
    fail(id, error) {
      requests.set(id, { ...requests.get(id), error, status: "failure" });
    },
    start(text) {
      const id = nextId;
      nextId += 1;
      requests.set(id, { id, status: "pending", text });
      return id;
    },
    state(id) {
      return requests.get(id);
    },
    succeed(id, result) {
      requests.set(id, { ...requests.get(id), result, status: "success" });
    },
  };
};

class SearchResultMediator {
  #latestRequestId = null;

  constructor(binding) {
    this.binding = binding;
  }

  search(text) {
    this.#latestRequestId = this.binding.start(text);
    return this.#latestRequestId;
  }

  success(id, result) {
    this.binding.succeed(id, result);
  }

  failure(id, error) {
    this.binding.fail(id, error);
  }

  displayed() {
    return this.binding.state(this.#latestRequestId);
  }
}

const currentSuccess = () => {
  const mediator = new SearchResultMediator(createSearchBinding());
  const request = mediator.search("alpha");
  assert.deepEqual(mediator.displayed(), {
    id: request,
    status: "pending",
    text: "alpha",
  });
  mediator.success(request, ["alpha result"]);
  assert.deepEqual(mediator.displayed(), {
    id: request,
    result: ["alpha result"],
    status: "success",
    text: "alpha",
  });
};

const currentFailure = () => {
  const mediator = new SearchResultMediator(createSearchBinding());
  const request = mediator.search("missing");
  mediator.failure(request, "not found");
  assert.deepEqual(mediator.displayed(), {
    error: "not found",
    id: request,
    status: "failure",
    text: "missing",
  });
};

const staleOutcomesAndRepeatedText = () => {
  const mediator = new SearchResultMediator(createSearchBinding());
  const first = mediator.search("same");
  const second = mediator.search("other");
  const current = mediator.search("same");

  mediator.success(first, ["stale success"]);
  assert.deepEqual(mediator.displayed(), {
    id: current,
    status: "pending",
    text: "same",
  });
  mediator.success(current, ["current result"]);
  mediator.failure(second, "stale failure");
  assert.deepEqual(mediator.displayed(), {
    id: current,
    result: ["current result"],
    status: "success",
    text: "same",
  });
};

for (const check of [
  currentSuccess,
  currentFailure,
  staleOutcomesAndRepeatedText,
]) {
  check();
  console.log(`ok ${check.name}`);
}
