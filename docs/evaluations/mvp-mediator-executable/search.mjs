import assert from "node:assert/strict";

/** Result-acceptance owner for a search screen. Query continues to execute requests. */
class SearchMediator {
  #nextRequestId = 0;

  constructor({ pending = false, results = [], error = null } = {}) {
    this.state = { error, latestRequestId: null, pending, results };
  }

  beginSearch(text) {
    this.#nextRequestId += 1;
    const requestId = this.#nextRequestId;
    this.state = {
      ...this.state,
      error: null,
      latestRequestId: requestId,
      pending: true,
    };
    return { requestId, text };
  }

  completeSuccess(requestId, results) {
    if (requestId !== this.state.latestRequestId) {
      return false;
    }
    this.state = { ...this.state, error: null, pending: false, results };
    return true;
  }

  completeFailure(requestId, error) {
    if (requestId !== this.state.latestRequestId) {
      return false;
    }
    this.state = { ...this.state, error, pending: false };
    return true;
  }
}

const snapshot = (mediator) => structuredClone(mediator.state);

const demo = () => {
  const mediator = new SearchMediator({ results: ["cached"] });
  const first = mediator.beginSearch("cat");
  const newestSameText = mediator.beginSearch("cat");
  const whileNewestPending = snapshot(mediator);

  assert.equal(
    mediator.completeSuccess(first.requestId, ["stale success"]),
    false
  );
  assert.deepEqual(mediator.state, whileNewestPending);
  assert.equal(
    mediator.completeFailure(first.requestId, "stale failure"),
    false
  );
  assert.deepEqual(mediator.state, whileNewestPending);
  assert.equal(
    mediator.completeFailure(newestSameText.requestId, "current failure"),
    true
  );
  assert.deepEqual(mediator.state, {
    error: "current failure",
    latestRequestId: newestSameText.requestId,
    pending: false,
    results: ["cached"],
  });

  const newest = mediator.beginSearch("dog");
  const newerPending = snapshot(mediator);
  assert.equal(
    mediator.completeFailure(newestSameText.requestId, "late failure"),
    false
  );
  assert.deepEqual(mediator.state, newerPending);
  assert.equal(mediator.completeSuccess(newest.requestId, ["dog"]), true);
  assert.deepEqual(mediator.state, {
    error: null,
    latestRequestId: newest.requestId,
    pending: false,
    results: ["dog"],
  });

  console.log("search mediator self-check: passed");
};

demo();
