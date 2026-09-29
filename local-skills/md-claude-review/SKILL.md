---
name: md-claude-review
description: "Interactive review of the project root CLAUDE.md against humanlayer best practices and the official Claude Code guidance. Use when the user says /md-claude-review, asks to review, audit, slim, trim, refresh, or apply progressive disclosure to the project CLAUDE.md. Use md-agents-review for AGENTS.md. Walks through the intro preamble and each `## ` section and offers Keep / Trim / Reword / Move-to / Delete decisions, then applies edits. Commit is left to the user."
allowed-tools: Read, Edit, Write, AskUserQuestion, Glob, Bash(git diff:*), Bash(wc:*), WebFetch(domain:code.claude.com), WebFetch(domain:platform.claude.com), Skill(claude-api)
metadata:
  depends_on: [references/criteria.md]
  topics: [claude-md, audit, progressive-disclosure, review]
  source: llm
---

# md-claude-review Claude Adapter

## Claude Runtime Notes

- Keep Claude-specific `allowed-tools` in this adapter, including `AskUserQuestion` for interactive section decisions.
- Read `references/criteria.md` before reviewing an instruction file.
- Execution loop: read `references/criteria.md`, then assign one decision from **{Keep / Trim / Reword / Move-to / Delete}** to the intro preamble (criteria §0 covers how to split it by topic) and exactly one to each `## ` section, citing the criteria row that justifies it. Open the decision table with two lines: the target model (the session's own model, and how you know it) and the path used for model-specific wording (`prompt-audit`, the fallback procedure, or skipped, and why). Before offering a Move-to target, confirm it exists with `Glob` or any file listing, and offer Delete when none does. Batch the decisions through `AskUserQuestion` (at most 4 questions per call; group units that take the same verb), and apply edits only after the user confirms.
- When incorporating external material (an article, another prompt set, a colleague's config) rather than an author's own draft, don't paste it in — run each element through the same Keep/Trim/Reword/Move-to/Delete decision against the sections it overlaps, and merge into existing sections before adding a new one.
- Use `Read`, `Edit`, and `Write` only after the user confirms the proposed CLAUDE.md changes through Claude's question UI.
- This skill is explicitly triggered only; it is not run from hooks.
- Offer `Reword` for sections that should stay but whose wording should match the current session model's prompting best practices. Model-specific wording checks go to `prompt-audit`: call the `claude-api` skill with the argument `prompt-audit` through the Skill tool, scoped to the one CLAUDE.md under review, and fold its High/Medium findings into the decisions (see `references/criteria.md` §7). If `claude-api` is unavailable or fails, run the update procedure in §7 (it fetches the official best-practices page and the model's guide), then apply §7a, and §7b only for rows still valid for this model.
