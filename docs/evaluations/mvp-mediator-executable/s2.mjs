import assert from "node:assert/strict";

// 既存の Query binding を最小限に模擬する。pending/result の所有者は binding のまま。
const createSearchBinding = () => ({
  cancel(requestId) {
    // 通信停止の依頼だけで、サーバー結果は巻き戻さない。
    this.cancellationRequests.push(requestId);
  },
  cancellationRequests: [],
  execute(request) {
    this.executed.push(request);
    this.state = { pending: true, result: undefined };
  },
  executed: [],
  publish(outcome) {
    this.state = outcome.ok
      ? { pending: false, result: { type: "success", value: outcome.value } }
      : { pending: false, result: { error: outcome.error, type: "failure" } };
  },
  state: { pending: false, result: undefined },
});

// この画面で結果を採用する唯一の所有者。text ではなく試行ごとの requestId を照合する。
class SearchMediator {
  #nextRequestId = 0;
  #latestRequestId = undefined;

  constructor(binding) {
    this.binding = binding;
  }

  search(text) {
    this.#nextRequestId += 1;
    const request = { id: this.#nextRequestId, text };
    const previousId = this.#latestRequestId;
    this.#latestRequestId = request.id;
    if (previousId !== undefined) {
      this.binding.cancel(previousId);
    }
    this.binding.execute(request);
    return request;
  }

  receive(requestId, outcome) {
    if (requestId !== this.#latestRequestId) {
      return false;
    }
    this.binding.publish(outcome);
    return true;
  }
}

const selfCheck = () => {
  const binding = createSearchBinding();
  const mediator = new SearchMediator(binding);
  const first = mediator.search("same text");
  const second = mediator.search("same text");

  assert.notEqual(first.id, second.id, "同じ text の再入力も別試行");
  assert.deepEqual(binding.state, { pending: true, result: undefined });
  assert.equal(
    mediator.receive(first.id, { ok: true, value: ["stale"] }),
    false
  );
  assert.deepEqual(binding.state, { pending: true, result: undefined });
  assert.equal(
    mediator.receive(first.id, { error: "stale failure", ok: false }),
    false
  );
  assert.deepEqual(binding.state, { pending: true, result: undefined });

  assert.equal(
    mediator.receive(second.id, { ok: true, value: ["current"] }),
    true
  );
  assert.deepEqual(binding.state, {
    pending: false,
    result: { type: "success", value: ["current"] },
  });

  const third = mediator.search("next");
  assert.equal(
    mediator.receive(third.id, { error: "current failure", ok: false }),
    true
  );
  assert.deepEqual(binding.state, {
    pending: false,
    result: { error: "current failure", type: "failure" },
  });
  assert.deepEqual(binding.cancellationRequests, [first.id, second.id]);
};

selfCheck();
console.log("s2 self-check: passed");
