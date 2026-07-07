---
name: to-pr
description: "Turn finished work into a pull request. Embeds the acceptance-criteria contract and a verification matrix covering every criterion (browser-observable or not) into the PR body, plus a code-review status note. Use after implementation work (e.g. a /tdd cycle) to publish it for review."
disable-model-invocation: true
---

# to-pr

Publish completed work as a pull request for human review. This closes the
gap left after implementation (a `/tdd` cycle stops at commit-to-branch): it opens the
PR with a **contract** (what this change was supposed to do) and a **verification
matrix** (what was actually checked, for every acceptance criterion — not just
browser-observable ones) folded into the PR body.

Keep the flow light: no evidence schemas, no verdict gates, no required traces/videos.
Non-UI acceptance criteria are recorded, not newly executed — verifying them is assumed
done by the implementation work (e.g. the `/tdd` cycle) that precedes this skill.

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

## 2. Build the verification matrix

Every acceptance criterion gets one row, regardless of type — there is no separate
"non-UI, skip verification" path anymore. Columns: `AC` / `種別` (UI, CLI, API, infra)
/ `実行コマンドまたは理由` / `結果` / `未確認理由`.

- **UI criteria** (something you can see or exercise in a browser — a page, a URL, a UI
  behaviour, a rendered output): verify with `playwright-cli`, per the procedure below.
- **CLI / API / infra criteria**: do not execute new verification commands. Cite
  existing evidence in the `実行コマンドまたは理由` column instead — a test file added
  during the `/tdd` cycle (with its commit hash), a `lefthook` pre-commit run
  (typecheck/lint/etc.), or another already-produced artifact. If no such evidence
  exists, mark `結果` as `未確認` and state why in `未確認理由`. This keeps the matrix
  honest without turning `to-pr` into a second test runner.
- Assign `結果` one of: `確認済み` (observed working, or evidence found) / `未確認`
  (could not be exercised or no evidence exists) / `要人間確認` (ambiguous; needs a
  human to judge).

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

1. Start the dev server if the repo defines one: `package.json` `scripts.dev`
   (`npm run dev` / `bun dev`), or a `dev` target in the `Makefile` (`make dev`). If no
   dev command exists, do not verify — mark the UI criteria `未確認` and note why.
2. For each UI criterion: open the relevant URL, drive the flow, take a `snapshot`, and
   — where it helps a reviewer — a `screenshot`. Check the console and network for
   errors. For timing- or count-sensitive criteria, measure inside a single `run-code`
   script rather than chaining separate CLI calls (each call's own round-trip can itself
   exceed the window you're measuring), e.g.:

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

Do not fail-close or gate on screenshots. Record what you saw and move on.

## 3. Record code-review status

Check the conversation/session for evidence that `code-review` ran: its summary output,
a verdict, or a note that blocking findings were fixed. Record one line in the PR body —
either the outcome (e.g. "実施済み、ブロッキング指摘なし") or `未実施` if no evidence is
found. Either way, **do not block PR creation on this** — it is a record, not a gate
(consistent with this skill never using verdict gates).

## 4. Self-check before opening the PR

Before creating the PR, do a quick pass over what step 2 and step 3 produced: is the
code-review status accidentally left as `未実施` without actually having looked for
evidence? Is there an acceptance criterion with no row in the verification matrix? Fix
what you find; otherwise proceed. This is a lightweight inline check, not an invocation
of the `harness-feedback` skill — `harness-feedback`'s auto mode is designed to skip the
currently active session, so chaining it from here would not analyse anything useful.
`harness-feedback` remains a separate, manually-triggered practice for a later session.

## 5. Open the PR

1. Push the branch if needed (ask before pushing — it is outward-facing).
2. Write the PR body to a **fresh** temp file (use `mktemp` or a branch-scoped name —
   a fixed name like `pr-body.md` collides with stale content from previous runs). Write
   it in the language of the conversation / repo. Canonical structure:
   - A short change summary.
   - `## Contract` — the six fields from step 1, verbatim (including any `未記載`).
   - `## Verification Matrix` — the table built in step 2.
   - `## Code Review` — the one line from step 3.
   Reference the issue it closes (`Fixes #N`) when there is one; when there is no issue,
   omit the `Fixes` line and mention where the contract came from (conversation, PRD) in
   the summary instead.
3. Create the PR:

   ```bash
   gh pr create --title "<conventional title>" --body-file <tmp>
   ```

## 6. Screenshots in the PR body (default: none)

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
Also out of scope: invoking `harness-feedback` from this skill. The PR body's Contract /
Verification Matrix / Code Review sections are Markdown for a human reviewer and for
this skill's own step-4 self-check — they are not consumed by `harness-feedback`'s
artifact-driven enrichment (`contract.json` / `review.json` / `active-eval.json`), which
remains transcript-only analysis run separately.
This skill opens a PR with an honest, lightweight verification note — nothing more.
