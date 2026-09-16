export const KINDS = [
  "COMMAND",
  "EVENT",
  "POLICY",
  "READ_MODEL",
  "AGGREGATE",
  "ACTOR",
  "PROCESS",
];
export const ORIGINS = {
  agreement: "業務上の合意",
  code: "コードで確認",
  inference: "AIの推測",
  proposal: "未検証の改善案",
};
const views = ["current", "proposed"];
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v) => typeof v === "string";
const nonempty = (v) => text(v) && v.trim().length > 0;
const id = (v) => text(v) && /^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/u.test(v);
const need = (condition, message) => {
  if (!condition) {
    throw new Error(message);
  }
};
const evidence = (items) => {
  need(Array.isArray(items), "根拠は配列で指定してください");
  for (const ref of items) {
    need(
      object(ref) &&
        nonempty(ref.path) &&
        nonempty(ref.symbol) &&
        nonempty(ref.revision),
      "根拠にpath・symbol・revisionが必要です"
    );
    need(
      !ref.path.startsWith("/") && !ref.path.split("/").includes(".."),
      "根拠はリポジトリ相対パスで指定してください"
    );
    need(
      ref.line === undefined || (Number.isInteger(ref.line) && ref.line > 0),
      "根拠の行番号が不正です"
    );
  }
};
const provenance = (data) => {
  need(object(data) && Object.hasOwn(ORIGINS, data.origin), "確度が不正です");
  evidence(data.evidence);
  need(
    data.origin !== "code" || data.evidence.length > 0,
    "コードで確認した要素には根拠が必要です"
  );
};
const validateNode = (node) => {
  need(
    nonempty(node.data.label) && KINDS.includes(node.data.kind),
    "要素の名称・種別が不正です"
  );
  need(
    object(node.position) &&
      Number.isFinite(node.position.x) &&
      Number.isFinite(node.position.y),
    "要素の配置が不正です"
  );
  need(
    Number.isFinite(node.width) &&
      node.width >= 100 &&
      Number.isFinite(node.height) &&
      node.height >= 60,
    "要素のサイズが不正です"
  );
};
const validateGraph = (graph, view) => {
  need(
    object(graph) && Array.isArray(graph.nodes) && Array.isArray(graph.edges),
    `${view}にnodes・edgesが必要です`
  );
  const ids = new Set();
  for (const item of [...graph.nodes, ...graph.edges]) {
    need(
      object(item) && id(item.id) && !ids.has(item.id),
      "要素・関係のIDが不正または重複しています"
    );
    ids.add(item.id);
    provenance(item.data);
  }
  for (const node of graph.nodes) {
    validateNode(node);
  }
  const nodeIds = new Set(graph.nodes.map((n) => n.id));
  for (const edge of graph.edges) {
    need(
      nodeIds.has(edge.source) && nodeIds.has(edge.target),
      "接続先が見つかりません"
    );
    need(text(edge.label), "関係の条件ラベルが必要です");
  }
};

const validateComment = (comment) => {
  need(
    object(comment) &&
      id(comment.id) &&
      text(comment.text) &&
      object(comment.target),
    "指摘の形式が不正です"
  );
  need(
    comment.target.view === "whole" ||
      (views.includes(comment.target.view) && id(comment.target.id)),
    "指摘対象が不正です"
  );
};

const validateRetired = (entry) => {
  need(
    object(entry) &&
      views.includes(entry.view) &&
      ["node", "edge"].includes(entry.entity) &&
      object(entry.item) &&
      id(entry.item.id),
    "削除記録が不正です"
  );
  provenance(entry.item.data);
  if (entry.entity === "node") {
    validateNode(entry.item);
  } else {
    need(
      id(entry.item.source) && id(entry.item.target),
      "削除した関係の端点が不正です"
    );
  }
  need(
    entry.entity === "node"
      ? nonempty(entry.item.data.label)
      : text(entry.item.label),
    "削除対象の名称が不正です"
  );
};

const validateTerm = (term) => {
  need(
    object(term) &&
      nonempty(term.term) &&
      text(term.definition) &&
      ["confirmed", "draft"].includes(term.status),
    "用語辞書の形式が不正です"
  );
  evidence(term.evidence);
};

