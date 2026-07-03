---
depends_on:
  - skills/dogfood-to-issues/SKILL.md
topics: [dogfood, mv3, chrome-extension, playwright]
source: human
---

# Playwright Dogfood Runner and MV3 Extension Path

## When to use this runner

`dogfood-to-issues` uses the bundled Playwright dogfood runner (`playwright-dogfood-runner.mjs`) for normal web targets and for Chrome MV3 extension targets. Pass `--extension <path>` when the run must load an unpacked MV3 Chrome extension directory (i.e. a directory containing `manifest.json` with `"manifest_version": 3`).

## Why Playwright is the standard path

The runner writes deterministic artifacts (`report.md`, screenshots, videos, traces, console/network JSON) without feeding DOM dumps or trace bodies into the model context. This keeps `dogfood-to-issues` evidence reproducible and low-token.

For MV3 extensions, Playwright is also required: `agent-browser` operates over headless CDP and does not register MV3 service workers — extensions loaded via `--load-extension` require a persistent browser context, which the agent-browser daemon does not expose.

The headed-with-xvfb alternative also fails: the agent-browser daemon holds the `DISPLAY` from its own Xvfb session, and a second `xvfb-run -a` conflicts with that daemon DISPLAY assignment (see `mv3-spike.md` for the full spike results, #955).

The runner therefore bypasses the agent-browser daemon entirely and drives Playwright directly, avoiding both issues.

## Playwright version and browser supply

`references/package.json` pins `playwright@1.59.1`. This version expects `chromium-1217`, which matches the nix `PLAYWRIGHT_BROWSERS_PATH` chromium build in this environment.

**Do not substitute `1.58.2`** (used by the uxaudit skill). That version expects `chromium-1208` and causes a browser-not-found mismatch (see #955 spike pin correction).

Install dependencies (the canonical invocation lives in `SKILL.md` Step 4; resolve `REF_DIR` to this skill's `references/` absolute path rather than `cd`-ing):

```bash
REF_DIR="${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}/references"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
```

`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` tells Playwright to skip its own browser download and resolve chromium from the nix `PLAYWRIGHT_BROWSERS_PATH` instead. `npm ci` (not `install`) is used so the committed `package-lock.json` is honoured exactly.

## Evidence contract

The runner writes all output under the directory passed to `--output` (use `dogfood-output/<session>/` to match the standard dogfood layout):

| Path                          | Contents                                                                                                                                                            |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `report.md`                   | Finding candidates as `### ISSUE-NNN:` blocks (see [report-parsing.md](report-parsing.md)); MV3 runs include an Extension ID header; clean runs emit no ISSUE block |
| `screenshots/initial.png`     | Full-page screenshot after navigation                                                                                                                               |
| `videos/`                     | Screen recording (finalized after `context.close()`)                                                                                                                |
| `traces/playwright-trace.zip` | Playwright trace archive for deterministic local replay                                                                                                             |
| `console.json`                | Captured console/page errors                                                                                                                                        |
| `network.json`                | Captured failed requests and 5xx responses                                                                                                                          |
| `auth-state.json`             | Playwright storage state snapshot                                                                                                                                   |
| `.chromium-profile/`          | Persistent browser profile (gitignored)                                                                                                                             |

The runner emits findings in the `report-parsing.md` block contract so Step 5 parses them directly: console/page errors become a `Category: console` finding, failed requests and 5xx responses become a `Category: network` finding, a missing MV3 service worker becomes a `Critical` `functional` finding, and navigation failures become `High` `functional` findings. Video files are finalized only after `context.close()`; the runner enumerates them after closing and lists them under each finding's `Evidence`.

## Launch mechanism

The runner uses `chromium.launchPersistentContext` with `channel: 'chromium'`. For `--extension` runs it also passes:

- `--disable-extensions-except=<extension>` — disables all other extensions
- `--load-extension=<extension>` — loads the unpacked MV3 extension

The service worker is obtained by filtering for `chrome-extension://` workers (so a reused profile or an unrelated worker is not mistaken for the extension under test), with the `waitForEvent` wrapped so a timeout does not throw:

```js
const isExtSw = (w) => w.url().startsWith("chrome-extension://");
let sw = context.serviceWorkers().find(isExtSw);
if (!sw) {
  try {
    sw = await context.waitForEvent("serviceworker", {
      predicate: isExtSw,
      timeout: 15000,
    });
  } catch {
    sw = undefined; // recorded as a Critical finding instead of crashing
  }
}
const extensionId = sw
  ? sw.url().split("/")[2]
  : "(unknown - service worker not registered)";
```

This derives the extension ID from the SW URL (`chrome-extension://<id>/...`) without relying on `chrome.management` or a fixed ID. The context is always closed in a `finally` block so the profile lock is released and the video is finalized even when the SW or navigation fails.

## Headless vs headed

Headless is the primary path. When the MV3 service worker never registers in headless mode the runner exits non-zero; on that failure retry once with `--headed` under `xvfb-run -a` (in headed mode a missing SW is final and is recorded as the Critical finding):

```bash
REF_DIR="${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}/references"
xvfb-run -a node "$REF_DIR/playwright-dogfood-runner.mjs" --target "$TARGET_URL" --extension "$EXT_ABS" --output "$OUT_ABS" --headed
```

Because the runner does not use the agent-browser daemon, there is no DISPLAY conflict when invoking `xvfb-run -a` independently.

## Self-test (no external extension required)

`references/fixtures/mv3-min/` is a minimal MV3 extension (manifest + service worker) included in this repository for smoke testing.

```bash
REF_DIR="${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}/references"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$REF_DIR" ci
node "$REF_DIR/playwright-dogfood-runner.mjs" --target about:blank --extension "$REF_DIR/fixtures/mv3-min" --output "$(mktemp -d)"
```

Expected outputs after the runner exits (the fixture's SW registers, so a clean run reports no findings):

- `report.md` containing an `Extension ID:` line (and `No findings:` for the clean fixture)
- `screenshots/initial.png`
- `auth-state.json`
- `traces/playwright-trace.zip`
- `videos/` directory with a `.webm` file

## Limitations

- **`--auth-from` is not yet supported on this runner.** The Playwright runner launches a fresh persistent
  context and does not apply the `--auth-from` profile/notes, so an authenticated target would
  be dogfooded unauthenticated (degrading the run into a login-page check or misleading findings).
  `SKILL.md` Step 4 therefore stops with an error when `--auth-from` is supplied. Applying auth state
  (e.g. `storageState` input or `context.addCookies()` from a stored profile) is a follow-up.
  `auth-state.json` written by the runner is an output snapshot, not an input.
