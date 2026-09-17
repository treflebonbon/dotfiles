import assert from "node:assert/strict";
import { test } from "node:test";

import {
  validateDocument,
  editItem,
  removeItem,
  reconcile,
  withRevisionHistory,
  signature,
  feedback,
  artifacts,
} from "../src/model.mjs";
import { example } from "./fixture.mjs";

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
    { path: "src/flow.js", revision: "a".repeat(40), symbol: "request" },
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

test("未解決事項は明示的な解決記録だけで除去し、固定したソース版を変えない", () => {
  const original = example();
  original.unresolved.push("再発行の条件は？");
  const saved = {
    document: original,
    lastExport: { id: "review-copy", signature: signature(original) },
    seed: signature(original),
  };
  const incoming = {
    ...structuredClone(original),
    basedOn: { exportId: "review-copy", revision: "r1" },
    revision: "r2",
  };
  assert.equal(reconcile(incoming, saved).conflict, false);
  for (const unresolved of [[], original.unresolved.slice(0, 1)]) {
    const result = reconcile({ ...incoming, unresolved }, saved);
    assert.equal(result.conflict, true);
    assert.deepEqual(result.document, original);
  }
  const changedSource = {
    ...incoming,
    repository: { ...incoming.repository, revision: "b".repeat(40) },
  };
  assert.equal(reconcile(changedSource, saved).conflict, true);
  const resolved = {
    ...incoming,
    resolutions: [
      {
        evidence: [],
        question: original.unresolved[1],
        reason: "担当者の回答で再発行の条件を確認した（実装の証拠ではない）",
      },
    ],
    unresolved: original.unresolved.slice(0, 1),
  };
  assert.equal(reconcile(resolved, saved).conflict, false);
  assert.ok(
    artifacts(resolved)["model.md"].includes(resolved.resolutions[0].reason)
  );
  assert.throws(
    () =>
      validateDocument({
        ...resolved,
        resolutions: [{ ...resolved.resolutions[0], reason: " " }],
      }),
    /解決/u
  );
  assert.throws(
    () => validateDocument({ ...resolved, resolutions: null }),
    /解決/u
  );
  const next = {
    ...resolved,
    basedOn: { exportId: "next-copy", revision: "r2" },
    resolutions: [],
    revision: "r3",
  };
  assert.equal(
    reconcile(next, {
      document: resolved,
      lastExport: { id: "next-copy", signature: signature(resolved) },
      seed: signature(resolved),
    }).conflict,
    true
  );
});

test("ソースと根拠には完全長のGitコミットIDだけを受け入れる", () => {
  for (const revision of [
    "a".repeat(40),
    "B".repeat(64),
    "main",
    "HEAD",
    "abc123",
    "g".repeat(40),
    "a".repeat(41),
  ]) {
    const valid =
      (revision.length === 40 && revision.startsWith("a")) ||
      revision === "B".repeat(64);
    const doc = example();
    doc.repository.revision = revision;
    if (valid) {
      assert.doesNotThrow(() => validateDocument(doc));
    } else {
      assert.throws(() => validateDocument(doc), /コミット/u);
    }
    doc.repository = example().repository;
    doc.models.current.nodes[0].data.evidence = [
      { path: "src/flow.js", revision, symbol: "request" },
    ];
    if (valid) {
      assert.doesNotThrow(() => validateDocument(doc));
    } else {
      assert.throws(() => validateDocument(doc), /コミット/u);
    }
  }
});

