---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [dogfood, worktree, evidence]
source: human
---

# Worktree Setup

Use a dedicated branch and worktree for each dogfood run so screenshots, videos, and reports never dirty the caller's current branch.

## Resolve Names

```bash
REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
TARGET_SLUG="$(printf '%s' "$TARGET_URL" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*$##; s#[^A-Za-z0-9]+#-#g; s#^-|-$##g' | tr '[:upper:]' '[:lower:]')"
SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
BRANCH="dogfood/$(date -u +%F)-$TARGET_SLUG"
WT_DIR=".worktrees/dogfood-$TARGET_SLUG"
OUTPUT_DIR="dogfood-output/$SESSION"
```

If the slug is empty, stop and ask for a concrete target URL.

## Create

```bash
git fetch origin main
git worktree add -b "$BRANCH" "$WT_DIR" origin/main
mkdir -p "$WT_DIR/$OUTPUT_DIR"
```

`origin/main` is the base because the worktree exists only to isolate the dogfood run from the caller's branch. The branch is never pushed; evidence lives under the `.worktrees/` worktree, which is gitignored, so it stays local.

> **Note on paths**: `WT_DIR` is relative to the repo root (inside the repository at `.worktrees/`). `OUTPUT_DIR` is relative to `WT_DIR`. All dogfood artifacts therefore live under `.worktrees/`, which is gitignored, so they stay a local-only audit trail (the `dogfood-output/` subtree is covered transitively by `.worktrees/`, not by a `dogfood-output/` entry).

## Resume

When `--resume <path>` is supplied, do not run dogfood again. Validate that `<path>/report.md` exists and that evidence paths in the report are readable. If the resume path is already inside a `dogfood/*` worktree, reuse that worktree.

## Dogfood Invocation

Run the Playwright dogfood runner with the output directory in the worktree:

```bash
REF_DIR="${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}/references"
OUT_ABS="$(readlink -f "$WT_DIR/$OUTPUT_DIR")"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
node "$REF_DIR/playwright-dogfood-runner.mjs" \
  --target "$TARGET_URL" \
  --output "$OUT_ABS"
```

When `--extension <path>` is supplied, append `--extension "$(readlink -f "$EXTENSION_PATH")"`.
If that headless MV3 run exits non-zero because the service worker did not register, retry once with `--headed` under `xvfb-run -a`.

The runner writes `report.md`, `screenshots/`, `videos/`, `traces/`, `console.json`, and `network.json` under `$WT_DIR/$OUTPUT_DIR`.

## Cleanup

Do not auto-remove the worktree. The final summary may include manual cleanup commands after issues have been reviewed:

```bash
git worktree remove "$WT_DIR"
git branch -D "$BRANCH"
```
