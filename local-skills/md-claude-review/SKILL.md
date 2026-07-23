---
name: md-claude-review
description: "Interactive review of the project root CLAUDE.md against humanlayer best practices and the official Claude Code guidance. Use when the user says /md-claude-review, asks to review, audit, slim, trim, refresh, or apply progressive disclosure to the project CLAUDE.md. Use md-agents-review for AGENTS.md. Walks through the intro preamble and each `## ` section and offers Keep / Trim / Reword / Move-to / Delete decisions, then applies edits. Commit is left to the user."
allowed-tools: Read, Edit, Write, AskUserQuestion, Glob, Bash(git diff:*), Bash(wc:*)
metadata:
  depends_on: [references/criteria.md]
  topics: [claude-md, audit, progressive-disclosure, review]
  source: llm
---

# md-claude-review Claude Adapter

## Claude Runtime Notes

- Keep Claude-specific `allowed-tools` in this adapter, including `AskUserQuestion` for interactive section decisions.
- Read `references/criteria.md` before reviewing an instruction file.
- Execution loop: read `references/criteria.md`, then assign one decision from **{Keep / Trim / Reword / Move-to / Delete}** to the intro preamble (criteria §0 covers how to split it by topic) and exactly one to each `## ` section, citing the criteria row that justifies it. Batch the decisions through `AskUserQuestion`, and apply edits only after the user confirms.
- When incorporating external material (an article, another prompt set, a colleague's config) rather than an author's own draft, don't paste it in — run each element through the same Keep/Trim/Reword/Move-to/Delete decision against the sections it overlaps, and merge into existing sections before adding a new one.
- Use `Read`, `Edit`, and `Write` only after the user confirms the proposed CLAUDE.md changes through Claude's question UI.
- This skill is explicitly triggered only; it is not run from hooks.
- Offer `Reword` for sections that should stay but whose wording should match Opus 4.8 prompting best practices (see `references/criteria.md` §7 and its cited source).
