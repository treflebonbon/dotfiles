---
name: dogfood
description: "Inspect a web app or Chrome MV3 extension with the bundled Playwright runner and report findings with local evidence. Add --annotate for human visual feedback, --issues for approved GitHub Issues, or --resume to review saved results. Use for implementation QA; not code review, feature design, or open-ended manual browser exploration."
allowed-tools: AskUserQuestion, Read, Write, Edit, Grep, Glob, Bash(git:*), Bash(gh:*), Bash(mkdir:*), Bash(date:*), Bash(find:*), Bash(readlink:*), Bash(npm:*), Bash(node:*), Bash(xvfb-run:*), Bash(bash:*)
metadata:
  depends_on: []
  topics: [dogfood, qa, issues, github, worktree, evidence]
  source: human
---

# Dogfood

Run automated inspection and report findings with local evidence. Annotation and Issue creation are independent opt-ins:

```text
/dogfood <URL>
/dogfood <URL> --annotate
/dogfood <URL> --issues
/dogfood <URL> --annotate --issues
/dogfood --resume <path> --issues
```

Without `--issues`, finish with the report and findings summary, including run/evidence status and warnings. Do not invoke `gh`, require GitHub authentication, ask about Issue creation, or load Issue-only procedures. `--issues` enables candidate review and creation after the user settles the candidates; it does not approve every finding automatically. `--issues` and `--resume` are skill options, not runner arguments.

## Steps

0. Reject `--annotate` together with `--resume <path>` before preflight, worktree, report, browser, or GitHub operations. Do not silently drop either option. For an external `--resume <path>` with `--issues`, require an explicit `REPO=owner/name` before GitHub preflight; ask for the repository when missing. Never infer its destination from the caller's checkout. Without `--issues`, no repository is required.
1. Run the bundled preflight `REPO="${REPO:-}" bash <this skill dir>/scripts/runtime-preflight.sh --need gh-issues` only with `--issues`; stop on `PREFLIGHT_FAIL`. Pass the requested `REPO` when supplied, including for external resumed reports. Without `--issues`, skip this GitHub preflight. Reject `--parent` or `REPO` without `--issues` before preflight or other operations.
2. Read [references/index.md](references/index.md), then load only the reference files needed for the current phase.
3. For a new run, resolve the required `TARGET_URL` and the local Git repository. With `--resume`, validate the existing report instead; no URL or local Git repository is required. Only with `--issues`, resolve the GitHub `REPO`, using the explicit destination for external resumed reports and otherwise defaulting to `gh repo view --json nameWithOwner`.
4. Create an isolated dogfood worktree on `dogfood/YYYY-MM-DD-<target-slug>` from local `HEAD` for a new run; no fetch or GitHub lookup is needed. With `--resume`, resolve the supplied output as the evidence root instead; reuse its dogfood worktree when present, but do not create a worktree merely to wrap an external output directory.
5. Unless `--resume <path>` is supplied, run the Playwright dogfood runner. **If `--auth-from` is supplied, stop and report that authenticated Playwright dogfood state import is not yet supported (follow-up) - do not silently dogfood an unauthenticated profile.** Resolve this skill's `references/` dir and output paths to **absolute** (the runner and its `node_modules` live under this skill's `references/`, a different base than the dogfood worktree):

   ```bash
   REF_DIR="${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}/references"
   OUT_ABS="$(readlink -f "$WT_DIR/$OUTPUT_DIR")"
   ARGS=(--target "$TARGET_URL" --output "$OUT_ABS")
   if [ -n "${EXTENSION_PATH:-}" ]; then
     ARGS+=(--extension "$(readlink -f "$EXTENSION_PATH")")
   fi
   if [ "${ANNOTATE:-0}" = 1 ]; then
     ARGS+=(--annotate)
   fi
   PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
   runner_status=0
   node "$REF_DIR/playwright-dogfood-runner.mjs" "${ARGS[@]}" || runner_status=$?
   if [ "$runner_status" -eq 2 ]; then
     runner_status=0
     if [[ -n "${WSL_DISTRO_NAME:-}" ]] || {
       [ -r /proc/sys/kernel/osrelease ] && grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease;
     }; then
       node "$REF_DIR/playwright-dogfood-runner.mjs" "${ARGS[@]}" --headed || runner_status=$?
     else
       xvfb-run -a node "$REF_DIR/playwright-dogfood-runner.mjs" "${ARGS[@]}" --headed || runner_status=$?
     fi
   fi
   if [ "$runner_status" -ne 0 ]; then
     printf 'Dogfood did not complete (exit %s). Report: %s\n' "$runner_status" "$OUT_ABS/report.md" >&2
     exit "$runner_status"
   fi
   ```

   `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` prevents npm from downloading a browser. On WSL2 the runner acquires Windows Managed Dogfood Chrome over loopback CDP; normal Web, MV3, and annotation share the output-derived profile identity and ownership record. Non-WSL environments retain the local Playwright path. Annotation uses a separate Dashboard window that displays the target via screencast, so the inspected browser can remain headless. Headless is primary. Exit 2 alone requests one headed MV3 retry with the same profile identity; exit 1 stops, including on cleanup or report publication failures. Each attempt retains its own report and evidence under `attempts/<id>/`; the root `report.md` is the latest view. On WSL2 the retry does not start a WSL browser or use `xvfb-run`.

   WSL2 requires the matching Nix `managed-chrome-owner` CLI (`MANAGED_CHROME_OWNER`). Startup and cleanup failures preserve ownership when Chrome's absence cannot be confirmed. Use `managed-chrome-owner status` to identify the consumer, finish that consumer, then run `managed-chrome-owner recover`. Recovery only verifies absence and releases ownership; it never closes Chrome or deletes profiles. Keep an uncertain startup reserved for investigation, and do not retry headed while ownership remains. Upgrade the Nix package and this local skill together after managed sessions and the Dashboard stop.

   With `--annotate`, the runner completes automated inspection before notifying the user that Playwright Dashboard input is awaited. It attaches a unique Playwright CLI session over the Managed Dogfood Chrome CDP endpoint, collects visual annotations, then detaches before releasing the dogfood ownership record. Rectangles and overall feedback become finding candidates; an empty submission adds none. Annotation failures are explicit and non-zero, but the runner still finalizes its report, trace, and video where the connected browser supports recording.

