import assert from "node:assert/strict";
import { test } from "node:test";

import {
  validateDocument,
  editItem,
  removeItem,
  reconcile,
  signature,
  feedback,
  artifacts,
} from "../src/model.mjs";

const node = (id, label, x) => ({
  data: { evidence: [], kind: "COMMAND", label, origin: "inference" },
  height: 90,
  id,
  position: { x, y: 80 },
  width: 180,
});

export const example = () => {
  const graph = {
    edges: [
      {
        data: { evidence: [], origin: "inference" },
        id: "request-accept",
        label: "有効な依頼",
        source: "request",
        target: "accept",
      },
    ],
    nodes: [node("request", "依頼する", 40), node("accept", "受諾する", 360)],
  };
  return {
    basedOn: null,
    changes: [],
    comments: [],
    glossary: [],
    models: {
      current: structuredClone(graph),
      proposed: structuredClone(graph),
    },
    repository: { name: "example/project", revision: "example-only" },
    retired: [],
    revision: "r1",
    scenarios: [],
    schemaVersion: 1,
    scope: "実装未確認の説明用モデル",
    sessionId: "example-session",
    title: "架空の依頼業務",
    unresolved: ["業務ルールを確認する"],
  };
};

test("モデルを受け取り、壊れた接続・重複ID・根拠のない確認済み事実を拒否する", () => {
  assert.equal(validateDocument(example()).title, "架空の依頼業務");
  const broken = example();
  broken.models.proposed.edges[0].target = "missing";
  assert.throws(() => validateDocument(broken), /接続/u);
  const duplicate = example();
  duplicate.models.current.nodes.push(duplicate.models.current.nodes[0]);
  assert.throws(() => validateDocument(duplicate), /ID/u);
  const unsupported = example();
  unsupported.models.current.nodes[0].data.origin = "code";
  assert.throws(() => validateDocument(unsupported), /根拠/u);
});

test("名称変更・削除後もID・根拠・指摘を保持し、コピー後の編集を上書きしない", () => {
  const original = example();
  original.comments.push({
    id: "comment-1",
    target: { id: "request", view: "proposed" },
    text: "再発行の条件は？",
  });
  const changed = editItem(original, "proposed", "node", "request", {
    data: {
      ...original.models.proposed.nodes[0].data,
      label: "依頼を再発行する",
    },
  });
  assert.equal(changed.models.proposed.nodes[0].id, "request");
  assert.equal(changed.models.proposed.nodes[0].data.origin, "proposal");
  assert.throws(
    () =>
      editItem(original, "current", "node", "request", {
        data: changed.models.proposed.nodes[0].data,
      }),
    /現状/u
  );
  const deleted = removeItem(changed, "node", "request");
  assert.equal(deleted.models.proposed.edges.length, 0);
  assert.equal(deleted.retired.length, 2);
  assert.equal(deleted.comments[0].text, "再発行の条件は？");
  const saved = {
    document: changed,
    lastExport: { id: "copy-1", signature: signature(changed) },
    seed: signature(original),
  };
  const incoming = {
    ...changed,
    basedOn: { exportId: "copy-1", revision: "r1" },
    revision: "r2",
  };
  assert.equal(reconcile(incoming, saved).conflict, false);
  saved.document = deleted;
  assert.equal(reconcile(incoming, saved).conflict, true);
  assert.equal(
    reconcile(incoming, saved).document.comments[0].text,
    "再発行の条件は？"
  );
  const copied = feedback(deleted, "copy-2");
  assert.ok(copied.includes("再発行の条件は？"));
  assert.ok(copied.includes('"retired"'));
  assert.deepEqual(Object.keys(artifacts(deleted)).toSorted(), [
    "changes.md",
    "glossary.md",
    "model.md",
    "scenarios.feature",
  ]);
  assert.ok(artifacts(deleted)["scenarios.feature"].includes("再確認待ち"));
});

test("AI更新の版・指摘・削除対象・根拠・人の配置を検証する", () => {
  const before = example();
  before.models.proposed.nodes[0].data.evidence = [
    { path: "src/flow.js", revision: "abc", symbol: "request" },
  ];
  const draft = structuredClone(before);
  draft.models.proposed.nodes[0].position.x += 40;
  draft.comments.push({
    id: "c1",
    target: { view: "whole" },
    text: "指摘を保持",
  });
  const saved = {
    document: draft,
    lastExport: { id: "export-1", signature: signature(draft) },
    seed: signature(before),
  };
  const good = {
    ...structuredClone(draft),
    basedOn: { exportId: "export-1", revision: "r1" },
    revision: "r2",
  };
  assert.equal(reconcile(good, saved).conflict, false);
  for (const mutate of [
    (doc) => {
      doc.revision = "r1";
    },
    (doc) => {
      doc.comments = [];
    },
    (doc) => {
      doc.models.proposed.nodes = [];
      doc.models.proposed.edges = [];
    },
    (doc) => {
      doc.models.proposed.nodes[0].data.evidence = [];
    },
    (doc) => {
      doc.models.proposed.nodes[0].position.x = 40;
    },
  ]) {
    const bad = structuredClone(good);
    mutate(bad);
    assert.equal(reconcile(bad, saved).conflict, true);
  }
  const deleted = removeItem(draft, "node", "request");
  const retiredUpdate = { ...deleted, basedOn: good.basedOn, revision: "r2" };
  assert.equal(reconcile(retiredUpdate, saved).conflict, false);
  const incomplete = structuredClone(deleted);
  delete incomplete.retired[0].item.position;
  assert.throws(() => validateDocument(incomplete), /配置/u);
  const savedDeleted = {
    ...saved,
    document: deleted,
    lastExport: { id: "export-2", signature: signature(deleted) },
  };
  assert.equal(
    reconcile(
      {
        ...retiredUpdate,
        basedOn: { exportId: "export-2", revision: "r1" },
        retired: [],
      },
      savedDeleted
    ).conflict,
    true
  );
});
