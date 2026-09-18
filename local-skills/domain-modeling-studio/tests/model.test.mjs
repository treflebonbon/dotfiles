import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

const flowNode = (id, kind, extra = {}) => ({
  data: { evidence: [], kind, label: id, origin: "inference", ...extra },
  height: 90,
  id,
  position: { x: 40, y: 80 },
  width: 180,
});
const edge = (id, source, target, label) => ({
  data: { evidence: [], origin: "inference" },
  id,
  label,
  source,
  target,
});

test("アーキテクチャ層・関数フロー層の新種別とdrillIntoの正常系・異常系を検証する", () => {
  const withLayers = () => {
    const doc = example();
    doc.models.proposed.nodes.push(
      flowNode("module-a", "MODULE", { drillInto: "stage-1" }),
      flowNode("external-a", "EXTERNAL"),
      flowNode("stage-1", "STAGE", { drillInto: "request" }),
      flowNode("failure-1", "FAILURE_HANDLER"),
      flowNode("recovery-1", "RECOVERY"),
      flowNode("bypass-1", "BYPASS"),
      flowNode("termination-1", "TERMINATION"),
      flowNode("outside-1", "OUTSIDE_TYPED_ERROR")
    );
    return doc;
  };
  assert.doesNotThrow(() => validateDocument(withLayers()));

  const danglingTarget = withLayers();
  danglingTarget.models.proposed.nodes.find(
    (n) => n.id === "stage-1"
  ).data.drillInto = "missing-node";
  assert.throws(() => validateDocument(danglingTarget), /ドリルダウン/u);

  const architectureToBusiness = withLayers();
  architectureToBusiness.models.proposed.nodes.find(
    (n) => n.id === "module-a"
  ).data.drillInto = "request";
  assert.throws(
    () => validateDocument(architectureToBusiness),
    /ドリルダウン/u
  );

  const flowToFlow = withLayers();
  flowToFlow.models.proposed.nodes.find(
    (n) => n.id === "stage-1"
  ).data.drillInto = "failure-1";
  assert.throws(() => validateDocument(flowToFlow), /ドリルダウン/u);

  const businessWithDrillInto = withLayers();
  businessWithDrillInto.models.proposed.nodes[0].data.drillInto = "stage-1";
  assert.throws(() => validateDocument(businessWithDrillInto), /ドリルダウン/u);

  const malformedId = withLayers();
  malformedId.models.proposed.nodes.find(
    (n) => n.id === "stage-1"
  ).data.drillInto = "../etc/passwd";
  assert.throws(() => validateDocument(malformedId), /ドリルダウン/u);

  const unknownKind = withLayers();
  unknownKind.models.proposed.nodes.find((n) => n.id === "module-a").data.kind =
    "BOGUS";
  assert.throws(() => validateDocument(unknownKind), /種別/u);

  const oldSchema = withLayers();
  oldSchema.schemaVersion = 1;
  assert.throws(() => validateDocument(oldSchema), /schemaVersion/u);
});

