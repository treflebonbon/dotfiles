---
depends_on:
  - skills/playwright-dogfood/SKILL.md
topics: [dogfood, worktree, evidence]
source: human
---

# Worktree Setup

Use a dedicated branch and worktree for each dogfood run so screenshots, videos, and reports never dirty the caller's current branch.

## Resolve Names

```bash
TARGET_SLUG="$(printf '%s' "$TARGET_URL" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*$##; s#[^A-Za-z0-9]+#-#g; s#^-|-$##g' | tr '[:upper:]' '[:lower:]')"
SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
BRANCH="dogfood/$(date -u +%F)-$TARGET_SLUG"
WT_DIR=".worktrees/dogfood-$TARGET_SLUG"
OUTPUT_DIR="dogfood-output/$SESSION"
```

If the slug is empty, stop and ask for a concrete target URL.

## Create

```bash
git worktree add -b "$BRANCH" "$WT_DIR" HEAD
mkdir -p "$WT_DIR/$OUTPUT_DIR"
```

Use local `HEAD` as the base: the worktree isolates evidence, while `TARGET_URL` selects the running app to inspect. No remote, fetch, or GitHub authentication is required. Follow the runtime’s native worktree entry rules when applicable. The branch is never pushed; evidence stays local under the gitignored `.worktrees/` directory.

> **Note on paths**: `WT_DIR` is relative to the repo root (inside the repository at `.worktrees/`). `OUTPUT_DIR` is relative to `WT_DIR`. All dogfood artifacts therefore live under `.worktrees/`, which is gitignored, so they stay a local-only audit trail (the `dogfood-output/` subtree is covered transitively by `.worktrees/`, not by a `dogfood-output/` entry).

## Resume

When `--resume <path>` is supplied, do not run dogfood again. Accept either the output root or a retained `attempts/<id>/` directory, and apply the run-status rules in [report-parsing.md](report-parsing.md). Resolve `<path>` to an absolute directory, validate that `report.md` exists, and validate evidence paths against that directory. It is the read-only evidence root. If it is already inside a `dogfood/*` worktree, reuse that worktree. Otherwise leave the external directory in place: do not create a wrapper worktree, move/copy its files, or mutate it.

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

When `--extension <path>` is supplied, append `--extension "$(readlink -f "$EXTENSION_PATH")"`. When `--annotate` is supplied, append `--annotate`; reject it if `--resume` is also present. The runner waits for Playwright Dashboard feedback only after automated inspection. Only if that headless MV3 run returns exit 2, retry once with `--headed` using the same output-derived Managed Dogfood profile identity. On WSL2 this is Windows Chrome over CDP and does not use `xvfb-run`; non-WSL callers may provide their normal display wrapper.

The runner creates a fresh `attempts/<id>/` directory under `$WT_DIR/$OUTPUT_DIR`, with its report and collected evidence. `report.md` at the output root presents the latest attempt with root-relative evidence paths. Annotation CLI output and response JSON also live inside the attempt. Failed acquisitions are recorded as warnings, with no missing paths advertised. Earlier attempts remain available for audit and `--resume`. Profile identity remains tied to the output root, not the attempt directory. Exit 1 stops; report text is never a retry trigger.

## Cleanup

Do not auto-remove the worktree. The final summary may include manual cleanup commands after the evidence has been reviewed:

```bash
git worktree remove "$WT_DIR"
git branch -D "$BRANCH"
```
