---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [verification, smoke-test]
source: human
---

# Verification

Use the smallest verification path that matches the change.

## Static Checks

The skill lives under `local-skills/dogfood-to-issues/` (chezmoi SoT) and is materialised to `~/.agents/skills/`, `~/.claude/skills/`, and `~/.codex/skills/` by `run_onchange_after_deploy-local-skills.sh.tmpl`.

## Runner Smoke Test

Run the bundled runner directly so browser automation is verified without creating GitHub Issues:

```bash
REF_DIR="$HOME/.agents/skills/dogfood-to-issues/references"
OUT_DIR="$(mktemp -d)"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
node "$REF_DIR/playwright-dogfood-runner.mjs" --target about:blank --output "$OUT_DIR"
test -f "$OUT_DIR/report.md"
test -f "$OUT_DIR/traces/playwright-trace.zip"
```

## Annotation Integration Tests

Run the subprocess-level Bats coverage for the opt-in path:

```bash
bats tests/dogfood-to-issues.bats
```

This verifies unchanged non-annotation output, `--resume` rejection, two rectangles plus overall feedback, empty submission, a real CDP attach/eval/detach against the runner-owned Chromium, MV3 coexistence, and evidence finalization on CLI failures.

For a manual dashboard check, run the runner with `--annotate` against a disposable page, submit two rectangles, and confirm `report.md`, the Playwright CLI PNG/YAML files, and `annotations/response.json` are present. Do not treat Submit as approval to create issues; candidates still go through Keep/Skip/Edit.

## Skill Smoke Test

Run against a low-risk public page:

```text
/dogfood-to-issues https://example.com
```

Expected:

- a `dogfood/YYYY-MM-DD-example-com` branch/worktree is created
- Playwright runner writes `dogfood-output/<session>/report.md`
- zero findings exits with a clear empty summary
- no GitHub Issues are created
- no commit or push of evidence happens

## End-to-End Test

Use a small app with known visual or functional defects:

1. Run `/dogfood-to-issues <local-app-url> --parent #N`.
2. Approve one finding, skip one, and edit one.
3. Confirm created issues contain repro steps and local evidence path references (no committed URLs).
4. Confirm parent issue body is updated only because `--parent` was explicit.

## Rollback Check

For accidental issues:

```bash
gh issue close <number> --repo "$REPO" --reason "not planned"
```

For evidence cleanup after audit:

```bash
git worktree remove "$WT_DIR"
git branch -D "$BRANCH"
```
