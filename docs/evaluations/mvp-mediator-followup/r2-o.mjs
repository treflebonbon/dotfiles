import assert from "node:assert/strict";

const shipped = "shipped";
const cancellable = "cancellable";

/** Model / use-case mock: it reads authoritative status at execution time. */
const cancelOrder = ({ orderId, readLatestStatus }) => {
  if (readLatestStatus(orderId) === shipped) {
    return { error: { _tag: "OrderAlreadyShipped", orderId }, ok: false };
  }
  return { ok: true, value: { orderId, status: "cancelled" } };
};

const createExistingCancelBinding = () => {
  // Existing binding state: shared pending/result state, not Mediator-owned state.
  const pendingByOrder = new Map();
  const resultByOrder = new Map();
  let nextAttempt = 0;

  return {
    complete: ({ attemptId, outcome }) => {
      const [orderId] = attemptId.split(":");
      if (pendingByOrder.get(orderId) !== attemptId) {
        return { accepted: false };
      }
      pendingByOrder.delete(orderId);
      resultByOrder.set(orderId, outcome);
      return { accepted: true };
    },
    isPending: (orderId) => pendingByOrder.has(orderId),
    release: (attemptId) => {
      const [orderId] = attemptId.split(":");
      if (pendingByOrder.get(orderId) === attemptId) {
        pendingByOrder.delete(orderId);
      }
    },
    result: (orderId) => resultByOrder.get(orderId),
    start: (orderId) => {
      nextAttempt += 1;
      const attemptId = `${orderId}:${nextAttempt}`;
      pendingByOrder.set(orderId, attemptId);
      return attemptId;
    },
  };
};

const createCancelMediator = (binding) => ({
  requestCancel: (orderId) => {
    if (binding.isPending(orderId)) {
      return { accepted: false, reason: "pending" };
    }
    return { accepted: true, attemptId: binding.start(orderId) };
  },
});

const createScreen = () => {
  const binding = createExistingCancelBinding();
  return {
    binding,
    mediator: createCancelMediator(binding),
    tooltipOpen: false,
  };
};

const cases = [
  [
    "通常のキャンセル成功",
    () => {
      const { binding, mediator } = createScreen();
      const attempt = mediator.requestCancel("normal");
      const outcome = cancelOrder({
        orderId: "normal",
        readLatestStatus: () => cancellable,
      });

      assert.deepEqual(outcome, {
        ok: true,
        value: { orderId: "normal", status: "cancelled" },
      });
      assert.deepEqual(
        binding.complete({ attemptId: attempt.attemptId, outcome }),
        { accepted: true }
      );
      assert.equal(binding.isPending("normal"), false);
      assert.deepEqual(binding.result("normal"), outcome);
    },
  ],
  [
    "発送競合はユースケースが typed business error で拒否",
    () => {
      const cachedStatus = cancellable;
      const { binding, mediator } = createScreen();
      const attempt = mediator.requestCancel("shipped-after-render");
      const outcome = cancelOrder({
        orderId: "shipped-after-render",
        readLatestStatus: () => shipped,
      });

      assert.equal(cachedStatus, cancellable);
      assert.deepEqual(outcome, {
        error: { _tag: "OrderAlreadyShipped", orderId: "shipped-after-render" },
        ok: false,
      });
      assert.deepEqual(
        binding.complete({ attemptId: attempt.attemptId, outcome }),
        { accepted: true }
      );
    },
  ],
  [
    "pending 中の重複送信を Mediator が拒否",
    () => {
      const { binding, mediator } = createScreen();
      const first = mediator.requestCancel("duplicate");

      assert.equal(first.accepted, true);
      assert.deepEqual(mediator.requestCancel("duplicate"), {
        accepted: false,
        reason: "pending",
      });
      assert.equal(binding.isPending("duplicate"), true);
    },
  ],
  [
    "旧成功は再試行中の新しい試行を完了させない",
    () => {
      const { binding, mediator } = createScreen();
      const oldAttempt = mediator.requestCancel("retry-success");
      binding.release(oldAttempt.attemptId);
      const currentAttempt = mediator.requestCancel("retry-success");

      assert.notEqual(oldAttempt.attemptId, currentAttempt.attemptId);
      assert.deepEqual(
        binding.complete({
          attemptId: oldAttempt.attemptId,
          outcome: { ok: true, value: "old" },
        }),
        { accepted: false }
      );
      assert.equal(binding.isPending("retry-success"), true);
      assert.deepEqual(
        binding.complete({
          attemptId: currentAttempt.attemptId,
          outcome: { ok: true, value: "current" },
        }),
        { accepted: true }
      );
    },
  ],
  [
    "旧失敗は再試行中の新しい試行を完了させない",
    () => {
      const { binding, mediator } = createScreen();
      const oldAttempt = mediator.requestCancel("retry-failure");
      binding.release(oldAttempt.attemptId);
      const currentAttempt = mediator.requestCancel("retry-failure");

      assert.deepEqual(
        binding.complete({
          attemptId: oldAttempt.attemptId,
          outcome: { error: "old", ok: false },
        }),
        { accepted: false }
      );
      assert.equal(binding.isPending("retry-failure"), true);
      assert.deepEqual(
        binding.complete({
          attemptId: currentAttempt.attemptId,
          outcome: { error: "current", ok: false },
        }),
        { accepted: true }
      );
    },
  ],
  [
    "tooltip は局所表示であり操作裁定を変えない",
    () => {
      const screen = createScreen();
      screen.tooltipOpen = true;

      assert.equal(screen.tooltipOpen, true);
      assert.equal(screen.binding.isPending("unrelated-order"), false);
      assert.equal(
        screen.mediator.requestCancel("unrelated-order").accepted,
        true
      );
    },
  ],
];

for (const [name, check] of cases) {
  check();
  console.log(`ok: ${name}`);
}
