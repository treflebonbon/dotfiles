---
name: ui-grill-with-docs
description: "UI/UX の設計を詰める grill-with-docs 派生。各ラウンドの全質問・比較モック・回答欄を1枚のHTMLにまとめ、回答をMarkdownで一括コピーする。"
disable-model-invocation: true
---

# ui-grill-with-docs

Call the Skill tool with "grilling" and with "domain-modeling" to run the same
frontier-round loop as `grill-with-docs`.
In each round, ask every decision whose prerequisites are
settled, give a recommendation for each, and wait for the human's answers
before opening the next frontier. Facts are explored from the environment;
decisions are not guessed or silently applied. Call the Skill tool with
"codebase-design" when the discussion reaches module interfaces or seams.
This skill replaces the chat question format with a round question sheet;
the interview and domain-modeling disciplines still apply.

## Build one round question sheet

Create `tmp/` if needed and copy [assets/round.html](assets/round.html) to
`tmp/ui-grill-<topic>.html`, using a short kebab-case topic. Use a path owned by
this session; choose a different slug if another session owns an existing file.
Update that same file for each subsequent round, replacing the previous
questions rather than accumulating a history. Keep every currently unblocked
question in this one HTML, including wording, business rules, and field choices.
Questions whose prerequisites remain open belong to a later frontier.

Read the template before adapting it. Replace its example `round-data` JSON:

- Give the session a unique, stable `sessionId`; change `roundId` for each new
  round. The page, copied answers, and browser drafts identify that round.
- Set the title and all questions. Each question has a stable `id`, `title`,
  full `prompt`, reasoned `recommendation`, and `choices` with stable IDs and
  human-readable labels. Put the recommended choice first and mark it
  `recommended: true`, leaving every input initially unanswered.
- Use `type: "single"` for exclusive choices, `"multiple"` for independent
  choices, and `"text"` with empty `choices` for an open question. Every question
  also has a free-text answer or supplement, so a custom answer needs no
  separate "Other" option.
- Serialize the JSON and escape `<` as `\u003c` before embedding it in the script
  element. Keep user-facing text as text, not executable markup.

For layout, component placement, or navigation comparisons, put a static
HTML/CSS mockup in a `<template id="visual-<question-id>">` in the same file.
It appears beside that question's text and inputs. Replace the example mockup;
omit a mockup when text resolves the decision. Keep mockups illustrative and
free of answer controls; the question sheet owns those controls.

Keep the generated file self-contained: inline CSS and JavaScript, no build,
server, CDN, or network dependency. Reuse the template's answer handling.
These are disposable interview aids; elaborate visual-design workflows and
advisory design-quality findings do not expand their scope.

## Collect and copy answers

The template provides a live, selectable Markdown output and one copy button.
Copy the round identity, question numbers and text, selected labels, and free
text for all questions. Include empty questions as `未回答`; copying partial
answers stays available. Recommendations and untouched inputs are not answers.

Input changes try to save a browser draft. Restore only the same session,
round, and question definitions, leaving new rounds unanswered. Local-file
storage can be unavailable; show that failure while keeping input and copying
usable. Try Clipboard API on the copy click; if unavailable or rejected, select
the visible output and explain how to copy it manually. Report success only
after a successful write. Browser drafts are a convenience, not decisions.

After every creation or update, link the file and ask the human to fill it in,
copy the answers, and paste them into chat. Let the human open the page; do not
take an automatic screenshot. Keep the questions in the sheet instead of
duplicating the round in chat or another question tool.

Read pasted answers against their session and round before recomputing the
frontier. Accept direct chat answers too. An ambiguous or unanswered decision
stays open; include it in the next sheet along with newly unblocked questions.
Carry each unanswered question forward with the same question ID, prompt,
choice IDs, and choice labels. A new round changes the round ID, not the
meaning of a pending question. Revise that question only when the human's
feedback calls for it; keep new proposals separate from its existing choices.
Resolve stale or contradictory answers with the human instead of applying them
to different questions. Do not read browser drafts as submitted answers.

## Preserve decisions and clean up

Record resolved terms immediately through `domain-modeling` in `CONTEXT.md`,
and decisions in an ADR only when its criteria apply. The conversation and
those records are the source for a later `to-spec`; the HTML and browser drafts
are never the source of truth. When the frontier is empty, confirm the shared
understanding before acting on the design.

Before ending the session, ask the user to confirm cleanup. After confirmation,
delete only the `tmp/ui-grill-<topic>.html` file owned by this session. Leave
`tmp/`, other sessions' sheets, and unrelated files intact. Deleting the HTML
does not clear browser drafts; do not claim that it does.
