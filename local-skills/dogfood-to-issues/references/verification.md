---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [verification, smoke-test]
source: human
---

# Verification

Use the smallest verification path that matches the change.

## Static Checks

The skill lives under `local-skills/dogfood-to-issues/` (chezmoi SoT) and is materialised to `~/.agents/skills/` and `~/.claude/skills/` by `run_onchange_after_deploy-local-skills.sh.tmpl`.

## Runner Smoke Test

Run the bundled runner directly so browser automation is verified without creating GitHub Issues. On WSL2 set `DOGFOOD_WINDOWS_SCRIPT` to the packaged PowerShell script; the runner connects to Windows Managed Dogfood Chrome over CDP and does not launch a WSL browser:

```bash
REF_DIR="$HOME/.agents/skills/dogfood-to-issues/references"
OUT_DIR="$(mktemp -d)"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
# The WSL devShell shellHook supplies DOGFOOD_WINDOWS_SCRIPT.
node "$REF_DIR/playwright-dogfood-runner.mjs" --target about:blank --output "$OUT_DIR"
test -f "$OUT_DIR/report.md"
ATTEMPT="$(sed -n 's/^Attempt directory: //p' "$OUT_DIR/report.md")"
test -n "$ATTEMPT"
grep -Fx 'Run status: completed' "$OUT_DIR/report.md"
grep -Fx 'Evidence status: complete' "$OUT_DIR/report.md"
test -s "$OUT_DIR/$ATTEMPT/screenshots/initial.png"
test -s "$OUT_DIR/$ATTEMPT/traces/playwright-trace.zip"
```

For WSL2, the runner uses Windows Chrome over CDP and intentionally does not produce a `.webm` because `connectOverCDP` cannot reliably record video. Verify the screenshot and trace at the fixed 1440x1000 viewport instead. Locally launched non-WSL contexts retain the video assertion.

## Annotation Integration Tests

Run the subprocess-level Bats coverage for the opt-in path:

```bash
bats tests/dogfood-results.bats tests/dogfood-to-issues.bats
```

The browser tests use the current platform path (Windows Managed Dogfood Chrome on WSL2), preserving the root report entry. CLI fault-injection tests also verify unavailable artifacts, failed cleanup, interrupted retries, and stale report handling. Together these verify `--resume` rejection, two rectangles plus overall feedback, empty submission, a real CDP attach/eval/detach against the runner-owned Chromium, MV3 coexistence, and evidence finalization on CLI failures.

For a manual dashboard check, run the runner with `--annotate` against a disposable page, submit two rectangles, and confirm the latest and attempt reports, the Playwright CLI PNG/YAML files, and `annotations/response.json` are present inside the attempt. Review an older attempt through `--resume` to verify historical evidence paths. Do not treat Submit as approval to create issues; candidates still go through Keep/Skip/Edit.

## Read-only Resume Check

Resume is a skill procedure, not a runner CLI mode. Verify its report-reading step using an external, read-only output directory and [report-parsing.md](report-parsing.md). Include a legacy report without run status, a priority alias, valid evidence, and missing or escaping evidence paths. Confirm that the candidate survives, its severity is normalized, invalid evidence is shown as warnings, and the run remains unknown. Also review empty legacy, failed, and warning-only reports: none adds a clean cycle or proves the target passed. Compare file hashes, symlink targets, and directory contents before and after review to confirm no mutation. This check ends before candidate approval and does not launch a browser or create GitHub Issues.

## Skill Smoke Test

Run against a low-risk public page:

```text
/dogfood-to-issues https://example.com
```

Expected:

- a `dogfood/YYYY-MM-DD-example-com` branch/worktree is created
- Playwright runner writes `dogfood-output/<session>/report.md`
- zero findings exits with explicit run/evidence status; warnings do not count as a clean cycle
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
