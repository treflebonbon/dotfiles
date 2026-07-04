# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, if it exists
- **`docs/adr/`** — read ADRs that touch the area you're about to work in

If either doesn't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
└── ...
```

## Relationship to `runtime/`

This repo also maintains **`runtime/`** — a pre-existing knowledge bundle (chezmoi-deployed to `~/runtime/`) describing the environment every agent shares regardless of which repo it's working in: shell environment, skill deployment, AI runtime config. It's named `runtime/`, not `okf/` — OKF (Open Knowledge Format) is the markdown+frontmatter *format* these files are written in, not a description of their content, so it doesn't belong in the directory name.

`runtime/` is scoped strictly to content with genuine cross-repo value (see [ADR-0007](../adr/0007-split-okf-by-cross-repo-value.md)). Two docs that used to live there — `architecture` (this repo's own chezmoi/nix layout) and `conventions` (this repo's own commit/lint rules) — provide no value to an agent working in an unrelated repo, so they live in `docs/architecture.md` / `docs/conventions.md` instead (repo-local, not chezmoi-deployed).

**Decision records are unified in `docs/adr/`** (see [ADR-0006](../adr/0006-consolidate-decisions-into-docs-adr.md)) — there is no separate `runtime/decisions/` (formerly `okf/decisions/`). All ADRs for this repo, whether about the dotfiles system's own architecture or about feature-level engineering-skill work, live in `docs/adr/` with sequential numbering (`000N-slug.md`). They keep the OKF-style frontmatter (`type` / `description` / `tags` / `timestamp`) as useful metadata, but otherwise follow the lightweight mattpocock ADR-FORMAT.md template.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR in `docs/adr/`, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (event-sourced orders) — but worth reopening because…_
