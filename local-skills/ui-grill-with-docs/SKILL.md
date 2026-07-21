---
name: ui-grill-with-docs
description: "UI/UX の比重が高い設計を詰める grill-with-docs 派生。レイアウト・コンポーネント配置・画面遷移の比較検討が争点になる質問だけ、使い捨ての静的 HTML モックアップ（tmp/wireflame-<screen>.html）を見せながら聞く。それ以外の質問は通常どおりチャットで一問一答する。Use when grilling a UI/UX-heavy plan or design where visual comparison would sharpen the question."
disable-model-invocation: true
---

# ui-grill-with-docs

Run the same one-question-at-a-time loop as `grill-with-docs`, using `grilling`
and `domain-modeling`. Use `codebase-design` when the discussion reaches module
interfaces or seams. This skill adds only the visual-question behavior below;
do not fork or replace those skills.

## Choose the question format

Keep most questions in chat, following `grilling`: ask one question with a
recommended answer, then wait for feedback before continuing.

Add a static HTML/CSS mockup only when the decision itself concerns one of:

- page or panel layout
- component placement
- screen-transition or navigation patterns

Keep questions about wording, business rules, field inclusion, or other
text-resolvable decisions in chat. When the boundary is unclear, ask whether
the layout, placement, or transition itself is what the user must compare. For
example, error-message wording stays in chat; where the error appears may use a
mockup. A color threshold stays in chat; where its badge appears may use a
mockup.

## Create the visual aid

For a visual question:

1. Create `tmp/` if it does not exist.
2. Write or update `tmp/wireflame-<screen>.html`, where `<screen>` is a short
   English or romanized kebab-case slug such as `product-list`.
3. Keep the file self-contained: use static HTML and CSS with no JavaScript,
   external CDN, or other network dependency.
4. Show the alternatives needed for the current question, but do not embed a
   form or collect the answer in the page. The question, recommendation, and
   choices remain in chat.
5. Tell the user the file path after every creation or update. Let the user
   open it; do not take an automatic screenshot.

Treat these mockups as disposable comparison aids, not polished UI artifacts.
Ignore advisory design-quality findings from skills such as `impeccable` for
these files.

## Split and reuse files

Split files by screen or topic, not by turn count. Use a focused topic slug for
part of a screen, such as `wireflame-error-toast.html`. Reuse the same file when
the discussion returns to the same screen or topic, even after intervening
questions.

## Preserve decisions and clean up

Record resolved terms and decisions immediately through `domain-modeling` in
`CONTEXT.md` or an ADR when its criteria apply. The conversation and those
records are the source for a later `to-spec`; the mockups are never the source
of truth.

Before ending the session, delete only the `tmp/wireflame-*.html` files created
by this skill. Leave `tmp/` and every unrelated temporary file intact.
