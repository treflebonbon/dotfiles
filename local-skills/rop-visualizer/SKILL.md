---
name: rop-visualizer
description: "Visualize existing TypeScript Effect or Rust Result code as an interactive HTML Mermaid flowchart for understanding and review. Use when asked to visualize ROP, trace success/error/recovery paths, or explain an implementation's railway flow. For changes to error-handling code itself, use rop instead."
---

# ROP visualizer

Turn an entry function and its relevant callees into a readable flowchart report.
The reader should see what runs next, what gets skipped, and where recovery
rejoins the successful path. Explain the existing implementation; keep its code
unchanged. The report describes possible paths inferred from source, not an
observed execution or an exhaustive proof.

## 1. Read the implementation

Locate the requested entry function. A file with one clear entry needs no
question; if several unrelated entries remain plausible, ask which to trace.
Inspect the repository instructions, language/dependency versions, enclosing
error types, and the called functions needed to explain propagation and recovery.
Read the relevant semantics reference:

- TypeScript Effect: [references/effect-ts.md](references/effect-ts.md)
- Rust Result: [references/rust.md](references/rust.md)

Record the input/output, failure types, branches, handler scopes, and source
locations. Follow local callees until those facts are supported. At unavailable
implementations, show a named unknown boundary and explain what the signature
does and does not establish. Derive technical facts from code; ask the user only
about scope that cannot be resolved there. Do not execute the target program to
discover its behavior.

## 2. Model the flow

Write `flow.json` using [references/report-format.md](references/report-format.md).
Start with a short Japanese purpose statement and roughly 4–7 meaningful stages
on the main path. Use business actions as node labels; keep operator names,
full types, code excerpts, and review notes in the details below the diagram.
Keep labels to a short action (roughly 4–8 Japanese characters); put full function
and error names in the summary/notes. Edge conditions appear in the selected
node's transition list, leaving the diagram's connectors free of text. Fold entry
wrappers and pure plumbing into adjacent stage details when their meaning fits
there. Preserve distinct branch/handler scopes even when shortening the overview.

The graph must preserve control flow, including the edges—not merely describe
the correct semantics in prose while drawing contradictory arrows:

- **Bind** runs its operation only for success. Failure skips later success-only
  stages and reaches the handler or return belonging to its actual scope.
- **Map error** changes an error and remains a failure.
- **Recovery** receives only errors within its scope and matching its condition.
  Draw both recovery success and recovery failure; mark unmatched errors.
- **Bypass** is propagation, not an extra function call. Label synthetic bypass
  nodes as such, with no invented source line.
- **Termination** ends that path. Early returns must not flow into later code in
  the same function. A caller may handle the returned error in a separate stage.
- **Outside typed errors** includes explicitly relevant defects, interruptions,
  panics, or unsupported constructs. Use the outside category and a bounded
  explanation instead of forcing these into a typed-error branch.

Distinguish fallible work from pure transformations, including fallible taps.
Keep handler scope visible when grouping operations. Summarize long pure spans;
split a large entry into a linked companion report when grouping would conceal
an important branch. Represent parallel work as a named grouped operation with
its actual join/failure policy in the details, rather than inventing a serial
order. State unmodeled paths in `limitations`.

Add a small set of feasible named paths: ordinary success, a failure that skips
later work, and a recovery outcome when present. Trace each edge list from the
entry to a terminal against source, including branch conditions. Do not offer
arbitrary per-node failure toggles: those can combine incompatible outcomes.

## 3. Generate the HTML

Use the bundled renderer; its interface and command are in
[references/report-format.md](references/report-format.md). It generates Mermaid
`flowchart TB` and renders the graph to SVG using an existing Playwright CLI
session. It embeds Mermaid's native layout with small local interactions in one
HTML file. Flow runs from top to bottom; success, failure, and recovery have
distinct colors rather than fixed rows.
Generation downloads pinned Mermaid code; opening the resulting HTML needs no
server, CDN, or network. Preserve the adjacent `flow.json` and `.mmd` as reviewable
source artifacts.

Use the environment's browser skill to open or select an authorized browser
session. Pass its name with `--session`. The renderer uses a transient tab and
leaves existing tabs intact. Close only a session you opened for this work, after
verification; respect any runtime-specific shared-browser ownership rules.
If browser rendering is unavailable, retain the model and generated Mermaid
source and report the concrete rendering failure. Do not claim a finished HTML.

Unless a destination was requested, place the report and its source artifacts in
`tmp/rop-<entry-slug>/` in the current validated task worktree. Avoid overwriting
an unrelated report; use a distinct slug when needed.

## 4. Check the report

Check graph edges against the actual source again, especially nested handlers,
early returns, error conversions, and failed recovery. Every source reference
must exist and support the node's claim. Separate facts from review questions.

Open the generated HTML with the browser skill and verify:

1. The flowchart reads from top to bottom. Check the rendered geometry: node
   labels do not overlap each other, connectors meet their actual endpoints and
   do not cross text or unrelated processing boxes. Named paths follow their
   exact model edges. At a desktop width, keep the branching overview visible
   without horizontal scrolling; shorten labels and summarize redundant stages
   when needed. Preserve readable text instead of shrinking a large graph to fit.
2. Selecting a node by click or keyboard changes the matching detail section;
   its source excerpt and optional notes can be opened. Every outgoing edge's
   condition and destination appear in the transition list, including recovery
   failures and unmatched errors. Destination buttons select the correct node.
3. Selecting a named path highlights exactly its edges and nodes; resetting it
   restores the entire graph. Node selection does not change the selected path.
4. The report works with network requests blocked and remains usable in a narrow
   viewport. The diagram may scroll horizontally; prose and controls must fit.

Use DOM geometry and interaction checks, then inspect a desktop and narrow-view
capture for spacing and line crossings. A style detector passing does not establish
that a diagram is readable.
Report the HTML path, the entry/scope, verification results, and concrete unknowns.
Do not present review questions as confirmed bugs or claim reduced human cognitive
load from an agent's timing alone.
