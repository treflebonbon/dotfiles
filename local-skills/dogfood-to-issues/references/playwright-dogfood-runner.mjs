import fs from "node:fs/promises";
import path from "node:path";

import { chromium } from "playwright";

const parseArgs = (argv) => {
  const out = { headed: false };
  for (let i = 2; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--headed") {
      out.headed = true;
    } else if (a === "--target") {
      i += 1;
      out.target = argv[i];
    } else if (a === "--extension") {
      i += 1;
      out.extension = argv[i];
    } else if (a === "--output") {
      i += 1;
      out.output = argv[i];
    }
  }
  if (!out.target || !out.output) {
    throw new Error(
      "usage: playwright-dogfood-runner.mjs --target <url> --output <dir> [--extension <dir>] [--headed]"
    );
  }
  return out;
};

// Render finding candidates in the report-parsing.md block contract
// (### ISSUE-NNN: with Severity / Category / URL / Summary / Actual / Evidence).
// No findings => no ### blocks, so the downstream parser reports a clean zero-finding run.
const renderReport = ({ target, extensionId, findings }) => {
  const header = [
    "# Playwright Dogfood Report",
    "",
    `Target: ${target}`,
    ...(extensionId ? [`Extension ID: ${extensionId}`] : []),
    "",
  ];
  if (findings.length === 0) {
    header.push(
      "No findings: target loaded and no critical browser errors were detected.",
      ""
    );
    return header.join("\n");
  }
  const blocks = findings.map((f, i) => {
    const n = String(i + 1).padStart(3, "0");
    return [
      `### ISSUE-${n}: ${f.title}`,
      `Severity: ${f.severity}`,
      `Category: ${f.category}`,
      `URL: ${target}`,
      `Summary: ${f.summary}`,
      `Actual: ${f.actual}`,
      `Evidence: ${f.evidence.join(", ")}`,
      "",
    ].join("\n");
  });
  return [...header, ...blocks].join("\n");
};

const isExtSw = (w) => w.url().startsWith("chrome-extension://");

const args = parseArgs(process.argv);
await fs.mkdir(path.join(args.output, "screenshots"), { recursive: true });
await fs.mkdir(path.join(args.output, "videos"), { recursive: true });
await fs.mkdir(path.join(args.output, "traces"), { recursive: true });

const userDataDir = path.join(args.output, ".chromium-profile");
const launchArgs = [];
if (args.extension) {
  launchArgs.push(
    `--disable-extensions-except=${args.extension}`,
    `--load-extension=${args.extension}`
  );
}
const context = await chromium.launchPersistentContext(userDataDir, {
  args: launchArgs,
  channel: "chromium",
  headless: !args.headed,
  recordVideo: {
    dir: path.join(args.output, "videos"),
    size: { height: 1000, width: 1440 },
  },
  viewport: { height: 1000, width: 1440 },
});

const findings = [];
const screenshotRel = "screenshots/initial.png";
let extensionId;
let swRegistered = !args.extension;
const consoleErrors = [];
const failedRequests = [];
const traceRel = "traces/playwright-trace.zip";

try {
  await context.tracing
    .start({ screenshots: true, snapshots: true, sources: false })
    .catch(() => null);

  if (args.extension) {
    // Resolve the target extension's MV3 service worker. Filter to chrome-extension:// workers so a
    // reused profile or an unrelated worker cannot be mistaken for the extension under test.
    let sw = context.serviceWorkers().find(isExtSw);
    if (!sw) {
      try {
        sw = await context.waitForEvent("serviceworker", {
          predicate: isExtSw,
          timeout: 15_000,
        });
      } catch {
        sw = undefined;
      }
    }
    if (sw) {
      swRegistered = true;
      extensionId = sw.url().split("/").at(2);
    } else {
      extensionId = "(unknown - service worker not registered)";
      findings.push({
        actual: `Loaded extension: ${args.extension}. Observed service workers: ${JSON.stringify(context.serviceWorkers().map((w) => w.url()))}.`,
        category: "functional",
        evidence: [screenshotRel, traceRel],
        severity: "Critical",
        summary:
          "The unpacked MV3 extension loaded but no chrome-extension:// service worker registered within 15s.",
        title: "MV3 service worker did not register",
      });
    }
  }

  const page = context.pages()[0] ?? (await context.newPage());
  page.on("pageerror", (e) => consoleErrors.push(String(e)));
  page.on("console", (m) => {
    if (m.type() === "error") {
      consoleErrors.push(m.text());
    }
  });
  page.on("requestfailed", (request) => {
    failedRequests.push({
      error: request.failure()?.errorText ?? "request failed",
      method: request.method(),
      url: request.url(),
    });
  });
  page.on("response", (response) => {
    if (response.status() >= 500) {
      failedRequests.push({
        error: `HTTP ${response.status()}`,
        method: response.request().method(),
        url: response.url(),
      });
    }
  });

  try {
    // 'load' (not 'networkidle') so SPAs with sockets/polling do not hang until the nav timeout.
    await page.goto(args.target, { timeout: 30_000, waitUntil: "load" });
  } catch (error) {
    findings.push({
      actual: String(error),
      category: "functional",
      evidence: [screenshotRel, traceRel],
      severity: "High",
      summary: "The page did not finish loading.",
      title: "Navigation to target failed",
    });
  }
  await page
    .screenshot({
      fullPage: true,
      path: path.join(args.output, "screenshots", "initial.png"),
    })
    .catch(() => null);
  await context
    .storageState({ path: path.join(args.output, "auth-state.json") })
    .catch(() => null);

  if (consoleErrors.length) {
    findings.push({
      actual: consoleErrors.map((e) => `- ${e}`).join("\n"),
      category: "console",
      evidence: [screenshotRel, traceRel],
      severity: "Medium",
      summary: `${consoleErrors.length} console/page error(s) were logged.`,
      title: "Console errors detected while dogfooding the target",
    });
  }
  if (failedRequests.length) {
    findings.push({
      actual: failedRequests
        .map((r) => `- ${r.method} ${r.url}: ${r.error}`)
        .join("\n"),
      category: "network",
      evidence: ["network.json", screenshotRel, traceRel],
      severity: "Medium",
      summary: `${failedRequests.length} failed request(s) or 5xx response(s) were observed.`,
      title: "Network failures detected while dogfooding the target",
    });
  }
} finally {
  await fs
    .writeFile(
      path.join(args.output, "console.json"),
      `${JSON.stringify(consoleErrors, null, 2)}\n`
    )
    .catch(() => null);
  await fs
    .writeFile(
      path.join(args.output, "network.json"),
      `${JSON.stringify(failedRequests, null, 2)}\n`
    )
    .catch(() => null);
  await context.tracing
    .stop({ path: path.join(args.output, traceRel) })
    .catch(() => null);
  // Always close: releases the profile lock and finalizes the recorded video.
  await context.close();
}

// Video files exist only after context.close(); enumerate now and attach to each finding's evidence.
let videoRels = [];
try {
  const videoFiles = await fs.readdir(path.join(args.output, "videos"));
  videoRels = videoFiles
    .filter((f) => f.endsWith(".webm"))
    .map((f) => `videos/${f}`);
} catch {
  videoRels = [];
}
for (const f of findings) {
  f.evidence.push(...videoRels);
}

await fs.writeFile(
  path.join(args.output, "report.md"),
  renderReport({ extensionId, findings, target: args.target })
);

// Headless run where the SW never registered: signal failure so SKILL.md Step 4 retries headed.
// In headed mode a missing SW is final and is already captured as the Critical finding above.
if (!swRegistered && !args.headed) {
  process.exitCode = 1;
}
