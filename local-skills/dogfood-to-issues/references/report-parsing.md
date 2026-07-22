---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [dogfood, report, parsing]
source: human
---

# Report Parsing

Parse the `dogfood` report into finding candidates before asking for approval. Prefer structured Markdown parsing if available; otherwise use the block contract below.

## Required Inputs

- `REPORT_PATH="$OUTPUT_DIR/report.md"` unless `--resume` points elsewhere.
- Evidence root is the directory containing `report.md`.

Stop if `report.md` is missing or empty.

## Finding Block Contract

Treat headings matching this shape as finding starts:

```text
### ISSUE-001: Submit button is hidden on mobile
```

Accepted aliases are `### Finding 001:` and `### Bug 001:`. The parser should collect text until the next same-or-higher-level heading.

Within each block, extract these fields when present:

- `Severity`: `Critical`, `High`, `Medium`, or `Low`
- `Category`: `visual`, `functional`, `ux`, `content`, `perf`, `console`, or `a11y`
- `URL`
- `Summary`
- `Expected`
- `Actual`
- `Steps to reproduce`
- `Evidence`

If a field is absent, keep the original prose in `description` rather than inventing details.

Annotation-generated blocks use the same contract. Each rectangle defaults to `Medium` / `visual`, uses its frame URL, and retains the full comment, coordinates, and viewport in `Actual`. Its evidence includes the annotated PNG, ARIA snapshot, and `annotations/response.json`. Overall feedback without a rectangle is one candidate. An empty annotation submission creates no candidate.

## Candidate Schema

```json
{
  "id": "ISSUE-001",
  "title": "Submit button is hidden on mobile",
  "severity": "High",
  "category": "visual",
  "url": "http://localhost:3000/signup",
  "summary": "The primary submit button is clipped below the fold.",
  "expected": "The button is visible without horizontal scrolling.",
  "actual": "The button is clipped at 390px width.",
  "repro_steps": ["Open /signup at 390px width", "Scroll to the form footer"],
  "evidence": ["screenshots/signup-mobile.png", "videos/signup-mobile.webm"],
  "source_report": "dogfood-output/20260529T010203Z/report.md"
}
```

## Evidence Paths

Normalize relative evidence paths against the directory containing `report.md`. Keep paths relative to the worktree root for local evidence references. Drop evidence entries that point outside the worktree.

## Empty Reports

If the report contains no findings, print a zero-finding summary and stop before opening issues unless the user explicitly asks to preserve the report.
