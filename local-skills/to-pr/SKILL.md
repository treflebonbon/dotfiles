---
name: to-pr
description: "Turn finished work into a pull request. When the change is browser-observable, verify its acceptance criteria in a real browser and record the result; otherwise open the PR with a written summary. Use after implementation work (e.g. a /tdd cycle) to publish it for review."
disable-model-invocation: true
---

# to-pr

Publish completed work as a pull request for human review. This closes the
gap left after implementation (a `/tdd` cycle stops at commit-to-branch): it opens the
PR and, when the change is browser-observable, verifies the acceptance criteria in a
real browser and folds the result into the PR body.

Browser verification is **conditional**, not the point of the skill — non-UI changes
skip it entirely. Keep the flow light: no evidence schemas, no verdict gates, no
required traces/videos.

## 1. Establish the context

- Determine the base ref and the current branch. If the branch is not pushed, that is
  handled in step 4.
- Find the acceptance criteria: from the linked issue (`gh issue view`), the PRD, or the
  conversation. If there are none, summarise what the change does instead.

## 2. Decide whether the change is browser-observable

A change is browser-observable when an acceptance criterion is about something you can
see or exercise in a browser (a page, a URL, a UI behaviour, a rendered output).

- **Browser-observable → verify (step 3).**
- **Not browser-observable (pure library / CLI / infra / refactor) → skip to step 4**
  and record `対象外(非UI)` for the criteria.

## 3. Verify in the browser (only when step 2 says so)

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

1. Start the dev server if the repo defines one: `package.json` `scripts.dev`
   (`npm run dev` / `bun dev`), or a `dev` target in the `Makefile` (`make dev`). If no
   dev command exists, do not verify — mark the UI criteria `未確認` and note why.
2. For each browser-observable criterion: open the relevant URL, drive the flow, take a
   `snapshot`, and — where it helps a reviewer — a `screenshot`. Check the console and
   network for errors. For timing- or count-sensitive criteria, measure inside a single
   `run-code` script rather than chaining separate CLI calls (each call's own round-trip
   can itself exceed the window you're measuring), e.g.:

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

   ```js
   async (page) => {
     await page.getByRole("button", { name: "<trigger>" }).click();
     return await page.getByRole("<item-role>").count();
   }
   ```

3. Assign each criterion one lightweight label:
   - `確認済み` — observed working
   - `未確認` — could not be exercised (no dev server, blocked path, port conflict)
   - `要人間確認` — ambiguous; needs a human to judge
   - `対象外(非UI)` — not browser-observable

Do not fail-close or gate on screenshots. Record what you saw and move on.

## 4. Open the PR

1. Push the branch if needed (ask before pushing — it is outward-facing).
2. Write the PR body to a **fresh** temp file (use `mktemp` or a branch-scoped name —
   a fixed name like `pr-body.md` collides with stale content from previous runs). Write
   it in the language of the conversation / repo. Canonical format for both cases: a short change
   summary, then the acceptance criteria listed one per line with a label each — the
   step 3 label for verified criteria, or `対象外(非UI)` for every criterion of a
   non-browser-observable change (plus one line noting browser verification was skipped
   as not applicable). Reference the issue it closes (`Fixes #N`) when there is one; when
   there is no issue, omit the `Fixes` line and mention where the acceptance criteria
   came from (conversation, PRD) in the summary instead.
3. Create the PR:

   ```bash
   gh pr create --title "<conventional title>" --body-file <tmp>
   ```

## 5. Screenshots in the PR body (default: none)

By default the PR body carries **text results only** — do not commit images.

Embed screenshots **only when the user explicitly confirms** they should be kept in
history. If confirmed:

1. Commit the images under `.github/pr-assets/<branch>/` (confirm the commit and any
   push first — both are outward-facing).
2. Reference them from the PR body with SHA-pinned raw blob URLs:
   `https://github.com/<owner>/<repo>/blob/<sha>/.github/pr-assets/<branch>/<file>?raw=true`

Keep it to a few representative images. No hero-selection rules, no size gating.

## Out of scope

Wiki / ADR generation, change-effect graphs, epic-branch reconciliation, auto-merge,
closing issues, verdict gates, evidence JSON schemas, mandatory trace/video capture.
Also out of scope: running tests or any non-browser AC verification — that is assumed
done by the implementation work (e.g. the `/tdd` cycle) that precedes this skill.
This skill opens a PR with an honest, lightweight verification note — nothing more.
