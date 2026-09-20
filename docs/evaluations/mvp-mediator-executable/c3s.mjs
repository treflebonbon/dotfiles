import assert from "node:assert/strict";

const provenance = {
  path: "/home/ubuntu/.codex/worktrees/90ae/dotfiles/docs/evaluations/mvp-mediator-executable/protocol.md#S",
  sha256: "18e1033cb8dcd626e8a4f2f393d17755fccb3f5033e255ffd6a9c8a741f77561",
  skill: {
    path: "/home/ubuntu/.codex/worktrees/90ae/dotfiles/local-skills/mvp-mediator-architecture/SKILL.md",
    sha256: "25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6",
  },
};

// Existing Query binding, represented only enough to expose per-request state.
const makeQueryBinding = () => {
  const requests = new Map();

  return {
    read(id) {
      const request = requests.get(id);
      assert.ok(request, `unknown request: ${id}`);
      return { ...request };
    },
    settle(id, outcome) {
      const request = requests.get(id);
      assert.ok(request, `unknown request: ${id}`);
      requests.set(id, { ...request, outcome, status: "settled" });
    },
    start(request) {
      requests.set(request.id, { ...request, status: "pending" });
    },
  };
};

// The one result-acceptance owner. Query keeps execution and per-request state.
const makeSearchResultMediator = (binding) => {
  let latestRequestId;

  return {
    accepts(id) {
      return id === latestRequestId;
    },
    request(request) {
      latestRequestId = request.id;
      binding.start(request);
    },
    searchView() {
      return binding.read(latestRequestId);
    },
    settle(id, outcome) {
      binding.settle(id, outcome);
      return id === latestRequestId;
    },
  };
};

// A Passive View-local state: it never calls the mediator.
const makeTooltipView = () => {
  let open = false;

  return {
    get open() {
      return open;
    },
    toggle() {
      open = !open;
    },
  };
};

const selfCheck = () => {
  const mediator = makeSearchResultMediator(makeQueryBinding());
  const tooltip = makeTooltipView();

  mediator.request({ id: "q1", text: "cat" });
  assert.equal(mediator.searchView().status, "pending");
  assert.equal(
    mediator.settle("q1", { kind: "success", value: ["catnip"] }),
    true
  );
  assert.deepEqual(mediator.searchView().outcome, {
    kind: "success",
    value: ["catnip"],
  });

  mediator.request({ id: "q2", text: "cat" });
  mediator.request({ id: "q3", text: "cat" });
  assert.equal(
    mediator.settle("q2", { kind: "success", value: ["old"] }),
    false
  );
  assert.deepEqual(mediator.searchView(), {
    id: "q3",
    status: "pending",
    text: "cat",
  });
  assert.equal(
    mediator.settle("q3", { kind: "success", value: ["new"] }),
    true
  );

  mediator.request({ id: "q4", text: "dog" });
  mediator.request({ id: "q5", text: "bird" });
  assert.equal(
    mediator.settle("q4", { kind: "failure", message: "late" }),
    false
  );
  assert.equal(mediator.searchView().status, "pending");
  assert.equal(
    mediator.settle("q5", { kind: "failure", message: "current" }),
    true
  );
  assert.deepEqual(mediator.searchView().outcome, {
    kind: "failure",
    message: "current",
  });

  const searchBeforeTooltip = mediator.searchView();
  tooltip.toggle();
  assert.equal(tooltip.open, true);
  assert.deepEqual(mediator.searchView(), searchBeforeTooltip);
};

selfCheck();
console.log(
  `c3s self-check: ok (${provenance.path}, ${provenance.sha256}; ${provenance.skill.path}, ${provenance.skill.sha256})`
);
