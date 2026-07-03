---
name: rop
description: "Enforce Railway Oriented Programming (ROP) two-track patterns in Elixir, Gleam, Rust, and Effect-TS. Use when the user mentions ROP, railway, two-track, or Result type composition, or asks to refactor imperative error handling to pipeline style. Provides bind/map/tee adapter taxonomy, language-specific references, and a code review checklist. Not for simple try/catch or basic error handling without railway composition."
allowed-tools: Read, Edit, Write
metadata:
  depends_on: []
  topics: [rop, railway, error-handling, functional, result-type]
  source: llm
---

# rop Claude Adapter

## Claude Runtime Notes

- Keep `Read`, `Edit`, and `Write` tool access for focused refactors and reviews.
- Use `references/elixir.md`, `references/gleam.md`, `references/rust.md`, and `references/effect-ts.md` for language-specific guidance.
- Apply ROP guidance only when the task involves two-track Result-style composition, not generic try/catch cleanup.
- Keep edits scoped to the requested language and module.
