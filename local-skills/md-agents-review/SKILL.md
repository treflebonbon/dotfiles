---
name: md-agents-review
description: "Interactive review of AGENTS.md, Codex rules, and Codex-facing repository instructions. Use when the user says /md-agents-review or asks to review, audit, slim, trim, refresh, or apply progressive disclosure to Codex-facing agent instructions. Commit is left to the user."
allowed-tools: Read, Edit, Write, AskUserQuestion, Glob, Bash(git diff:*), Bash(wc:*)
metadata:
  topics: [agents-md, codex, audit, progressive-disclosure, review]
  source: llm
---

# md-agents-review Claude Adapter

## Claude Runtime Notes

- Keep Claude-specific `allowed-tools` in this adapter, including `AskUserQuestion` for interactive section decisions.
- Read `references/criteria.md` before proposing instruction edits.
- Execution loop: read `references/criteria.md`, then assign one decision from **{Keep / Trim / Reword / Move-to / Delete}** to the preamble (criteria §1 Review unit covers how to split it by topic) and exactly one to each `## ` section, citing the criteria row. Present findings per §8 (severity-ordered), batch decisions through `AskUserQuestion`, and apply edits only after the user confirms.
- When incorporating external material (an article, another prompt set, a colleague's config) rather than an author's own draft, don't paste it in — run each element through the same Keep/Trim/Reword/Move-to/Delete decision against the sections it overlaps, and merge into existing sections before adding a new one.
- Use `Read`, `Edit`, and `Write` only after the user confirms proposed changes through Claude's question UI.
- This skill is explicitly triggered only; it is not run from hooks.
- Offer `Reword` for sections that should stay but whose wording should match GPT-5.5 prompt guidance (see `references/criteria.md` §6 and its cited source).
