# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, if it exists
- **`docs/adr/`** — read ADRs that touch the area you're about to work in

If either doesn't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
└── ...
```

## Relationship to `okf/`

This repo also maintains **`okf/`** — a separate, pre-existing knowledge bundle (chezmoi-deployed to `~/okf/`) describing the *dotfiles system itself*: chezmoi layout, nix devshells, skill harness, AI runtimes, and the architecture decisions behind them (`okf/decisions/`). `okf/` is consumed by any agent running in the home directory, across all repos — it is not scoped to feature work in this repo.

`CONTEXT.md` / `docs/adr/` (once they exist) are scoped to feature-level engineering-skill work *in this repo* (`tdd`, `diagnosing-bugs`, `improve-codebase-architecture`, `domain-modeling`) — glossary terms and decisions that arise from building or fixing something here, as opposed to decisions about the dotfiles system's own architecture.

**This split is provisional and flagged for reconsideration** — if `docs/adr/` and `okf/decisions/` start accumulating overlapping or contradicting entries, that's the signal to consolidate. Until then: system/infra-level decisions go in `okf/decisions/`, feature-level decisions arising from engineering-skill work go in `docs/adr/`.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR (in `docs/adr/` or `okf/decisions/`), surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