test("TypeScript EffectとRustのフィクスチャ関数からROP意味論に従って関数フロー層を生成する", () => {
  const FIXTURE_REVISION = "0".repeat(40);
  const tsPath =
    "local-skills/domain-modeling-studio/tests/fixtures/effect-checkout.ts.fixture";
  const rsPath =
    "local-skills/domain-modeling-studio/tests/fixtures/rust-checkout.rs.fixture";
  const ref = (path, symbol, line) => ({
    line,
    path,
    revision: FIXTURE_REVISION,
    symbol,
  });

  const businessNode = flowNode("checkout-flow", "COMMAND", {
    label: "注文を確定する",
  });
  const nodes = [
    businessNode,
    // Effect: bind (reserve/charge), recovery scoped to reserve's OutOfStock,
    // a synthetic bypass around catchTag, and mapError as a failure-only handler.
    flowNode("ts-reserve", "STAGE", {
      evidence: [ref(tsPath, "reserve", 12)],
      label: "予約する(reserve)",
      origin: "code",
    }),
    flowNode("ts-charge", "STAGE", {
      evidence: [ref(tsPath, "charge", 13)],
      label: "請求する(charge)",
      origin: "code",
    }),
    flowNode("ts-recovery", "RECOVERY", {
      evidence: [ref(tsPath, "catchTag", 15)],
      label: "在庫切れを代替入荷へ回復する(catchTag)",
      origin: "code",
    }),
    flowNode("ts-bypass", "BYPASS", {
      label: "PaymentDeclinedはcatchTagの対象外のため素通りする",
    }),
    flowNode("ts-map-error", "FAILURE_HANDLER", {
      evidence: [ref(tsPath, "mapError", 16)],
      label: "残った失敗をCheckoutFailedへ変換する(mapError)",
      origin: "code",
    }),
    flowNode("ts-success-end", "TERMINATION", {
      drillInto: "checkout-flow",
      evidence: [ref(tsPath, "checkout", 13)],
      label: "確定応答を返す",
      origin: "code",
    }),
    flowNode("ts-recovered-end", "TERMINATION", {
      drillInto: "checkout-flow",
      evidence: [ref(tsPath, "catchTag", 15)],
      label: "代替入荷で確定する",
      origin: "code",
    }),
    flowNode("ts-failure-end", "TERMINATION", {
      evidence: [ref(tsPath, "mapError", 16)],
      label: "失敗を返す",
      origin: "code",
    }),
    // Rust: `?` bind/early-return, or_else recovery scoped to tax_rate, its
    // executed non-recovering `other => Err(other)` arm as a real bypass, and
    // expect() turning a returned Err into a panic outside the typed lane.
    flowNode("rs-normalize", "STAGE", {
      evidence: [ref(rsPath, "normalize_country", 22)],
      label: "国コードを正規化する(normalize_country)",
      origin: "code",
    }),
    flowNode("rs-quote", "STAGE", {
      evidence: [ref(rsPath, "quote_tax", 23)],
      label: "税率を照会する(quote_tax)",
      origin: "code",
    }),
    flowNode("rs-recovery", "RECOVERY", {
      evidence: [ref(rsPath, "tax_rate", 24)],
      label: "ServiceDownを0円へ回復する(or_else)",
      origin: "code",
    }),
    flowNode("rs-bypass", "BYPASS", {
      evidence: [ref(rsPath, "tax_rate", 25)],
      label: "ServiceDown以外はor_elseの対象外のまま伝播する",
      origin: "code",
    }),
    flowNode("rs-tax-rate-failure", "TERMINATION", {
      evidence: [
        ref(rsPath, "normalize_country", 8),
        ref(rsPath, "tax_rate", 25),
      ],
      label: "tax_rateがErrを返す",
      origin: "code",
    }),
    flowNode("rs-tax-rate-success", "STAGE", {
      evidence: [ref(rsPath, "quote_tax", 23), ref(rsPath, "tax_rate", 24)],
      label: "tax_rateがOkを返す",
      origin: "code",
    }),
    flowNode("rs-outside-error", "OUTSIDE_TYPED_ERROR", {
      evidence: [ref(rsPath, "charge_invoice", 30)],
      label: "expectがErrでpanicする(型付きエラー外)",
      origin: "code",
    }),
    flowNode("rs-success-end", "TERMINATION", {
      drillInto: "checkout-flow",
      evidence: [ref(rsPath, "charge_invoice", 30)],
      label: "税率込みの金額を返す",
      origin: "code",
    }),
  ];
  const edges = [
    edge("e-ts-reserve-charge", "ts-reserve", "ts-charge", "予約成功"),
    edge("e-ts-charge-success", "ts-charge", "ts-success-end", "請求成功"),
    edge(
      "e-ts-reserve-recovery",
      "ts-reserve",
      "ts-recovery",
      "OutOfStock（在庫切れ）"
    ),
    edge(
      "e-ts-recovery-end",
      "ts-recovery",
      "ts-recovered-end",
      "backorderへ回復"
    ),
    edge(
      "e-ts-charge-bypass",
      "ts-charge",
      "ts-bypass",
      "PaymentDeclined（catchTagの対象外）"
    ),
    edge(
      "e-ts-bypass-maperror",
      "ts-bypass",
      "ts-map-error",
      "素通りしてmapErrorへ"
    ),
    edge(
      "e-ts-maperror-end",
      "ts-map-error",
      "ts-failure-end",
      "CheckoutFailedとして返す"
    ),
    edge("e-rs-normalize-quote", "rs-normalize", "rs-quote", "正規化成功"),
    edge(
      "e-rs-normalize-failure",
      "rs-normalize",
      "rs-tax-rate-failure",
      "InvalidCountryで早期return"
    ),
    edge(
      "e-rs-quote-success",
      "rs-quote",
      "rs-tax-rate-success",
      "税率取得成功"
    ),
    edge("e-rs-quote-recovery", "rs-quote", "rs-recovery", "ServiceDown"),
    edge(
      "e-rs-recovery-success",
      "rs-recovery",
      "rs-tax-rate-success",
      "0円へ回復"
    ),
    edge("e-rs-quote-bypass", "rs-quote", "rs-bypass", "ServiceDown以外のErr"),
    edge(
      "e-rs-bypass-failure",
      "rs-bypass",
      "rs-tax-rate-failure",
      "Errのまま伝播"
    ),
    edge(
      "e-rs-success-end",
      "rs-tax-rate-success",
      "rs-success-end",
      "expectが値を取り出す"
    ),
    edge(
      "e-rs-failure-outside",
      "rs-tax-rate-failure",
      "rs-outside-error",
      "expectがErrでpanicする"
    ),
  ];
  const graph = { edges, nodes };
  const doc = {
    basedOn: null,
    changes: [],
    comments: [],
    glossary: [],
    models: {
      current: structuredClone(graph),
      proposed: structuredClone(graph),
    },
    repository: {
      name: "example/checkout-fixtures",
      revision: FIXTURE_REVISION,
    },
    retired: [],
    revision: "r1",
    scenarios: [],
    schemaVersion: 2,
    scope: "TypeScript EffectとRustのフィクスチャ関数のROP関数フロー層",
    sessionId: "function-flow-fixture-session",
    title: "関数フロー層のフィクスチャ検証",
    unresolved: [],
  };

  assert.doesNotThrow(() => validateDocument(doc));

  // Every cited evidence line must actually contain the construct it is cited
  // for, so an edit to either fixture fails this test instead of going unnoticed.
  const fixtureLines = {
    [tsPath]: readFileSync(
      new URL("fixtures/effect-checkout.ts.fixture", import.meta.url),
      "utf-8"
    ).split("\n"),
    [rsPath]: readFileSync(
      new URL("fixtures/rust-checkout.rs.fixture", import.meta.url),
      "utf-8"
    ).split("\n"),
  };
  const expectedText = {
    [tsPath]: {
      12: "reserve(id)",
      13: "charge(reserved)",
      15: "catchTag",
      16: "mapError",
    },
    [rsPath]: {
      22: "normalize_country",
      23: "quote_tax",
      24: "ServiceDown => Ok(0)",
      25: "other => Err(other)",
      30: "expect(",
      8: "InvalidCountry",
    },
  };
  for (const node of nodes) {
    for (const item of node.data.evidence) {
      const expected = expectedText[item.path]?.[item.line];
      assert.ok(
        expected,
        `no expected text registered for ${item.path}:${item.line}`
      );
      assert.ok(
        fixtureLines[item.path][item.line - 1].includes(expected),
        `${item.path}:${item.line} does not contain ${JSON.stringify(expected)}`
      );
    }
  }

  const byId = new Map(nodes.map((n) => [n.id, n]));
  const outgoing = (nodeId) => edges.filter((e) => e.source === nodeId);
  const incoming = (nodeId) => edges.filter((e) => e.target === nodeId);

  // Success never routes through a failure-lane node.
  assert.deepEqual(
    outgoing("ts-reserve")
      .map((e) => e.target)
      .toSorted(),
    ["ts-charge", "ts-recovery"]
  );
  assert.deepEqual(
    outgoing("ts-charge")
      .map((e) => e.target)
      .toSorted(),
    ["ts-bypass", "ts-success-end"]
  );

  // Recovery only receives the failure from its actual scope (reserve), never charge's.
  assert.deepEqual(
    incoming("ts-recovery").map((e) => e.source),
    ["ts-reserve"]
  );

  // A bypass with no dispatching source is synthetic; an executed non-recovering
  // arm (Rust's `other => Err(other)`) is real source with evidence.
  assert.equal(byId.get("ts-bypass").data.origin, "inference");
  assert.deepEqual(byId.get("ts-bypass").data.evidence, []);
  assert.equal(byId.get("rs-bypass").data.origin, "code");
  assert.ok(byId.get("rs-bypass").data.evidence.length > 0);

  // Termination ends its path.
  for (const nodeId of [
    "ts-success-end",
    "ts-recovered-end",
    "ts-failure-end",
    "rs-success-end",
  ]) {
    assert.deepEqual(outgoing(nodeId), []);
  }

  // Outside-typed-error is a boundary reached only from a returned failure, and
  // is itself a dead end distinct from the typed-error handlers above it.
  assert.deepEqual(
    incoming("rs-outside-error").map((e) => e.source),
    ["rs-tax-rate-failure"]
  );
  assert.deepEqual(outgoing("rs-outside-error"), []);

  // Function-flow terminations drill down into the business flow they implement.
  assert.equal(byId.get("ts-success-end").data.drillInto, "checkout-flow");
  assert.equal(byId.get("rs-success-end").data.drillInto, "checkout-flow");
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