const validateScenario = (scenario) => {
  need(
    object(scenario) &&
      id(scenario.id) &&
      nonempty(scenario.title) &&
      views.includes(scenario.model) &&
      ["confirmed", "draft"].includes(scenario.status),
    "シナリオの形式が不正です"
  );
  need(
    Array.isArray(scenario.given) &&
      scenario.given.length > 0 &&
      scenario.given.every(nonempty) &&
      nonempty(scenario.when) &&
      Array.isArray(scenario.then) &&
      scenario.then.length > 0 &&
      scenario.then.every(nonempty),
    "シナリオの前提・操作・結果が必要です"
  );
  evidence(scenario.evidence);
  need(
    scenario.status !== "confirmed" || scenario.evidence.length > 0,
    "確認済みシナリオには根拠が必要です"
  );
};

const validateChange = (change) => {
  need(
    object(change) &&
      id(change.id) &&
      nonempty(change.title) &&
      text(change.reason) &&
      ["proposed", "agreed"].includes(change.status),
    "実装変更候補の形式が不正です"
  );
  evidence(change.evidence);
};

const validateResolutions = (items = []) => {
  need(Array.isArray(items), "解決記録は配列で指定してください");
  for (const item of items) {
    need(
      object(item) && nonempty(item.question) && nonempty(item.reason),
      "解決記録には元の質問と解決理由が必要です"
    );
    evidence(item.evidence);
  }
};

export const validateDocument = (doc) => {
  need(
    object(doc) && doc.schemaVersion === 1,
    "未対応のモデル形式です（schemaVersion: 1が必要）"
  );
  need(id(doc.sessionId) && id(doc.revision), "sessionId・revisionが不正です");
  need(nonempty(doc.title) && text(doc.scope), "タイトル・対象範囲が必要です");
  need(
    object(doc.repository) &&
      nonempty(doc.repository.name) &&
      nonempty(doc.repository.revision),
    "リポジトリと参照版が必要です"
  );
  need(
    doc.basedOn === null ||
      (object(doc.basedOn) &&
        id(doc.basedOn.revision) &&
        id(doc.basedOn.exportId)),
    "basedOnが不正です"
  );
  need(object(doc.models), "現状・改善案が必要です");
  need(
    doc.needsReview === undefined || typeof doc.needsReview === "boolean",
    "needsReviewは真偽値で指定してください"
  );
  for (const view of views) {
    validateGraph(doc.models[view], view);
  }
  for (const key of [
    "comments",
    "retired",
    "glossary",
    "scenarios",
    "changes",
    "unresolved",
  ]) {
    need(Array.isArray(doc[key]), `${key}は配列で指定してください`);
  }
  for (const item of doc.comments) {
    validateComment(item);
  }
  need(
    new Set(doc.comments.map((c) => c.id)).size === doc.comments.length,
    "指摘IDが重複しています"
  );
  for (const item of doc.retired) {
    validateRetired(item);
  }
  for (const item of doc.glossary) {
    validateTerm(item);
  }
  for (const item of doc.scenarios) {
    validateScenario(item);
  }
  for (const item of doc.changes) {
    validateChange(item);
  }
  need(doc.unresolved.every(nonempty), "未解決事項は文字列で指定してください");
  validateResolutions(doc.resolutions);
  // Imported JSON never supplies executable React Flow props, styles, or HTML.
  return structuredClone(doc);
};

export const signature = (doc) => JSON.stringify(doc);
const canonical = (value) =>
  JSON.stringify(value, (_key, item) =>
    object(item)
      ? Object.fromEntries(
          Object.entries(item).toSorted(([a], [b]) => a.localeCompare(b))
        )
      : item
  );
const preservesEvidence = (before, after) =>
  before.every((ref) =>
    after.some((candidate) => canonical(ref) === canonical(candidate))
  );
const preservesItems = (incoming, previous, view, key, seed) =>
  previous.models[view][key].every((item) => {
    const next = incoming.models[view][key].find(
      (candidate) => candidate.id === item.id
    );
    const removed = incoming.retired.find(
      (entry) =>
        entry.view === view &&
        entry.item.id === item.id &&
        entry.entity === (key === "nodes" ? "node" : "edge")
    );
    if (!next) {
      return Boolean(removed && canonical(removed.item) === canonical(item));
    }
    if (!preservesEvidence(item.data.evidence, next.data.evidence)) {
      return false;
    }
    if (key !== "nodes") {
      return true;
    }
    const original = seed.models[view].nodes.find(
      (candidate) => candidate.id === item.id
    );
    // Preserve human layout changes; AI may arrange its untouched source nodes.
    return ["position", "width", "height"].every(
      (field) =>
        (original && canonical(original[field]) === canonical(item[field])) ||
        canonical(item[field]) === canonical(next[field])
    );
  });
