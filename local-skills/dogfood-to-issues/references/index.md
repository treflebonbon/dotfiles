---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [dogfood-to-issues, references]
source: human
---

# dogfood-to-issues references

Read this file first. Then open the reference needed for the active phase:

- [worktree-setup.md](worktree-setup.md) — create, resume, and preserve the `dogfood/*` evidence worktree.
- [report-parsing.md](report-parsing.md) — parse `report.md` into finding candidates.
- [approval-protocol.md](approval-protocol.md) — dedup preflight and per-finding approval loop.
- [severity-label-mapping.md](severity-label-mapping.md) — map dogfood severity/category to repository labels with fallback.
- [issue-body-template.md](issue-body-template.md) — render approved findings into GitHub Issue bodies.
- [verification.md](verification.md) — smoke and end-to-end verification guidance.
- [mv3-extension.md](mv3-extension.md) — Playwright runner と `--extension` を使った MV3 拡張 dogfood 経路。
- [mv3-spike.md](mv3-spike.md) — MV3 SW 登録の spike (#955) 結果と採用経路。

The high-level flow is intentionally thin: isolate the Playwright dogfood run, keep evidence as a local-only audit trail under `dogfood-output/`, ask before opening every issue unless the user explicitly chooses the batch escape hatch, then create issues that reference that local evidence.
