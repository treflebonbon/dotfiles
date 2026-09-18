---
name: domain-modeling-studio
description: Collaboratively model an existing codebase with a human using an editable offline HTML domain diagram. Use for code-grounded domain modeling, reviewing current versus proposed business flows, or incorporating diagram feedback into a glossary, BDD drafts, and implementation candidates. Not a generic architecture diagram or an implementation workflow.
---

# Domain Modeling Studio

Investigate the code; let the human correct the model. Deliver an editable, offline HTML review workspace and keep verified behavior separate from proposed business rules.

## Establish the evidence

Use the named repository and a bounded business flow. If only a repository is given, inspect its glossary, entry points, domain code, and tests, then recommend a small complete flow. Ask only for decisions the code cannot settle. Honor that repository's worktree and document ownership rules.

Pin the source commit with its complete 40- or 64-character hexadecimal Git ID. Identify local uncommitted changes explicitly when they affect the evidence. Read each cited implementation and its relevant callers/tests; a filename or function name alone is not evidence of behavior. Existing domain terms take precedence over synonyms. Keep credentials, invitation secrets, real customer data, and unrelated source out of the model.

Read [the model contract](references/model.md), then create a session-owned JSON file in the task's scratch directory. Build the current flow with file/symbol/revision evidence on nodes and relationships. Mark deductions `inference`; use `code` only where implementation was inspected. Tests read are evidence about intended checks, not proof that those checks ran. Missing events or aggregate boundaries remain explicit hypotheses rather than invented implementation facts.

Initialize `proposed` from `current`. Incorporate requested changes there, with stable IDs, change reasons and unresolved questions. A human's desired rule is `agreement` or `proposal`, never proof of current code. Populate all four deliverables: model/evidence, glossary, Gherkin drafts, and implementation candidates. Gherkin must follow the actual conditions and paths investigated, including known exceptions; never pair arbitrary first nodes into a scenario. Once architecture or function-flow nodes exist in the model, revisit all four deliverables so they reflect those layers too, not only the business flow.

## Generate the function-flow layer

Build a function-flow layer node only from the actual implementation; a function or file name is not evidence of its control flow. Assign `kind` per [ROP semantics](references/rop-semantics.md): `STAGE` for a success-only continuation; `FAILURE_HANDLER` for an operation that receives a failure and stays a failure (`mapError`/`map_err` and similar conversions); `RECOVERY` for an operation that can turn a matching failure back into success, drawing both its recovery-success and recovery-failure outcomes; `BYPASS` for a failure that reaches an in-scope handler without matching it; `TERMINATION` for a path's end; `OUTSIDE_TYPED_ERROR` for defects, interruptions, panics, or syntax the typed-error model does not cover. A bypass with no dispatching source line (e.g. an unmatched `catchTag`) is synthetic: `origin: inference`, no evidence. A bypass that is itself an executed non-recovering arm (e.g. Rust's `other => Err(other)`) is real source: `origin: code`, with evidence. Set each function-flow node's `drillInto` to the business-flow node it implements or affects.

For TypeScript Effect code, first collect syntax evidence with the migrated ast-grep helper: `python3 <skill-dir>/scripts/extract-typescript.py` (see [TypeScript syntax evidence](references/typescript-evidence.md) and [Effect semantics](references/effect-ts.md)). This step needs Python 3 and `ast-grep` from the shared devShell — a dependency the rest of this skill does not have: the generator below needs only Node, and the delivered review HTML it produces needs no runtime at all. Record the helper's `status`: `ok` means the returned nodes are syntax evidence to check against source (an empty `nodes` array only means the scan found none of the selected constructs, never a failure); `unavailable` (ast-grep missing) or `failed` (extraction could not be completed or verified) mean the helper produced no usable evidence — continue building the node from source reading rather than leaving it unmodeled or treating the empty result as a failure. There is no separate schema field for this: the helper's own output (`evidence.json`, kept alongside the session model per [TypeScript syntax evidence](references/typescript-evidence.md)) is the record of `status`/`reason`; if `unavailable`/`failed` leaves a node's control flow unconfirmed from source reading alone, add an entry to the document's `unresolved` array naming the concrete reason, rather than modeling it as if source reading had settled it.

For Rust and other languages without a migrated extraction helper, build the function-flow layer from source reading only, using [Rust Result semantics](references/rust.md) (or the closest source-reading discipline for that language) — the same procedure `rop-visualizer` used before its retirement into this skill.

Fold what these layers establish into the four deliverables: add glossary terms confirmed while naming a module or a function's control flow; ground Gherkin scenarios only in conditions and branches actually confirmed in the function-flow layer, including known exceptions such as a bypass or a scoped recovery, and never synthesize an untested combination; cite the affected module and function as evidence on any implementation change candidate an architecture or function-flow finding motivates; and keep the model page's evidence, change reasons and unresolved questions naming architecture and function-flow findings alongside business-flow ones.