const preservesReview = (incoming, saved) => {
  const previous = saved.document;
  let seed;
  try {
    seed = validateDocument(JSON.parse(saved.seed));
  } catch {
    return false;
  }
  return (
    incoming.repository.name === previous.repository.name &&
    incoming.repository.revision === previous.repository.revision &&
    previous.unresolved.every(
      (question) =>
        incoming.unresolved.includes(question) ||
        incoming.resolutions?.some((item) => item.question === question)
    ) &&
    (previous.resolutions ?? []).every((item) =>
      incoming.resolutions?.some(
        (candidate) => canonical(item) === canonical(candidate)
      )
    ) &&
    previous.comments.every((comment) =>
      incoming.comments.some(
        (candidate) => canonical(comment) === canonical(candidate)
      )
    ) &&
    previous.retired.every((entry) =>
      incoming.retired.some(
        (candidate) => canonical(entry) === canonical(candidate)
      )
    ) &&
    views.every((view) =>
      ["nodes", "edges"].every((key) =>
        preservesItems(incoming, previous, view, key, seed)
      )
    )
  );
};
export const reconcile = (incoming, saved) => {
  validateDocument(incoming);
  if (!saved) {
    return { conflict: false, document: incoming, lastExport: null };
  }
  validateDocument(saved.document);
  if (saved.document.sessionId !== incoming.sessionId) {
    throw new Error("別セッションの下書きです");
  }
  const sameSeed = saved.seed === signature(incoming);
  const acknowledged =
    incoming.basedOn &&
    incoming.revision !== saved.document.revision &&
    incoming.basedOn.revision === saved.document.revision &&
    incoming.basedOn.exportId === saved.lastExport?.id &&
    saved.lastExport.signature === signature(saved.document);
  if (sameSeed) {
    return {
      conflict: false,
      document: saved.document,
      lastExport: saved.lastExport ?? null,
    };
  }
  if (acknowledged && preservesReview(incoming, saved)) {
    return { conflict: false, document: incoming, lastExport: null };
  }
  return {
    conflict: true,
    document: saved.document,
    lastExport: saved.lastExport ?? null,
  };
};

export const editItem = (doc, view, entity, itemId, patch) => {
  need(
    views.includes(view) && ["node", "edge"].includes(entity),
    "編集対象が不正です"
  );
  const next = structuredClone(doc);
  const item = next.models[view][entity === "node" ? "nodes" : "edges"].find(
    (n) => n.id === itemId
  );
  need(item, "編集対象が見つかりません");
  const layoutKeys = new Set(["position", "width", "height"]);
  need(!Object.hasOwn(patch, "id"), "IDは変更できません");
  const semantic = Object.keys(patch).some((key) => !layoutKeys.has(key));
  need(
    view === "proposed" || !semantic,
    "現状の業務内容は指摘から再確認してください"
  );
  Object.assign(item, patch);
  if (semantic) {
    item.data = { ...item.data, origin: "proposal" };
    next.needsReview = true;
  }
  return validateDocument(next);
};

export const removeItem = (doc, entity, itemId) => {
  const next = structuredClone(doc);
  const graph = next.models.proposed;
  const nodes =
    entity === "node" ? graph.nodes.filter((n) => n.id === itemId) : [];
  const edges = graph.edges.filter(
    (e) =>
      e.id === itemId ||
      nodes.some((n) => n.id === e.source || n.id === e.target)
  );
  next.retired.push(
    ...nodes.map((item) => ({ entity: "node", item, view: "proposed" })),
    ...edges.map((item) => ({ entity: "edge", item, view: "proposed" }))
  );
  graph.nodes = graph.nodes.filter((n) => !nodes.includes(n));
  graph.edges = graph.edges.filter((e) => !edges.includes(e));
  next.needsReview = true;
  return validateDocument(next);
};

const md = (s) =>
  String(s)
    .replaceAll(/[\\`*_{}[\]()#+.!|>~<-]/gu, "\\$&")
    .replaceAll("\n", " ");
const mermaidText = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\n", " ");
export const toMermaid = (graph) => {
  // Use generated diagram IDs: user-provided IDs like "end" have Mermaid meaning.
  const ids = new Map(graph.nodes.map((n, i) => [n.id, `N${i}`]));
  return [
    "flowchart LR",
    ...graph.nodes.map(
      (n) => `  ${ids.get(n.id)}["${mermaidText(n.data.label)}"]`
    ),
    ...graph.edges.map(
      (e) =>
        `  ${ids.get(e.source)} -->|"${mermaidText(e.label).replaceAll("|", "&#124;")}"| ${ids.get(e.target)}`
    ),
  ].join("\n");
};
const refs = (items) =>
  items
    .map(
      (r) =>
        `- ${md(r.path)}${r.line ? `:${r.line}` : ""} / ${md(r.symbol)} @ ${md(r.revision)}`
    )
    .join("\n");
