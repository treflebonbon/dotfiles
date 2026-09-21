import assert from "node:assert/strict";

const success = (orderId) => ({ orderId, tag: "success" });
const shipped = (orderId) => ({
  code: "ORDER_ALREADY_SHIPPED",
  orderId,
  tag: "business-error",
});

// Model/use case: the status is read when cancellation executes, never from View cache.
const cancelOrder = (latestStatusByOrder, orderId) => {
  if (latestStatusByOrder.get(orderId) === "shipped") {
    return shipped(orderId);
  }
  latestStatusByOrder.set(orderId, "cancelled");
  return success(orderId);
};

// Existing UI binding simulation. It owns normal pending/result and operation IDs.
const createBinding = () => {
  let nextOperationId = 0;
  const pendingByOrder = new Map();
  const resultByOrder = new Map();

  return {
    complete(orderId, operationId, result) {
      if (pendingByOrder.get(orderId) !== operationId) {
        return { tag: "stale" };
      }
      pendingByOrder.delete(orderId);
      resultByOrder.set(orderId, result);
      return { tag: "accepted" };
    },
    pending(orderId) {
      return pendingByOrder.get(orderId);
    },
    result(orderId) {
      return resultByOrder.get(orderId);
    },
    start(orderId) {
      const pending = pendingByOrder.get(orderId);
      if (pending) {
        return { operationId: pending, tag: "duplicate" };
      }

      nextOperationId += 1;
      const operationId = nextOperationId;
      pendingByOrder.set(orderId, operationId);
      return { operationId, tag: "started" };
    },
    // The execution boundary reported cancellation/end. A late server response remains possible.
    stopTracking(orderId, operationId) {
      if (pendingByOrder.get(orderId) !== operationId) {
        return false;
      }
      pendingByOrder.delete(orderId);
      return true;
    },
  };
};

// Mediator: its sole operation rule is to delegate start/duplicate arbitration to the binding.
const createMediator = (binding) => ({
  requestCancel(orderId) {
    return binding.start(orderId);
  },
});

const createOrderView = (cachedStatus) => {
  let tooltipOpen = false;

  return {
    closeTooltip() {
      tooltipOpen = false;
    },
    label: cachedStatus.toUpperCase(),
    openTooltip() {
      tooltipOpen = true;
    },
    tooltipOpen() {
      return tooltipOpen;
    },
  };
};

const testNormalCancellation = () => {
  const latest = new Map([["normal", "open"]]);
  const binding = createBinding();
  const mediator = createMediator(binding);
  const attempt = mediator.requestCancel("normal");

  assert.deepEqual(attempt, { operationId: 1, tag: "started" });
  assert.equal(binding.pending("normal"), 1);
  assert.deepEqual(
    binding.complete(
      "normal",
      attempt.operationId,
      cancelOrder(latest, "normal")
    ),
    {
      tag: "accepted",
    }
  );
  assert.deepEqual(binding.result("normal"), success("normal"));
  assert.equal(binding.pending("normal"), undefined);
};

const testRuntimeBusinessRejection = () => {
  // View cache: display input only.
  const cachedStatus = "open";
  const latest = new Map([["raced", "shipped"]]);
  const binding = createBinding();
  const mediator = createMediator(binding);
  const attempt = mediator.requestCancel("raced");

  // The Mediator starts from the cache-blind binding; it does not duplicate shipping policy.
  assert.equal(cachedStatus, "open");
  assert.equal(attempt.tag, "started");
  const result = cancelOrder(latest, "raced");
  assert.deepEqual(result, shipped("raced"));
  assert.deepEqual(binding.complete("raced", attempt.operationId, result), {
    tag: "accepted",
  });
  assert.deepEqual(binding.result("raced"), shipped("raced"));
};

const testDuplicateAndStaleResults = () => {
  const binding = createBinding();
  const mediator = createMediator(binding);
  const first = mediator.requestCancel("same-order");

  assert.deepEqual(mediator.requestCancel("same-order"), {
    operationId: first.operationId,
    tag: "duplicate",
  });
  assert.equal(binding.pending("same-order"), first.operationId);

  assert.equal(binding.stopTracking("same-order", first.operationId), true);
  const second = mediator.requestCancel("same-order");
  assert.deepEqual(second, { operationId: 2, tag: "started" });
  assert.deepEqual(
    binding.complete("same-order", first.operationId, success("same-order")),
    {
      tag: "stale",
    }
  );
  assert.equal(binding.pending("same-order"), second.operationId);

  assert.equal(binding.stopTracking("same-order", second.operationId), true);
  const third = mediator.requestCancel("same-order");
  assert.deepEqual(third, { operationId: 3, tag: "started" });
  assert.deepEqual(
    binding.complete("same-order", second.operationId, shipped("same-order")),
    {
      tag: "stale",
    }
  );
  assert.equal(binding.pending("same-order"), third.operationId);
  assert.deepEqual(
    binding.complete("same-order", third.operationId, success("same-order")),
    {
      tag: "accepted",
    }
  );
};

const testLocalViewState = () => {
  const view = createOrderView("open");

  assert.equal(view.label, "OPEN");
  view.openTooltip();
  assert.equal(view.tooltipOpen(), true);
  view.closeTooltip();
  assert.equal(view.tooltipOpen(), false);
};

testNormalCancellation();
testRuntimeBusinessRejection();
testDuplicateAndStaleResults();
testLocalViewState();

console.log("holdout-o: 4 assertion groups passed");