## Generate and review

Run with Node (runtime has no npm dependencies):

```sh
node <skill-dir>/scripts/render.mjs <session-model.json> <new-review.html> <new-artifacts-directory>
```

The generator validates the input and uses the committed, self-contained template. Use new output names for revisions; it refuses to overwrite files. Inspect validation failures and fix the model rather than weakening validation. Read the generated artifacts for consistency with the source and requested flow.

Use `playwright-cli` in a session-specific browser to open the HTML for interactive work. If `file:` navigation is blocked, serve only this session's generated HTML from a private document root on `127.0.0.1`, in a managed terminal. Verify both the local HTTP response and browser session/revision. Preserve other browser consumers. If a visible browser is unavailable, provide the file link and state that limitation. Opening/serving is a viewing aid: the delivered HTML needs neither server nor network. Stop session-owned viewing services when the modeling interview finishes.

Link the HTML. Ask the human to review, directly edit the proposed model, add comments, and paste **指摘・モデルをコピー** into chat. The current model accepts layout adjustments; corrections to its business content are comments for code re-investigation. The diagram's handles and inspector support edits; the inspector offers keyboard alternatives. Diagram and comment edits are undoable. Dictionary/BDD/change-candidate corrections go through feedback, then the agent regenerates them from the reviewed model.

## Incorporate submitted feedback

A browser draft or successful clipboard write is not a submitted answer. Use the actual chat payload `domain-studio-feedback-v1`; check its session, document revision, repository revision, and `exportId` against the active round before acting. Stale or conflicting payloads require reconciliation with the human.

Re-investigate each correction against the source. Keep the human's layout, stable IDs, surviving metadata and comments. Preserve removed nodes/edges in `retired`, including incident edges, so their comments remain attributable. Do not regenerate IDs from labels or silently drop unresolved feedback. Keep each prior unresolved question verbatim, or record its exact text, resolution reason and evidence in `resolutions` (see the model contract); carry earlier resolution records forward. Keep the repository commit pinned for the round-trip. A requested source rebase requires explicit agreement and a separate session after preserving the old records, not an automatic update. If semantics change, reconsider associated glossary entries, scenarios and implementation candidates.

Emit a new revision with `basedOn: { revision: <submitted revision>, exportId: <submitted exportId> }`. Preserve `revisionHistory` and append the submitted revision; never reuse a past revision. Carry the submitted edits forward, explain accepted/rejected/unresolved changes, and reset `needsReview` only after reviewing all derived artifacts. The human imports the new plain model JSON using **JSONを読み込む**, or opens the new HTML. Unsent changes, reused revision IDs, and missing review records are protected; ask for a fresh submitted export rather than bypassing the conflict guard. If re-investigation supersedes a human semantic edit, provide the matching target, field, before/after values, reason and evidence in `editResolutions` (model contract), retaining earlier entries. Imports retain earlier evidence, comments and retired records, and preserve human-adjusted geometry. Explain contradictory citations in unresolved notes instead of silently erasing them.

The **JSONを保存** backup preserves the current document, including a comment still being typed. Copy and import also incorporate that pending comment before checking the update baseline. Loading a backup explicitly asks the human to download the current contents before restoring. Neither a backup nor a draft is permission to accept a proposed business rule.

## Finish the modeling session

Confirm the agreed model and remaining unknowns. Use `domain-modeling` to integrate only agreed vocabulary into the target repository's existing `CONTEXT.md` (or context-specific glossary); follow its ADR criteria. Create the four artifacts in a session-owned directory with the generator. Present scenarios as drafts with current/proposed and confirmed/draft status, and separate code-reading evidence from test execution results.

Report the source revision, resulting files, unresolved questions, and checks actually performed. Implementation candidates remain a separate implementation task. Retain the agreed records; clean up only session-owned temporary files with the user's authorization. No automatic code changes, issue creation, or deployment follow from a modeling review.

## Maintaining the editor

The standalone template and notices in `dist/` ship with the skill. `src/` is the editable source. `node scripts/build.mjs` uses the pinned package lock in a fresh temporary directory, leaving npm dependencies outside the chezmoi-deployed tree. Rebuild the template after source changes. Run `node --test tests/*.test.mjs` (model and architecture-generation coverage) and the browser workflow in `tests/browser.mjs` (its environment requirements are at the top). Verify offline `file:` loading, actual edits/undo/restore, clipboard failure and baseline conflicts before replacing the template. The browser test fixture is deliberately fictional; private pilot data belongs in the target task's scratch directory.