const clean = (s) => String(s).replaceAll(/[\r\n]/gu, " ");
export const artifacts = (doc) => {
  const model = [
    `# ${md(doc.title)}`,
    `${md(doc.repository.name)} @ ${md(doc.repository.revision)}`,
    md(doc.scope),
  ];
  for (const view of views) {
    model.push(
      `\n## ${view === "current" ? "現状" : "改善案"}`,
      "```mermaid",
      toMermaid(doc.models[view]),
      "```"
    );
    for (const item of [...doc.models[view].nodes, ...doc.models[view].edges]) {
      model.push(
        `\n### ${md(item.id)}: ${md(item.data.label ?? item.label)}`,
        ORIGINS[item.data.origin],
        refs(item.data.evidence)
      );
    }
  }
  model.push(
    "\n## 指摘",
    ...doc.comments.map(
      (c) =>
        `- ${md(c.target.view)} / ${md(c.target.id ?? "全体")}: ${md(c.text)}`
    ),
    "\n## 削除記録",
    ...doc.retired.map(
      (r) =>
        `- ${md(r.view)} / ${md(r.item.id)}: ${md(r.item.data.label ?? r.item.label)}`
    ),
    "\n## 未解決",
    ...doc.unresolved.map((s) => `- ${md(s)}`),
    "\n## 解決記録",
    ...(doc.resolutions ?? []).map(
      (item) =>
        `\n### ${md(item.question)}\n${md(item.reason)}\n${refs(item.evidence)}`
    )
  );
  const glossary = [
    "# 用語辞書",
    ...doc.glossary.map(
      (t) =>
        `\n## ${md(t.term)}\n${t.status === "confirmed" ? "合意済み" : "草案"}\n\n${md(t.definition)}\n${refs(t.evidence)}`
    ),
  ].join("\n");
  const bdd = [
    `# レビュー用草案：テスト実行結果ではありません`,
    ...(doc.needsReview ? ["# モデル変更後の再確認待ち"] : []),
    `Feature: ${clean(doc.title)}`,
    ...doc.scenarios.map(
      (s) =>
        `\n  # ${s.model} / ${s.status}\n${s.evidence.map((r) => `  # ${clean(r.path)}:${r.line ?? ""} @ ${clean(r.revision)}`).join("\n")}\n  Scenario: ${clean(s.title)}\n${s.given.map((g, i) => `    ${i ? "And" : "Given"} ${clean(g)}`).join("\n")}\n    When ${clean(s.when)}\n${s.then.map((t, i) => `    ${i ? "And" : "Then"} ${clean(t)}`).join("\n")}`
    ),
  ].join("\n");
  const changes = [
    "# 実装変更候補",
    ...doc.changes.map(
      (c) =>
        `\n## ${md(c.title)}\n${c.status === "agreed" ? "合意済み・実装は別工程" : "提案・未実装"}\n\n${md(c.reason)}\n${refs(c.evidence)}`
    ),
  ].join("\n");
  const warning = doc.needsReview
    ? "> モデル変更後のためAIによる再確認が必要です。\n\n"
    : "";
  return {
    "changes.md": warning + changes,
    "glossary.md": warning + glossary,
    "model.md": model.join("\n"),
    "scenarios.feature": bdd,
  };
};

export const feedback = (doc, exportId) => {
  const payload = {
    document: doc,
    exportId,
    format: "domain-studio-feedback-v1",
  };
  const json = JSON.stringify(payload, null, 2);
  const fence = "`".repeat(
    Math.max(3, ...[...json.matchAll(/`+/gu)].map((m) => m[0].length + 1))
  );
  return `# ドメインモデルのレビュー\nセッション: ${md(doc.sessionId)} / 版: ${md(doc.revision)}\n回答ID: ${exportId}\n\n指摘と改善案を再調査してください。現状はコードから再確認し、用語・BDD・変更候補も整合させてください。更新版のbasedOnには、この版と回答IDを設定し、未解決事項と削除対象への指摘を保持してください。\n\n${doc.comments.map((c) => `- ${md(c.target.view)}/${md(c.target.id ?? "全体")}: ${md(c.text)}`).join("\n")}\n\n${fence}json\n${json}\n${fence}\n`;
};