test("人間の要素・関係の意味編集は、対象と変更前後が一致する解決記録が必要", () => {
  for (const [key, field, value] of [
    ["nodes", "label", "依頼を再発行する"],
    ["nodes", "kind", "PROCESS"],
    ["edges", "label", "追加の条件"],
    ["edges", "source", "accept"],
    ["edges", "target", "request"],
  ]) {
    const seed = example();
    const draft = structuredClone(seed);
    const [item] = draft.models.proposed[key];
    const data = key === "nodes" ? item.data : item;
    data[field] = value;
    const saved = {
      document: draft,
      lastExport: { id: "copy", signature: signature(draft) },
      seed: signature(seed),
    };
    const incoming = {
      ...structuredClone(draft),
      basedOn: { exportId: "copy", revision: "r1" },
      revision: "r2",
    };
    assert.equal(reconcile(incoming, saved).conflict, false);
    const [next] = incoming.models.proposed[key];
    const [original] = seed.models.proposed[key];
    const after = key === "nodes" ? original.data[field] : original[field];
    (key === "nodes" ? next.data : next)[field] = after;
    assert.equal(reconcile(incoming, saved).conflict, true);
    incoming.editResolutions = [
      {
        after,
        before: value,
        entity: key === "nodes" ? "node" : "edge",
        evidence: [],
        field,
        id: item.id,
        reason: "人間の指摘を再調査して訂正",
      },
    ];
    assert.equal(reconcile(incoming, saved).conflict, false);
    assert.ok(
      artifacts(incoming)["model.md"].includes("人間の指摘を再調査して訂正")
    );
    incoming.editResolutions[0].before = "別の値";
    assert.equal(reconcile(incoming, saved).conflict, true);
    incoming.editResolutions[0].reason = "";
    assert.throws(() => validateDocument(incoming), /編集解決/u);
    // No protection is imposed on untouched AI semantics, or current-model corrections.
    delete incoming.editResolutions;
    saved.seed = signature(draft);
    assert.equal(reconcile(incoming, saved).conflict, false);
    saved.seed = signature(seed);
    incoming.models.proposed = structuredClone(draft.models.proposed);
    incoming.models.current.nodes[0].data.label = "再調査による訂正";
    assert.equal(reconcile(incoming, saved).conflict, false);
    // A human-created item has no seed counterpart: all of its semantics are protected.
    const emptySeed = example();
    emptySeed.models.proposed = { edges: [], nodes: [] };
    saved.seed = signature(emptySeed);
    incoming.models.proposed[key][0] = structuredClone(original);
    assert.equal(reconcile(incoming, saved).conflict, true);
  }
  const doc = example();
  doc.editResolutions = [
    {
      after: "依頼する",
      before: "旧称",
      entity: "node",
      evidence: [],
      field: "label",
      id: "request",
      reason: "合意した名称",
    },
  ];
  const next = {
    ...doc,
    basedOn: { exportId: "copy", revision: "r1" },
    editResolutions: [],
    revision: "r2",
  };
  assert.equal(
    reconcile(next, {
      document: doc,
      lastExport: { id: "copy", signature: signature(doc) },
      seed: signature(doc),
    }).conflict,
    true
  );
});

const update = (doc, revision) =>
  reconcile(
    {
      ...structuredClone(doc),
      basedOn: { exportId: "copy", revision: doc.revision },
      revision,
      revisionHistory: [],
    },
    {
      document: doc,
      lastExport: { id: "copy", signature: signature(doc) },
      seed: signature(doc),
    }
  );

test("更新・リロード・古いバックアップの復元後も使用済み版を再利用しない", () => {
  const original = example();
  const second = update(original, "r2");
  assert.equal(second.conflict, false);
  assert.deepEqual(second.document.revisionHistory, ["r1"]);
  const third = update(second.document, "r3");
  assert.equal(third.conflict, false);
  const persisted = structuredClone(third.document);
  assert.equal(update(persisted, "r1").conflict, true);
  assert.equal(update(persisted, "r2").conflict, true);
  const restored = withRevisionHistory(original, persisted);
  assert.deepEqual(restored.revisionHistory.toSorted(), ["r2", "r3"]);
  assert.equal(update(restored, "r2").conflict, true);
  assert.equal(update(restored, "r3").conflict, true);
  assert.equal(update(restored, "r4").conflict, false);
  const fresh = reconcile(
    { ...second.document, revisionHistory: undefined },
    null
  ).document;
  assert.equal(update(fresh, "r1").conflict, true);
  for (const revisionHistory of [null, ["r1", "r1"], ["invalid revision"]]) {
    assert.throws(
      () => validateDocument({ ...original, revisionHistory }),
      /版履歴/u
    );
  }
});
