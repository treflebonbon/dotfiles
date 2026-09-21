import assert from "node:assert/strict";

// Model / use case: this is the only owner of the business cancellation rule.
const cancelOrder = ({ orderId, readCurrentStatus }) => {
  if (readCurrentStatus(orderId) === "shipped") {
    return { _tag: "BusinessError", code: "ORDER_ALREADY_SHIPPED", orderId };
  }
  return { _tag: "Success", orderId };
};

// Existing UI binding simulation: owns operation IDs, pending state, and result adoption.
const createBinding = () => {
  let nextAttempt = 1;
  const activeAttemptByOrder = new Map();
  const resultByOrder = new Map();

  return {
    begin(orderId) {
      const attempt = `${orderId}:${nextAttempt}`;
      nextAttempt += 1;
      activeAttemptByOrder.set(orderId, attempt);
      return attempt;
    },
    complete(orderId, attempt, result) {
      if (activeAttemptByOrder.get(orderId) !== attempt) {
        return false;
      }
      activeAttemptByOrder.delete(orderId);
      resultByOrder.set(orderId, result);
      return true;
    },
    isPending(orderId) {
      return activeAttemptByOrder.has(orderId);
    },
    snapshot(orderId) {
      return {
        pending: activeAttemptByOrder.has(orderId),
        result: resultByOrder.get(orderId),
      };
    },
  };
};

// Mediator: it judges only the UI-flow duplicate rule; it has no status rule or state.
const createMediator = (binding) => ({
  requestCancel(orderId) {
    if (binding.isPending(orderId)) {
      return { _tag: "Ignored", reason: "pending" };
    }
    return { _tag: "Accepted", attempt: binding.begin(orderId) };
  },
});

// View: cached display and tooltip are local presentation concerns. It only sends events.
const createOrderRow = (cachedOrder, sendCancel) => {
  let tooltipOpen = false;
  return {
    label: `${cachedOrder.label} (${cachedOrder.cachedStatus})`,
    requestCancel: () => sendCancel(cachedOrder.id),
    toggleTooltip: () => (tooltipOpen = !tooltipOpen),
    tooltipOpen: () => tooltipOpen,
  };
};

const setup = (status) => {
  const currentStatus = new Map([["order-1", status]]);
  const binding = createBinding();
  const mediator = createMediator(binding);
  const executeAtExistingEffectBoundary = (attempt) =>
    binding.complete(
      "order-1",
      attempt,
      cancelOrder({
        orderId: "order-1",
        readCurrentStatus: (orderId) => currentStatus.get(orderId),
      })
    );
  return { binding, executeAtExistingEffectBoundary, mediator };
};

const normalSuccess = () => {
  const { binding, mediator, executeAtExistingEffectBoundary } = setup("open");
  const request = mediator.requestCancel("order-1");
  assert.equal(request._tag, "Accepted");
  assert.equal(executeAtExistingEffectBoundary(request.attempt), true);
  assert.deepEqual(binding.snapshot("order-1"), {
    pending: false,
    result: { _tag: "Success", orderId: "order-1" },
  });
};

const shippedAfterCachedDisplayIsRejected = () => {
  const { binding, mediator, executeAtExistingEffectBoundary } =
    setup("shipped");
  const row = createOrderRow(
    { cachedStatus: "open", id: "order-1", label: "Order 1" },
    (orderId) => mediator.requestCancel(orderId)
  );
  const request = row.requestCancel();
  assert.equal(request._tag, "Accepted");
  assert.equal(executeAtExistingEffectBoundary(request.attempt), true);
  assert.deepEqual(binding.snapshot("order-1"), {
    pending: false,
    result: {
      _tag: "BusinessError",
      code: "ORDER_ALREADY_SHIPPED",
      orderId: "order-1",
    },
  });
};

const repeatedRequestsAndStaleResults = () => {
  const { binding, mediator } = setup("open");
  const first = mediator.requestCancel("order-1");
  assert.equal(mediator.requestCancel("order-1")._tag, "Ignored");
  assert.equal(
    binding.complete("order-1", first.attempt, { _tag: "Success" }),
    true
  );

  const second = mediator.requestCancel("order-1");
  assert.equal(second._tag, "Accepted");
  assert.notEqual(second.attempt, first.attempt);
  assert.equal(
    binding.complete("order-1", first.attempt, { _tag: "Success" }),
    false
  );
  assert.equal(
    binding.complete("order-1", first.attempt, { _tag: "BusinessError" }),
    false
  );
  assert.deepEqual(binding.snapshot("order-1"), {
    pending: true,
    result: { _tag: "Success" },
  });
  assert.equal(
    binding.complete("order-1", second.attempt, { _tag: "Success" }),
    true
  );
};

const tooltipIsLocal = () => {
  const { binding, mediator } = setup("open");
  const row = createOrderRow(
    { cachedStatus: "open", id: "order-1", label: "Order 1" },
    (orderId) => mediator.requestCancel(orderId)
  );
  const before = binding.snapshot("order-1");
  assert.equal(row.toggleTooltip(), true);
  assert.equal(row.tooltipOpen(), true);
  assert.deepEqual(binding.snapshot("order-1"), before);
};

const executedCases = [
  ["normal cancellation success", normalSuccess],
  [
    "shipped race returns typed business error",
    shippedAfterCachedDisplayIsRejected,
  ],
  [
    "duplicate request and stale result exclusion",
    repeatedRequestsAndStaleResults,
  ],
  ["local tooltip independence", tooltipIsLocal],
];

for (const [, run] of executedCases) {
  run();
}
console.log(
  `passed ${executedCases.length} assertions: ${executedCases.map(([name]) => name).join("; ")}`
);
