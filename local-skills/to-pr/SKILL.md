---
name: to-pr
description: "Turn finished work into a pull request. Embeds the acceptance-criteria contract and a verification matrix covering every criterion (browser-observable or not) into the PR body, plus a code-review status note. Use after implementation work when the user invokes /to-pr, or when the user explicitly authorized AFK/autonomous completion; otherwise do not invoke it automatically."
---

# to-pr

Publish completed work as a pull request for human review. This closes the
gap left after implementation (`/implement` stops at commit-to-branch): it opens the
PR with a **contract** (what this change was supposed to do) and a **verification
matrix** (what was actually checked, for every acceptance criterion — not just
browser-observable ones) folded into the PR body.

Keep the flow light: no evidence schemas, no verdict gates, no required traces/videos.
Non-UI acceptance criteria are recorded, not newly executed — verifying them is assumed
done by the implementation work (e.g. `/implement` and its `/tdd` cycle) that precedes this skill.

## 1. Establish the context

- Determine the base ref and the current branch. If the branch is not pushed, that is
  handled in step 5.
- Find the acceptance criteria: from the linked issue (`gh issue view`), the PRD, or the
  conversation. If there are none, summarise what the change does instead.
- Extract the **contract**: 目的 (purpose) / AC / 非目標 (non-goals) / 検証方法
  (verification method) / 関連ファイル・入口 (related files/entry points) / 判断済み
  tradeoff (decided tradeoffs). Source it from the linked issue body when there is one
  (issues carrying the `ready-for-agent` label are expected to state these six fields —
  see `runtime/skill-harness.md`); otherwise extract it from the conversation. Mark any
  field that was never discussed as `未記載` rather than omitting it or inventing content.
- Resolve the linked issue's **Ticket Hierarchy** before drafting the PR:
  1. Read the linked issue with
     `gh issue view <issue> --json number,state,body,parent`.
  2. If it has a native parent, read that issue with
     `gh issue view <parent> --json number,state,body,subIssues,subIssuesSummary`.
     GitHub native sub-issues are the source of truth; cross-check it against the ticket
     body's `## Parent`. If the hierarchy cannot be fetched or the two parent references
     are missing or disagree, do not infer a parent.
  3. Consider only the parent's direct children. Do not recurse to a grandparent.
  4. Read every open direct child with
     `gh issue view <child> --json number,state,body`. Include each child Acceptance
     Criterion that this PR covers in the Contract and identify its ticket number.
  5. Once the final PR is created, freeze this Ticket Hierarchy until merge. Put scope
     found during review under a separate parent issue instead of adding or reparenting
     children in this hierarchy.

## 2. Build the verification matrix

Every acceptance criterion gets one row, regardless of type — there is no separate
"non-UI, skip verification" path anymore. Columns: `AC` / `種別` (UI, CLI, API, infra)
/ `実行コマンドまたは理由` / `結果` / `未確認理由`.

- **UI criteria** (something you can see or exercise in a browser — a page, a URL, a UI
  behaviour, a rendered output): verify with `playwright-cli`, per the procedure below.
- **CLI / API / infra criteria**: do not execute new verification commands. Cite
  existing evidence in the `実行コマンドまたは理由` column instead — a test file added
  during `/implement` / the `/tdd` cycle (with its commit hash), a `lefthook` pre-commit run
  (typecheck/lint/etc.), or another already-produced artifact. If no such evidence
  exists, mark `結果` as `未確認` and state why in `未確認理由`. This keeps the matrix
  honest without turning `to-pr` into a second test runner.
- Assign `結果` one of: `確認済み` (observed working, or evidence found) / `未確認`
  (could not be exercised or no evidence exists) / `要人間確認` (ambiguous; needs a
  human to judge).

For a direct child, **Ticket Coverage** means that every Acceptance Criterion from that
child appears in the Contract and has a row in the Verification Matrix. The row results
(`確認済み`, `未確認`, or `要人間確認`) record verification status. These result values do
not affect Ticket Coverage. An issue-number or commit reference alone is not coverage.

### UI verification procedure

Use the `playwright-cli` skill for all browser interaction, with two exceptions:

