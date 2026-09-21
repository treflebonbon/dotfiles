import assert from "node:assert/strict";

class BusinessError extends Error {
  constructor(code) {
    super(code);
    this.name = "BusinessError";
    this.code = code;
  }
}

// Model / use case: this is the only owner of the business rule.
const createCancelOrderUseCase = (statuses) => ({
  execute(orderId) {
    if (statuses.get(orderId) === "shipped") {
      return { error: new BusinessError("ORDER_ALREADY_SHIPPED"), ok: false };
    }
    statuses.set(orderId, "cancelled");
    return { ok: true, value: { orderId, status: "cancelled" } };
  },
});

// Existing UI binding simulation: owns pending/result for each operation.
const createExistingCancelBinding = () => {
  let nextAttempt = 0;
  const pending = new Map();
  const results = new Map();
  const release = (orderId, attemptId) => {
    if (pending.get(orderId) === attemptId) {
      pending.delete(orderId);
    }
  };

  return {
    complete(orderId, attemptId, outcome) {
      release(orderId, attemptId);
      results.set(attemptId, outcome);
    },
    isPending(orderId) {
      return pending.has(orderId);
    },
    pending,
    release,
    results,
    start(orderId) {
      nextAttempt += 1;
      const attemptId = `${orderId}:${nextAttempt}`;
      pending.set(orderId, attemptId);
      return attemptId;
    },
  };
};

// Mediator: only arbitrates duplicate UI requests and result adoption.
const createCancelMediator = (binding) => {
  const currentAttempt = new Map();
  return {
    currentAttempt,
    receiveCompletion(orderId, attemptId, outcome) {
      binding.complete(orderId, attemptId, outcome);
      return currentAttempt.get(orderId) === attemptId
        ? { adopted: true, outcome }
        : { adopted: false, reason: "stale" };
    },
    request(orderId) {
      if (binding.isPending(orderId)) {
        return { accepted: false, reason: "pending" };
      }
      const attemptId = binding.start(orderId);
      currentAttempt.set(orderId, attemptId);
      return { accepted: true, attemptId };
    },
  };
};

// View: status formatting and tooltip state are local; it receives cancelable as a projection.
const viewState = ({ cachedStatus, cancelable, pending, tooltipOpen }) => ({
  cancelDisabled: !cancelable || pending,
  statusLabel: cachedStatus.toUpperCase(),
  tooltipOpen,
});

const tests = [];
const test = (name, run) => {
  run();
  tests.push(name);
};

test("通常経路: 未発送の注文をキャンセルする", () => {
  const statuses = new Map([["normal", "paid"]]);
  const binding = createExistingCancelBinding();
  const mediator = createCancelMediator(binding);
  const attempt = mediator.request("normal");
  const outcome = createCancelOrderUseCase(statuses).execute("normal");
  const completion = mediator.receiveCompletion(
    "normal",
    attempt.attemptId,
    outcome
  );

  assert.deepEqual(completion, { adopted: true, outcome });
  assert.equal(binding.isPending("normal"), false);
  assert.deepEqual(outcome, {
    ok: true,
    value: { orderId: "normal", status: "cancelled" },
  });
});

test("発送競合: cached表示後でもユースケースが実行時に拒否する", () => {
  const statuses = new Map([["race", "paid"]]);
  const binding = createExistingCancelBinding();
  const mediator = createCancelMediator(binding);
  const rendered = viewState({
    cachedStatus: "paid",
    cancelable: true,
    pending: false,
    tooltipOpen: true,
  });
  statuses.set("race", "shipped");

  const attempt = mediator.request("race");
  const outcome = createCancelOrderUseCase(statuses).execute("race");
  const completion = mediator.receiveCompletion(
    "race",
    attempt.attemptId,
    outcome
  );

  assert.equal(rendered.cancelDisabled, false);
  assert.equal(outcome.ok, false);
  assert.ok(outcome.error instanceof BusinessError);
  assert.equal(outcome.error.code, "ORDER_ALREADY_SHIPPED");
  assert.equal(completion.adopted, true);
});

test("pending中の重複要求はMediatorが拒否する", () => {
  const binding = createExistingCancelBinding();
  const mediator = createCancelMediator(binding);

  assert.equal(mediator.request("duplicate").accepted, true);
  assert.deepEqual(mediator.request("duplicate"), {
    accepted: false,
    reason: "pending",
  });
});

for (const oldOutcome of [
  { ok: true, value: { status: "cancelled" } },
  { error: new BusinessError("ORDER_ALREADY_SHIPPED"), ok: false },
]) {
  test(`旧${oldOutcome.ok ? "成功" : "失敗"}は新しい試行を完了させない`, () => {
    const binding = createExistingCancelBinding();
    const mediator = createCancelMediator(binding);
    const first = mediator.request("retry");
    // Existing execution layer has finished releasing A.
    binding.release("retry", first.attemptId);
    const second = mediator.request("retry");
    const completion = mediator.receiveCompletion(
      "retry",
      first.attemptId,
      oldOutcome
    );

    assert.notEqual(first.attemptId, second.attemptId);
    assert.deepEqual(completion, { adopted: false, reason: "stale" });
    assert.equal(binding.pending.get("retry"), second.attemptId);
    assert.equal(mediator.currentAttempt.get("retry"), second.attemptId);
  });
}

console.log(`OK: ${tests.join(" / ")}`);