6. Read the run and evidence status using [report-parsing.md](references/report-parsing.md), then parse `report.md` into finding candidates. Exit 0 may include evidence warnings: display the missing artifacts and reasons before review. Failed runs stop automatic review; explicit `--resume` can review their recorded findings without rerunning the browser or treating them as completed.
7. Without `--issues`, report the findings, run/evidence status, warnings, and local report path, then finish. With `--issues` and nonempty candidates, run dedup preflight with `gh search issues` and label preflight with `gh label list`.
8. Ask for approval using [approval-protocol.md](references/approval-protocol.md). Use Keep, Skip, Edit, and Open all remaining as-is in a four-choice runtime. In a runtime limited to three choices, ask for individual versus batch review first, then use Keep, Skip, and Edit per finding.
9. Create approved issues with `gh issue create`, referencing paths relative to the resolved local evidence root (normally `dogfood-output/<session>/`). For an external resumed output, include its absolute local evidence root in the Issue source section. If `--parent #N` was explicitly supplied, append created sub-issue links to that parent.
10. Report created, skipped, edited, and duplicate-suspect findings. Leave the worktree in place for evidence audit.

## Scope Boundary

This skill ends with the report and findings summary, or with approved Issue creation and its summary when `--issues` is supplied. Do not implement fixes, create code branches, commit application changes, push code, open implementation PRs, close issues, or run finalization inside this skill.

If the user includes a follow-on workflow, finish only the dogfood phase first, then report an explicit handoff summary:

- report path and findings, plus created issue numbers and skipped/duplicate candidates when `--issues` is supplied
- current cycle number and zero-finding streak when the request is multi-cycle
- any visible GitHub actions that still need user approval

Created issues enter the normal workflow: `/triage` marks them ready, and implementation happens with the model-invoked discipline skills (tdd / code-review etc.). Continue into that separate phase only within the user's authorized follow-on scope.

For multi-cycle requests, track cycle count and zero-finding streak separately from this skill's single-cycle inspection. A single zero-finding dogfood run completes only the current cycle; never claim a "2 consecutive zero findings" stop condition unless two completed consecutive dogfood cycles both found zero Critical, High, or Medium findings (priority aliases P0-P2) after the most recent positive-finding cycle. Count only newly executed cycles whose final report has `Run status: completed` and `Evidence status: complete`, with no warnings. Evidence warnings reset the streak even when exit is 0. Failed, unfinished, retryable, and unknown runs also break the streak; headless/headed attempts together are one cycle, and `--resume` is review of an existing attempt, never a new cycle. If a cycle records no findings, skip follow-on implementation/finalization steps for that cycle and report the next required cycle or stop condition.

## Inputs

- `TARGET_URL`: required URL for a new run; not required with `--resume`.
- `REPO`: optional `owner/name`, valid only with `--issues`; required for an external resumed report; otherwise defaults to the current GitHub repository.
- `--issues`: opt into GitHub dedup, label lookup, candidate approval, and Issue creation. Without it, finish with the report and findings summary.
- `--resume <path>`: optional existing dogfood output directory containing `report.md`. The directory is a read-only evidence root. It may be an output root or an individual `attempts/<id>/` directory. Legacy/external reports without run status are reviewed as status unknown and never count toward consecutive zero-finding cycles.
- `--annotate`: optional visual feedback collection through Playwright CLI. It waits for human submission after automated checks and is incompatible with `--resume`.
- `--parent #N`: optional parent issue; requires `--issues`. Never infer a parent automatically.
- `--auth-from <profile|notes>`: optional authentication context. Not yet supported by the Playwright runner; supplying it stops the run so authenticated dogfood does not degrade into an unauthenticated login-page check.
- `--extension <path>`: optional path to an unpacked MV3 Chrome extension. On WSL2 the Managed Dogfood Chrome process receives the extension flags; the runner verifies a `chrome-extension://` service worker. Not compatible with `--auth-from` until authenticated MV3 state import is implemented.

## Guardrails

- Do not commit or push dogfood evidence. New runs stay under a gitignored `.worktrees/` dogfood worktree. An external resumed output remains in place as a read-only evidence root; issues identify that local root and reference evidence relative to it, never by committed URL.
- Do not auto-remove the worktree; it is the audit trail for screenshots, videos, and the source report.
- Do not add setup-repo labels in this flow. Missing severity or area labels fall back to `bug,dogfood`.
- Stop on `gh issue create` failure and print already-created issue numbers plus rollback commands.
- Adapt the approval questions to the current runtime's choice limit without dropping either per-finding editing or the explicit batch escape hatch.
- The Playwright dogfood runner is the standard path for both normal web targets and `--extension` MV3 targets. For open-ended manual browser exploration, use `playwright-cli`.

## References

- [index.md](references/index.md)
- [mv3-extension.md](references/mv3-extension.md)
- [mv3-spike.md](references/mv3-spike.md)
