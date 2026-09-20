import assert from "node:assert/strict";

class PermissionDeniedError extends Error {
  constructor(message) {
    super(message);
    this.name = "PermissionDeniedError";
  }
}

const createTableSelectionBinding = () => {
  let ids = new Set();
  return {
    set(nextIds) {
      ids = new Set(nextIds);
    },
    snapshot() {
      return Object.freeze([...ids].toSorted());
    },
  };
};

const createQueryBinding = () => {
  let rows = [];
  return {
    refresh(nextRows) {
      rows = nextRows;
    },
    get rows() {
      return rows;
    },
  };
};

const createArchiveUseCase = (canArchive) => {
  const executed = [];
  return {
    archive(ids) {
      if (!canArchive(ids)) {
        throw new PermissionDeniedError("archive denied at execution time");
      }
      executed.push(ids);
      return { archivedIds: ids };
    },
    executed,
  };
};

const createDocumentListMediator = ({ executionBoundary, tableSelection }) => ({
  onArchiveClick() {
    return executionBoundary.runArchive(tableSelection.snapshot());
  },
});

const formatDocumentTitle = (row) => row.title.trim();

const tableSelection = createTableSelectionBinding();
const query = createQueryBinding();
const archiveUseCase = createArchiveUseCase(() => true);
const mediator = createDocumentListMediator({
  executionBoundary: { runArchive: (ids) => archiveUseCase.archive(ids) },
  tableSelection,
});

tableSelection.set(["b", "a"]);
query.refresh([
  { id: "a", title: " first " },
  { id: "b", title: "second" },
]);
assert.deepEqual(tableSelection.snapshot(), ["a", "b"]);
assert.deepEqual(archiveUseCase.executed, []);
assert.equal(formatDocumentTitle(query.rows[0]), "first");

const accepted = mediator.onArchiveClick();
tableSelection.set(["c"]);
assert.deepEqual(accepted.archivedIds, ["a", "b"]);
assert.deepEqual(archiveUseCase.executed, [["a", "b"]]);

const deniedUseCase = createArchiveUseCase(() => false);
assert.throws(
  () => deniedUseCase.archive(Object.freeze(["c"])),
  PermissionDeniedError
);

console.log(
  "t.mjs: refresh, archive snapshot, later selection, and use-case permission checks passed"
);
