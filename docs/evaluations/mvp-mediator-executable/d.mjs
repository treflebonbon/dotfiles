import assert from "node:assert/strict";

const createExistingFormBindingMock = (values) => ({
  draftRevision: 0,
  edit(name, value) {
    this.values[name] = value;
    this.draftRevision += 1;
  },
  values: { ...values },
});

const createExistingSaveUseCaseMock = () => ({
  execute(command) {
    // Production validates business rules here; this mock only records its boundary.
    this.received.push(structuredClone(command));
  },
  received: [],
});

const createExistingQueryExecutionMock = (useCase) => ({
  execute(command) {
    this.started.push(structuredClone(command));
    useCase.execute(command);
  },
  started: [],
});

// The sole UI save-policy owner: it serializes saves and adopts only its active result.
class SaveMediator {
  #active;
  #nextOperationId = 0;
  #savedRevision;

  constructor(form, query) {
    this.form = form;
    this.query = query;
    this.#savedRevision = form.draftRevision;
  }

  requestSave() {
    if (this.#active) {
      return false;
    }

    this.#nextOperationId += 1;
    const command = {
      operationId: this.#nextOperationId,
      revision: this.form.draftRevision,
      values: structuredClone(this.form.values),
    };
    this.#active = command;
    this.query.execute(command);
    return true;
  }

  succeeded(operationId) {
    if (this.#active?.operationId !== operationId) {
      return false;
    }
    this.#savedRevision = this.#active.revision;
    this.#active = undefined;
    return true;
  }

  failed(operationId) {
    if (this.#active?.operationId !== operationId) {
      return false;
    }
    this.#active = undefined;
    return true;
  }

  state() {
    return {
      activeOperationId: this.#active?.operationId,
      isDirty: this.form.draftRevision !== this.#savedRevision,
      isSaving: Boolean(this.#active),
      savedRevision: this.#savedRevision,
    };
  }
}

const run = () => {
  const form = createExistingFormBindingMock({ title: "初期値" });
  const useCase = createExistingSaveUseCaseMock();
  const query = createExistingQueryExecutionMock(useCase);
  const mediator = new SaveMediator(form, query);

  // Normal path: initial draft succeeds without interruption.
  assert.equal(mediator.requestSave(), true);
  const [initial] = query.started;
  assert.deepEqual(initial, {
    operationId: 1,
    revision: 0,
    values: { title: "初期値" },
  });
  assert.equal(mediator.succeeded(initial.operationId), true);
  assert.deepEqual(mediator.state(), {
    activeOperationId: undefined,
    isDirty: false,
    isSaving: false,
    savedRevision: 0,
  });

  // Editing remains possible while the captured command is in flight.
  form.edit("title", "下書き A");
  assert.equal(mediator.requestSave(), true);
  const [, editedSnapshot] = query.started;
  form.edit("title", "下書き B");
  assert.deepEqual(editedSnapshot, {
    operationId: 2,
    revision: 1,
    values: { title: "下書き A" },
  });
  assert.equal(mediator.requestSave(), false);
  assert.equal(query.started.length, 2);
  assert.equal(mediator.succeeded(editedSnapshot.operationId), true);
  assert.deepEqual(mediator.state(), {
    activeOperationId: undefined,
    isDirty: true,
    isSaving: false,
    savedRevision: 1,
  });

  // A new save ignores stale duplicate notifications and failure keeps savedRevision.
  assert.equal(mediator.requestSave(), true);
  const failingSnapshot = query.started.at(-1);
  assert.equal(mediator.succeeded(editedSnapshot.operationId), false);
  assert.equal(mediator.failed(editedSnapshot.operationId), false);
  assert.deepEqual(mediator.state(), {
    activeOperationId: failingSnapshot.operationId,
    isDirty: true,
    isSaving: true,
    savedRevision: 1,
  });
  assert.equal(mediator.failed(failingSnapshot.operationId), true);
  assert.deepEqual(mediator.state(), {
    activeOperationId: undefined,
    isDirty: true,
    isSaving: false,
    savedRevision: 1,
  });
  assert.deepEqual(useCase.received, query.started);

  console.log("d.mjs: 4 scenarios passed");
};

run();
