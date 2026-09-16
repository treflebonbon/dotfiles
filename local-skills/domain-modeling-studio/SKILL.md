---
name: domain-modeling-studio
description: Collaboratively model an existing codebase with a human using an editable offline HTML domain diagram. Use for code-grounded domain modeling, reviewing current versus proposed business flows, or incorporating diagram feedback into a glossary, BDD drafts, and implementation candidates. Not a generic architecture diagram or an implementation workflow.
---

# Domain Modeling Studio

Investigate the code; let the human correct the model. Deliver an editable, offline HTML review workspace and keep verified behavior separate from proposed business rules.

## Establish the evidence

Use the named repository and a bounded business flow. If only a repository is given, inspect its glossary, entry points, domain code, and tests, then recommend a small complete flow. Ask only for decisions the code cannot settle. Honor that repository's worktree and document ownership rules.

Pin the source commit. Identify local uncommitted changes explicitly when they affect the evidence. Read each cited implementation and its relevant callers/tests; a filename or function name alone is not evidence of behavior. Existing domain terms take precedence over synonyms. Keep credentials, invitation secrets, real customer data, and unrelated source out of the model.

Read [the model contract](references/model.md), then create a session-owned JSON file in the task's scratch directory. Build the current flow with file/symbol/revision evidence on nodes and relationships. Mark deductions `inference`; use `code` only where implementation was inspected. Tests read are evidence about intended checks, not proof that those checks ran. Missing events or aggregate boundaries remain explicit hypotheses rather than invented implementation facts.

Initialize `proposed` from `current`. Incorporate requested changes there, with stable IDs, change reasons and unresolved questions. A human's desired rule is `agreement` or `proposal`, never proof of current code. Populate all four deliverables: model/evidence, glossary, Gherkin drafts, and implementation candidates. Gherkin must follow the actual conditions and paths investigated, including known exceptions; never pair arbitrary first nodes into a scenario.

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

Re-investigate each correction against the source. Keep the human's layout, stable IDs, surviving metadata and comments. Preserve removed nodes/edges in `retired`, including incident edges, so their comments remain attributable. Do not regenerate IDs from labels or silently drop unresolved feedback. If semantics change, reconsider associated glossary entries, scenarios and implementation candidates.

Emit a new revision with `basedOn: { revision: <submitted revision>, exportId: <submitted exportId> }`. Carry the submitted edits forward, explain accepted/rejected/unresolved changes, and reset `needsReview` only after reviewing all derived artifacts. The human imports the new plain model JSON using **JSONを読み込む**, or opens the new HTML. Unsent changes or a mismatched baseline are protected; ask for a fresh submitted export rather than bypassing the conflict guard.

The **JSONを保存** backup preserves the current document. Loading a backup explicitly asks the human to download the current contents before restoring. Neither a backup nor a draft is permission to accept a proposed business rule.

## Finish the modeling session

Confirm the agreed model and remaining unknowns. Use `domain-modeling` to integrate only agreed vocabulary into the target repository's existing `CONTEXT.md` (or context-specific glossary); follow its ADR criteria. Create the four artifacts in a session-owned directory with the generator. Present scenarios as drafts with current/proposed and confirmed/draft status, and separate code-reading evidence from test execution results.

Report the source revision, resulting files, unresolved questions, and checks actually performed. Implementation candidates remain a separate implementation task. Retain the agreed records; clean up only session-owned temporary files with the user's authorization. No automatic code changes, issue creation, or deployment follow from a modeling review.

## Maintaining the editor

The standalone template and notices in `dist/` ship with the skill. `src/` is the editable source. `node scripts/build.mjs` uses the pinned package lock in a fresh temporary directory, leaving npm dependencies outside the chezmoi-deployed tree. Rebuild the template after source changes. Run `node --test tests/model.test.mjs` and the browser workflow in `tests/browser.mjs` (its environment requirements are at the top). Verify offline `file:` loading, actual edits/undo/restore, clipboard failure and baseline conflicts before replacing the template. The browser test fixture is deliberately fictional; private pilot data belongs in the target task's scratch directory.
