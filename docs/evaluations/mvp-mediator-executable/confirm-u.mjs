import assert from "node:assert/strict";

// Existing binding / Effect execution-layer doubles; this is not an Effect runtime.
const createFeedBinding = () => ({
  entries: new Map(),
  failure(sessionId, failure) {
    const previous = this.entries.get(sessionId) ?? {
      failure: null,
      value: null,
    };
    this.entries.set(sessionId, { ...previous, failure });
  },
  read(sessionId) {
    return this.entries.get(sessionId) ?? { failure: null, value: null };
  },
  value(sessionId, value) {
    this.entries.set(sessionId, { failure: null, value });
  },
});

const createEffectScopeExecutor = () => ({
  completeUnsubscribe(sessionId) {
    this.subscriptions.delete(sessionId);
  },
  requestUnsubscribe(sessionId) {
    const scope = this.subscriptions.get(sessionId);
    if (!scope || scope.phase === "closing") {
      return;
    }
    scope.phase = "closing";
    this.unsubscribeRequests.push(sessionId);
  },
  subscribe(sessionId, symbol) {
    this.subscriptions.set(sessionId, { phase: "open", symbol });
  },
  subscriptions: new Map(),
  unsubscribeRequests: [],
});

class FeedMediator {
  nextSessionId = 1;
  activeSessionId = null;
  unsubscribed = new Set();
  // Passive View local state; it never participates in feed arbitration.
  helpOpen = false;

  constructor(
    binding = createFeedBinding(),
    executor = createEffectScopeExecutor()
  ) {
    this.binding = binding;
    this.executor = executor;
  }

  mount(symbol) {
    const sessionId = `session-${this.nextSessionId}`;
    this.nextSessionId += 1;
    this.activeSessionId = sessionId;
    this.executor.subscribe(sessionId, symbol);
    return sessionId;
  }

  unmount(sessionId) {
    if (
      this.activeSessionId !== sessionId ||
      this.unsubscribed.has(sessionId)
    ) {
      return;
    }
    this.activeSessionId = null;
    this.unsubscribed.add(sessionId);
    this.executor.requestUnsubscribe(sessionId);
  }

  receivedValue(sessionId, value) {
    this.binding.value(sessionId, value);
  }

  receivedFailure(sessionId, failure) {
    this.binding.failure(sessionId, failure);
  }

  unsubscribeCompleted(sessionId) {
    this.executor.completeUnsubscribe(sessionId);
  }

  view() {
    if (this.activeSessionId === null) {
      return { failure: null, sessionId: null, value: null };
    }
    return {
      sessionId: this.activeSessionId,
      ...this.binding.read(this.activeSessionId),
    };
  }
}

const normalMountValueUnmountCompletion = () => {
  const mediator = new FeedMediator();
  const session = mediator.mount("7203");
  mediator.receivedValue(session, 100);
  assert.deepEqual(mediator.view(), {
    failure: null,
    sessionId: session,
    value: 100,
  });
  mediator.unmount(session);
  assert.deepEqual(mediator.executor.unsubscribeRequests, [session]);
  assert.deepEqual(mediator.view(), {
    failure: null,
    sessionId: null,
    value: null,
  });
  mediator.unsubscribeCompleted(session);
  assert.equal(mediator.executor.subscriptions.has(session), false);
};

const remountIgnoresOldResultsAndKeepsNewScope = () => {
  const mediator = new FeedMediator();
  const oldSession = mediator.mount("7203");
  mediator.receivedValue(oldSession, 100);
  mediator.unmount(oldSession);
  mediator.unmount(oldSession);
  assert.deepEqual(mediator.executor.unsubscribeRequests, [oldSession]);

  const newSession = mediator.mount("7203");
  assert.notEqual(newSession, oldSession);
  mediator.receivedValue(newSession, 200);
  mediator.receivedValue(oldSession, 99);
  mediator.receivedFailure(oldSession, "old feed failed");
  assert.deepEqual(mediator.view(), {
    failure: null,
    sessionId: newSession,
    value: 200,
  });

  mediator.unsubscribeCompleted(oldSession);
  assert.equal(mediator.executor.subscriptions.has(newSession), true);
  assert.deepEqual(mediator.view(), {
    failure: null,
    sessionId: newSession,
    value: 200,
  });
};

const helpIsLocal = () => {
  const mediator = new FeedMediator();
  const session = mediator.mount("7203");
  mediator.receivedValue(session, 100);
  mediator.helpOpen = true;
  assert.equal(mediator.helpOpen, true);
  assert.deepEqual(mediator.view(), {
    failure: null,
    sessionId: session,
    value: 100,
  });
};

const checks = [
  [
    "normal mount -> value -> unmount -> completion",
    normalMountValueUnmountCompletion,
  ],
  [
    "remount ignores old results and delayed completion",
    remountIgnoresOldResultsAndKeepsNewScope,
  ],
  ["help is local", helpIsLocal],
];

for (const [name, check] of checks) {
  check();
  console.log(`ok: ${name}`);
}
