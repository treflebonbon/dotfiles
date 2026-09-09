const element = (id) => document.querySelector(`#${id}`);

(() => {
  const model = JSON.parse(document.querySelector("#flow-data").textContent);
  const byId = new Map(model.nodes.map((node) => [node.id, node]));
  const setText = (id, text) => {
    element(id).textContent = text;
  };
  const graph = element("graph");
  const svg = graph.querySelector("svg");
  svg.style.minInlineSize = `${svg.viewBox.baseVal.width * 0.875}px`;
  const kinds = {
    boundary: "この図で扱う範囲の境界",
    bypass: "失敗の伝播・追加処理なし",
    recover: "回復",
    terminal: "終了",
    work: "処理",
  };
  const nodes = new Map(
    model.nodes.map((node) => [
      node.id,
      graph.querySelector(`[data-node="${node.id}"]`),
    ])
  );
  const edgeElements = model.edges.map((_, index) =>
    graph.querySelector(`path[data-edge-index="${index}"]`)
  );
  const revealNode = (id) => {
    const box = nodes.get(id).getBoundingClientRect();
    const viewport = graph.getBoundingClientRect();
    if (box.left < viewport.left + 8 || box.right > viewport.right - 8) {
      graph.scrollLeft +=
        (box.left + box.right - viewport.left - viewport.right) / 2;
    }
  };
  const buttons = new Map();
  const show = (id) => {
    const node = byId.get(id);
    setText("detail-kind", kinds[node.kind]);
    setText("detail-title", node.label);
    setText("detail-summary", node.summary);
    const transitions = model.edges.filter((edge) => edge.from === id);
    element("transitions").replaceChildren(
      ...transitions.map((edge) => {
        const li = document.createElement("li");
        const condition = document.createElement("span");
        condition.textContent = `${edge.label || "次へ"}：`;
        const next = document.createElement("button");
        next.type = "button";
        next.textContent = byId.get(edge.to).label;
        next.addEventListener("click", () => {
          show(edge.to);
          element("detail-title").focus();
        });
        li.append(condition, next);
        return li;
      })
    );
    element("transitions-section").hidden = transitions.length === 0;
    setText("source-location", node.source_label || "");
    setText("source-code", node.excerpt || "");
    element("source-detail").hidden = !node.source;
    element("source-detail").open = false;
    element("notes-detail").open = false;
    element("notes").replaceChildren(
      ...(node.notes || []).map((note) => {
        const li = document.createElement("li");
        li.textContent = note;
        return li;
      })
    );
    element("notes-detail").hidden = !node.notes?.length;
    for (const [key, svgNode] of nodes) {
      svgNode.classList.toggle("selected", key === id);
      svgNode.setAttribute("aria-pressed", String(key === id));
      buttons.get(key).setAttribute("aria-pressed", String(key === id));
    }
    element("detail").dataset.node = id;
    revealNode(id);
  };
  for (const node of model.nodes) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = node.label;
    button.dataset.node = node.id;
    button.addEventListener("click", () => show(node.id));
    element("steps").append(button);
    buttons.set(node.id, button);
    const svgNode = nodes.get(node.id);
    svgNode.setAttribute("role", "button");
    svgNode.setAttribute("tabindex", "0");
    svgNode.setAttribute("aria-label", `${node.label}の詳細`);
    svgNode.addEventListener("click", () => show(node.id));
    svgNode.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        show(node.id);
      }
    });
  }
  for (const [index, path] of model.paths.entries()) {
    const option = document.createElement("option");
    option.value = String(index);
    option.textContent = path.label;
    element("path").append(option);
  }
  element("path").addEventListener("change", (event) => {
    const selected =
      event.target.value === ""
        ? null
        : model.paths[Number(event.target.value)];
    const indexes = new Set(selected?.edges || []);
    const activeNodes = new Set();
    for (const index of indexes) {
      activeNodes.add(model.edges[index].from);
      activeNodes.add(model.edges[index].to);
    }
    for (const [id, svgNode] of nodes) {
      svgNode.classList.toggle(
        "dimmed",
        selected !== null && !activeNodes.has(id)
      );
    }
    for (const [index, edge] of edgeElements.entries()) {
      edge.classList.toggle("on-path", indexes.has(index));
      edge.classList.toggle("dimmed", selected !== null && !indexes.has(index));
    }
    setText(
      "path-description",
      selected
        ? selected.description || selected.label
        : "コードから読み取れる経路です。実行ログではありません。"
    );
  });
  for (const text of model.limitations || []) {
    const li = document.createElement("li");
    li.textContent = text;
    element("limits").append(li);
  }
  element("limits-section").hidden = !model.limitations?.length;
  setText("summary", model.summary);
  setText("entry", model.entry);
  setText("generated", `生成日時 ${model.generated_at} · ソース読取時点の説明`);
  show(model.start);
  window.addEventListener("resize", () =>
    revealNode(element("detail").dataset.node)
  );
})();
