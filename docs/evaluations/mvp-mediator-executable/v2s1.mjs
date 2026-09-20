import assert from "node:assert/strict";

// 既存 Query binding の実行・要求ごとの pending/result を表す最小の模擬。
const createExistingSearchBinding = () => {
  let nextRequestId = 0;
  const binding = { requests: new Map() };
  binding.search = (text) => {
    nextRequestId += 1;
    const request = { id: nextRequestId, text };
    binding.requests.set(request.id, {
      error: null,
      pending: true,
      result: null,
    });
    return request;
  };
  binding.settle = (id, outcome) => {
    const state = binding.requests.get(id);
    assert.ok(state, `unknown request ${id}`);
    state.pending = false;
    Object.assign(state, outcome);
    return { id, ...state };
  };
  binding.succeed = (request, result) =>
    binding.settle(request.id, { error: null, result });
  binding.fail = (request, error) =>
    binding.settle(request.id, { error, result: null });
  return binding;
};

const view = (pending, results = null, error = null) => ({
  error,
  pending,
  results,
});

// UI の結果採用を一意に裁定する所有者。実行・取消は binding に残す。
const createSearchResultAcceptanceMediator = (binding) => {
  const mediator = { latestRequestId: 0, view: view(false) };
  mediator.search = (text) => {
    const request = binding.search(text);
    mediator.latestRequestId = request.id;
    mediator.view = view(true);
    return request;
  };
  mediator.accept = (completion) => {
    if (completion.id !== mediator.latestRequestId) {
      return false;
    }
    mediator.view = view(false, completion.result, completion.error);
    return true;
  };
  return mediator;
};

const createHelpTooltip = () => {
  const tooltip = { open: false };
  tooltip.toggle = () => {
    tooltip.open = !tooltip.open;
  };
  return tooltip;
};

const checkNormalPathFirst = () => {
  const binding = createExistingSearchBinding();
  const mediator = createSearchResultAcceptanceMediator(binding);
  const request = mediator.search("cats");

  assert.equal(mediator.accept(binding.succeed(request, ["cat"])), true);
  assert.deepEqual(mediator.view, view(false, ["cat"]));
};

const checkRepeatedTextUsesIdentity = () => {
  const binding = createExistingSearchBinding();
  const mediator = createSearchResultAcceptanceMediator(binding);
  const first = mediator.search("same");
  const latest = mediator.search("same");

  assert.notEqual(first.id, latest.id);
  assert.equal(mediator.accept(binding.succeed(first, ["stale"])), false);
  assert.deepEqual(mediator.view, view(true));
  assert.equal(mediator.accept(binding.fail(latest, "current failure")), true);
  assert.deepEqual(mediator.view, view(false, null, "current failure"));
};

const checkStaleFailureAndCurrentSuccess = () => {
  const binding = createExistingSearchBinding();
  const mediator = createSearchResultAcceptanceMediator(binding);
  const first = mediator.search("old");
  const latest = mediator.search("new");

  assert.equal(mediator.accept(binding.fail(first, "stale failure")), false);
  assert.deepEqual(mediator.view, view(true));
  assert.equal(mediator.accept(binding.succeed(latest, ["new result"])), true);
  assert.deepEqual(mediator.view, view(false, ["new result"]));
};

const checkTooltipIsLocal = () => {
  const binding = createExistingSearchBinding();
  const mediator = createSearchResultAcceptanceMediator(binding);
  const tooltip = createHelpTooltip();
  const request = mediator.search("cats");
  const before = structuredClone(mediator.view);

  tooltip.toggle();
  assert.equal(tooltip.open, true);
  assert.deepEqual(mediator.view, before);
  assert.equal(mediator.accept(binding.succeed(request, ["cat"])), true);
};

const checks = [
  ["通常経路", checkNormalPathFirst],
  ["同一文言の再要求と古い成功", checkRepeatedTextUsesIdentity],
  ["古い失敗と現在成功", checkStaleFailureAndCurrentSuccess],
  ["ツールチップの局所性", checkTooltipIsLocal],
];

for (const [name, check] of checks) {
  check();
  console.log(`OK ${name}`);
}
