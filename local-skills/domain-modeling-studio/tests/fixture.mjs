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
    repository: { name: "example/project", revision: "0".repeat(40) },
    retired: [],
    revision: "r1",
    scenarios: [],
    schemaVersion: 2,
    scope: "実装未確認の説明用モデル",
    sessionId: "example-session",
    title: "架空の依頼業務",
    unresolved: ["業務ルールを確認する"],
  };
};
