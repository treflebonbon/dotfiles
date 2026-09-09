# Report model and renderer

Write one JSON object to `flow.json`. Keep paths relative to the repository root.
The renderer reads the referenced lines itself, so quote real locations rather
than transcribing or fabricating code excerpts.

```json
{
  "title": "会員を登録する",
  "entry": "src/users.ts:createUser",
  "summary": "入力を検証し、会員を保存する。",
  "start": "VALIDATE",
  "nodes": [
    {
      "id": "VALIDATE",
      "label": "入力を検証",
      "lane": "success",
      "kind": "work",
      "summary": "成功した入力だけを保存へ渡す。検証失敗は呼び出し元へ返す。",
      "source": { "path": "src/users.ts", "start": 10, "end": 15 },
      "notes": []
    },
    {
      "id": "SAVE",
      "label": "会員を保存",
      "lane": "success",
      "kind": "work",
      "summary": "保存に成功した会員を返す。DB エラーは呼び出し元へ返す。",
      "source": { "path": "src/users.ts", "start": 16, "end": 20 }
    },
    {
      "id": "OK",
      "label": "会員を返す",
      "lane": "success",
      "kind": "terminal",
      "summary": "成功結果として会員を返す。"
    },
    {
      "id": "ERR",
      "label": "エラーを返す",
      "lane": "error",
      "kind": "terminal",
      "summary": "失敗結果を呼び出し元へ返す。後続の成功処理は実行しない。"
    }
  ],
  "edges": [
    { "from": "VALIDATE", "to": "SAVE", "label": "成功" },
    { "from": "SAVE", "to": "OK", "label": "成功" },
    { "from": "VALIDATE", "to": "ERR", "label": "検証失敗" },
    { "from": "SAVE", "to": "ERR", "label": "保存失敗" }
  ],
  "paths": [
    {
      "label": "通常の成功",
      "description": "検証・保存ともに成功する。",
      "edges": [0, 1]
    },
    {
      "label": "検証で失敗",
      "description": "保存は実行されない。",
      "edges": [2]
    }
  ],
  "limitations": []
}
```

Replace example locations and branches with facts from the requested source.

- Node IDs use uppercase letters, digits, and underscores, starting with a
  letter. IDs are unique within the report.
- `lane`: semantic category `success`, `error`, or `outside`. It controls color,
  not position. Mermaid arranges the flowchart from top to bottom using its edges;
  no row or column coordinates are needed.
- `kind`: `work`, `recover`, `bypass`, `terminal`, or `boundary`. A real operation
  or boundary requires a source location. Synthetic propagation/return nodes may
  omit it; explain their synthetic meaning. Assign a recovery operation to the error
  category and connect its successful output to the correct continuation.
- `source`: a repository-relative file path and inclusive 1-based `start`/`end`.
  `notes`: optional strings with nested-scope explanations, dependent services,
  additional source locations, and clearly phrased review questions.
- Edges are directed. Use distinct junction nodes when two semantic branches
  would otherwise share the same from/to pair. Labels state their condition;
  they appear in the node's transition list and SVG tooltips, not on connectors.
- A path's `edges` lists zero-based indexes into `edges` in traversal order.
  Each path starts at `start`, is continuous, and ends at a terminal or an
  explicitly unmodeled boundary. Mechanical continuity does not establish
  feasibility; check branch conditions and handler scopes against source.
- `limitations` names concrete unavailable behavior or intentionally summarized
  complexity. Do not fill it with generic warnings about all possible failures.

## Generate

Open a browser session with the environment's browser skill. From the repository
root, run (replace the absolute skill path, filenames, and session name):

```bash
python3 /absolute/path/to/rop-visualizer/scripts/render.py \
  tmp/rop-create-user/flow.json tmp/rop-create-user/report.html \
  --session rop-visualizer
```

`--repo-root /absolute/repo/path` supports an explicit source root. The session
must already exist; the renderer creates and closes only its own transient tab.
It downloads Mermaid **11.17.2** into that tab at generation time. It does not
install a browser, change global packages, start the target application, or run
the analyzed code. Existing reports and source artifacts are preserved: use a
new output basename for a new attempt.

Outputs beside the HTML:

- `report.mmd`: generated Mermaid source.
- `report.render.js`: the actual Playwright rendering operation, retained for
  diagnosis if rendering fails.

The renderer generates `flowchart TB` with explicit edge IDs (`E0`, `E1`, ...),
then uses Mermaid's native layout. Conditions remain in source comments and the
selected node's transition list. No connector geometry is rewritten after rendering.

The HTML contains that SVG, source excerpts, data, CSS, and small local JavaScript
interactions. It has no external viewing dependencies. Graph nodes have
`#graph [data-node="<model node id>"]`. The details section is `#detail`; its
`data-node` identifies the selected node. The path selector is `#path`, and
highlighted edges have `.on-path` and `data-edge-index` identifies the original
model edge. `#transitions` contains the selected node's outgoing conditions and
destination buttons. These are useful verification selectors.

For an existing render result, `--rendered-json result.json` replaces the browser
step. That JSON must contain the exact Mermaid `{ "svg": "..." }` for this model;
this is useful for deterministic renderer tests, not a substitute drawing. The
renderer verifies node/edge identities and adds interaction metadata and tooltips
without changing the supplied layout.