- **Criteria needing the user's real logged-in session** (no seeded fixture — a real
  account, real data, or a real payment/irreversible action): playwright-cli's context
  has no login. If the runtime provides a way to drive the user's own logged-in browser
  (e.g. Claude Code's `claude-in-chrome` skill), use that instead — and ask the user
  first if its site permission hasn't been granted, rather than silently verifying
  against playwright-cli's anonymous context. If no such path exists in this runtime, do
  not attempt it — mark the criterion `要人間確認` and ask the user to check it
  themselves. If driving the criterion would itself perform a real, costly, or
  hard-to-reverse action (e.g. an actual payment), ask before that specific step — the
  same bar as asking before `git push`.
- **This machine may run other Orca workspaces/agents concurrently.** Give playwright-cli
  a workspace-scoped session name (`-s=<branch-or-workspace-name>`) — never the shared
  `default` session, and never `close-all` / `kill-all`. Before starting a dev server, do
  one check: is the port already bound, and if so does the owning process's `cwd` match
  your own worktree? If it does not, stop there (do not investigate further or try to
  resolve the conflict) — mark the criterion `未確認` noting the port conflict and move
  on.

Before browser verification, create a fresh evidence bundle with
`TO_PR_EVIDENCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/to-pr-evidence.XXXXXX")"`. Keep all
Playwright evidence in this directory; do not put it in the repository. Run every
Playwright CLI command from the bundle so its default `.playwright-cli/` snapshots and
logs also stay there:

```bash
(cd "$TO_PR_EVIDENCE_DIR" && playwright-cli -s=<branch-or-workspace-name> ...)
```

Do not run `playwright-cli` from the repository worktree. Resolve repository-relative
input paths to absolute paths before entering the evidence-directory subshell. The
bundle contains:

- Exactly one representative `screenshot` for every UI criterion that was exercised.
  Use a criterion-oriented filename rather than a generic sequence number. If a
  criterion cannot be exercised, record the reason instead of fabricating an image.
- `playwright-report.md`, with one entry per UI criterion: the operation performed, the
  observed result, the URL, and a summary of console/network errors. Record `none` when
  no errors were observed.

Initialize `playwright-report.md` as soon as the bundle is created so unexercised UI
criteria and their reasons are preserved too.

Do not include authentication details, cookies, tokens, headers, or raw requests in the
report or screenshots. Redact sensitive user data that is not needed to establish the
criterion.

1. Start the dev server if the repo defines one: `package.json` `scripts.dev`
   (`npm run dev` / `bun dev`), or a `dev` target in the `Makefile` (`make dev`). If no
   dev command exists, do not verify — mark the UI criteria `未確認` and note why.
2. For each UI criterion that can be exercised: open the relevant URL, drive the flow,
   take a `snapshot`, and save one representative `screenshot` to the evidence bundle.
   Check the console and network for errors, then append the criterion's result to
   `playwright-report.md`. For timing- or count-sensitive criteria, measure inside a
   single `run-code` script rather than chaining separate CLI calls (each call's own
   round-trip can itself exceed the window you're measuring), e.g.:

   <!-- prettier-ignore -->
   ```js
   async (page) => {
     await page.getByRole("button", { name: "<trigger>" }).click();
     const t0 = Date.now();
     await page.getByText("<criterion text>").waitFor({ state: "visible" });
     await page.getByText("<criterion text>").waitFor({ state: "hidden" });
     return Date.now() - t0;
   }
   ```

   Count-sensitive criteria (e.g. "exactly N items appear") follow the same pattern —
   read the count inside the same script, after the triggering action, rather than
   `snapshot`-ing before and after in separate CLI calls:

   <!-- prettier-ignore -->
   ```js
   async (page) => {
     await page.getByRole("button", { name: "<trigger>" }).click();
     return await page.getByRole("<item-role>").count();
   }
   ```

Do not fail-close or gate on screenshots. Record what you saw and move on.

## 3. Record code-review status

Check the conversation/session for evidence that `code-review` ran: its summary output,
a verdict, or a note that blocking findings were fixed. Record one line in the PR body —
either the outcome (e.g. "実施済み、ブロッキング指摘なし") or `未実施` if no evidence is
found. Either way, **do not block PR creation on this** — it is a record, not a gate
(consistent with this skill never using verdict gates).

## 4. Reconcile the direct parent

Use the Ticket Hierarchy snapshot and Ticket Coverage from steps 1–2 to prepare the PR
body's `## Parent Reconciliation` section:

- If there is no linked issue, record `対象なし` and omit all `Fixes` lines.
- If the linked issue has no native parent, record `対象なし`, state the reason, and
  preserve the ordinary `Fixes #N` line for the linked issue.
- If the native hierarchy fetch or `## Parent` cross-check failed, record `未実施`,
  explain the failure, preserve the ordinary `Fixes #N` line for the linked issue, omit
  the parent `Fixes` line and continue creating the PR.
- Otherwise, treat an already-closed direct child as complete and an open direct child
  as complete only when it has Ticket Coverage. The **親完了条件** is satisfied only
  when every direct child is complete.
- When the 親完了条件 is satisfied, record `確認済み`. Add one `Fixes #N` line for
  every open, covered direct child and one more for the direct parent. Omit already-closed
  children from the closing keywords.
- When any open direct child lacks Ticket Coverage, record `未実施`, identify the
  uncovered child and its missing criteria, and omit the parent `Fixes` line and continue
  creating the PR. Preserve the ordinary closing reference for the linked issue, but do
  not add closing references for sibling tickets.

In all cases, the section records exactly one state — `確認済み`, `未実施`, or `対象なし`
— plus the reason and the complete list of issues that the PR's closing keywords will
close on merge. This reconciliation is one level only and never mutates issue hierarchy,
labels, or state through the API; GitHub closes the listed issues only when the PR merges.
Keep state labels unchanged when GitHub closes an issue.

## 5. Self-check before opening the PR

Before creating the PR, do a quick pass over what steps 2–4 produced: is the code-review
status accidentally left as `未実施` without actually having looked for evidence? Is
there an acceptance criterion with no row in the verification matrix? Does Parent
Reconciliation list every and only the issues named by `Fixes` lines? Fix what you find;
otherwise proceed. This is a lightweight inline check, not an invocation of the
`harness-feedback` skill — `harness-feedback`'s auto mode is designed to skip the
currently active session, so chaining it from here would not analyse anything useful.
`harness-feedback` remains a separate, manually-triggered practice for a later session.

## 6. Open the PR

1. Determine whether the branch needs to be pushed and whether the evidence bundle has
   images to attach. Ask once for explicit confirmation covering all outward-facing
   actions that apply: pushing the branch, creating the PR, and uploading the images.
   Include the exact list of child and parent issues that will close on merge, grouped by
   role; if no parent will close, say so. Do not split these into separate confirmation
   prompts.
2. Write the PR body to a **fresh** temp file (use `mktemp` or a branch-scoped name —
   a fixed name like `pr-body.md` collides with stale content from previous runs). Write
   it in the language of the conversation / repo. Canonical structure:
   - A short change summary.
   - `## Contract` — the six fields from step 1, verbatim (including any `未記載`).
   - `## Verification Matrix` — the table built in step 2.
   - `## Playwright Evidence` — for each UI criterion, copy the operation, observed
     result, URL, and console/network errors summary from `playwright-report.md`. Add an
     image placeholder for every exercised UI criterion. For an unexercised criterion,
     state the reason and `画像なし`; use `対象なし` only when there are no UI criteria.
   - `## Parent Reconciliation` — the state, reason, and exact merge-time close targets
     from step 4.
   - `## Code Review` — the one line from step 3.
     Add only the `Fixes #N` lines selected in step 4. When there is no issue, omit all
     `Fixes` lines and mention where the contract came from (conversation, PRD) in the
     summary instead.
3. After confirmation, push the branch if needed and create the PR:

   ```bash
   gh pr create --title "<conventional title>" --body-file <tmp>
   ```

## 7. Attach Playwright evidence

If the bundle has representative images, try to attach them after the PR exists:

1. Use a browser exposed by the current runtime only when it already has an authenticated
   GitHub session. Do not ask the user to log in, import browser state, or let `to-pr`
   create or save authentication. On WSL2, do not assume that a Windows Chrome session
   or profile is available: automatic attachment is allowed only when Chrome running in
   WSL2 already has an authenticated GitHub session.
2. Open the PR body editor in that browser, attach each representative image, and read
   the anonymized URL that GitHub inserts into the editor. Do not submit the browser's
   stale copy of the PR body.
3. Replace the corresponding placeholders in the fresh body file with Markdown image
   links using those anonymized URLs, then update the PR with:

   ```bash
   gh pr edit --body-file <tmp>
   ```

If no authenticated browser is available, browser control is unavailable, or any upload
fails, do not retry by logging in and do not commit the images. Replace the affected
image placeholders with `手動添付待ち`, update the PR body with `gh pr edit --body-file`,
and hand the evidence bundle to the user. The completion report must include the bundle's
absolute path and a file list so the user can attach the images manually.

## Out of scope

Wiki / ADR generation, change-effect graphs, auto-merge, recursive or grandparent
reconciliation, issue-hierarchy mutation, state-label cleanup, verdict gates, evidence
JSON schemas, and mandatory trace/video capture. Post-merge issue mutation or automation
is also out of scope.
Also out of scope: running tests or any non-browser AC verification — that is assumed
done by the implementation work (e.g. `/implement` and its `/tdd` cycle) that precedes this skill.
Also out of scope: invoking `harness-feedback` from this skill. The PR body's Contract /
Verification Matrix / Code Review sections are Markdown for a human reviewer and for
this skill's own step-4 self-check — they are not consumed by `harness-feedback`'s
artifact-driven enrichment (`contract.json` / `review.json` / `active-eval.json`), which
remains transcript-only analysis run separately.
This skill opens a PR with an honest, lightweight verification note — nothing more.
