---
name: marp
description: "Convert markdown to PDF presentation slides using Marp CLI. Use when the user says /marp, asks to create slides, a presentation, a deck, or demo materials, or wants to convert markdown to PDF slides for a talk. Simplifies content for slide format, applies design template, and generates PDF output."
allowed-tools: Bash(marp:*), Bash(mktemp:*), Bash(rm:*), Read, Write
metadata:
  depends_on: []
  topics: [slides, marp, markdown, pdf, presentation]
  source: llm
---

# marp Claude Adapter

## Claude Runtime Notes

- Keep `allowed-tools` for `marp`, `mktemp`, `rm`, `Read`, and `Write`.
- Read `references/slide-guidelines.md` before simplifying source Markdown.
- Read `references/design-template.md` before generating Marp frontmatter and slide styling.
- Produce PDF output through Marp CLI rather than hand-editing exported artifacts.
