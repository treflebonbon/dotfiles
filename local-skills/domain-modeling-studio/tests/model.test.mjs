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
