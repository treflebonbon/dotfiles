import assert from "node:assert/strict";

// 既存 Query binding の pending/result を小さく模擬する。
const createSearchBinding = () => {
  const requests = new Map();
  return {
    begin: (id, text) => {
      requests.set(id, {
        error: undefined,
        pending: true,
        result: undefined,
        text,
      });
    },
    fail: (id, error) => {
      requests.set(id, { ...requests.get(id), error, pending: false });
    },
    read: (id) => requests.get(id),
    succeed: (id, result) => {
      requests.set(id, { ...requests.get(id), pending: false, result });
    },
  };
};

// ResultAcceptanceMediator は表示に採用する request identity だけを所有する。
class ResultAcceptanceMediator {
  nextId = 0;
  latestId = undefined;

  constructor(binding) {
    this.binding = binding;
  }

  search(text) {
    this.nextId += 1;
    const id = this.nextId;
    this.latestId = id;
    this.binding.begin(id, text);
    return id;
  }

  failed(id, error) {
    this.binding.fail(id, error);
  }

  succeeded(id, result) {
    this.binding.succeed(id, result);
  }

  displayed() {
    return this.binding.read(this.latestId);
  }
}

const demo = () => {
  const binding = createSearchBinding();
  const mediator = new ResultAcceptanceMediator(binding);
  let tooltipOpen = false;

  // 初期状態から完了まで、割込みのない通常経路を最初に実行する。
  const first = mediator.search("cats");
  assert.deepEqual(mediator.displayed(), {
    error: undefined,
    pending: true,
    result: undefined,
    text: "cats",
  });
  mediator.succeeded(first, ["cat"]);
  assert.deepEqual(mediator.displayed(), {
    error: undefined,
    pending: false,
    result: ["cat"],
    text: "cats",
  });

  // 同じ text の再検索でも ID は別であり、古い成功は表示を変えない。
  const staleSuccess = mediator.search("cats");
  const current = mediator.search("cats");
  mediator.succeeded(staleSuccess, ["old cat"]);
  assert.deepEqual(mediator.displayed(), {
    error: undefined,
    pending: true,
    result: undefined,
    text: "cats",
  });

  // 古い失敗も表示を変えず、現在の完了だけが採用される。
  mediator.failed(staleSuccess, "old failure");
  assert.deepEqual(mediator.displayed(), {
    error: undefined,
    pending: true,
    result: undefined,
    text: "cats",
  });
  mediator.succeeded(current, ["new cat"]);
  assert.deepEqual(mediator.displayed(), {
    error: undefined,
    pending: false,
    result: ["new cat"],
    text: "cats",
  });

  tooltipOpen = !tooltipOpen;
  assert.equal(tooltipOpen, true);
  assert.deepEqual(mediator.displayed().result, ["new cat"]);
  console.log("c1s self-check: passed");
};

demo();
