import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";

import { chromium } from "playwright";

const execFileAsync = promisify(execFile);

const parseArgs = (argv) => {
  const out = { annotate: false, headed: false };
  for (let i = 2; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--headed") {
      out.headed = true;
    } else if (a === "--annotate") {
      out.annotate = true;
    } else if (a === "--target") {
      i += 1;
      out.target = argv[i];
    } else if (a === "--extension") {
      i += 1;
      out.extension = argv[i];
    } else if (a === "--output") {
      i += 1;
      out.output = argv[i];
    } else if (a === "--resume") {
      i += 1;
      out.resume = argv[i];
    }
  }
  if (!out.target || !out.output) {
    throw new Error(
      "usage: playwright-dogfood-runner.mjs --target <url> --output <dir> [--extension <dir>] [--headed] [--annotate]"
    );
  }
  if (out.annotate && out.resume) {
    throw new Error("--annotate cannot be combined with --resume");
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
      `URL: ${f.url ?? target}`,
      `Summary: ${f.summary}`,
      `Actual: ${f.actual}`,
      `Evidence: ${f.evidence.join(", ")}`,
      "",
    ].join("\n");
  });
  return [...header, ...blocks].join("\n");
};

const isExtSw = (w) => w.url().startsWith("chrome-extension://");

const titleFromComment = (comment) => {
  const [firstLine = ""] = comment.split("\n");
  return [...firstLine.trim()].slice(0, 120).join("") || "Visual annotation";
};

const parseAnnotationResponse = (raw, target, responseRel) => {
  const payload = JSON.parse(raw);
  if (payload.isError) {
    throw new TypeError(payload.error ?? "Playwright CLI annotation failed");
  }
  if (payload.result === "No annotations were submitted.") {
    return [];
  }
  if (typeof payload.result !== "string") {
    throw new TypeError(
      "Playwright CLI annotation response has no result text"
    );
  }

  const frames = [];
  const feedback = [];
  let frame;
  let lastAnnotation;
  for (const line of payload.result.split("\n")) {
    if (line.startsWith("## Screenshot ")) {
      lastAnnotation = undefined;
      continue;
    }
    const header = line.match(
      /^.+? \/ .+? @ (?<url>.+) \((?<width>\d+)x(?<height>\d+)\)$/u
    );
    if (header) {
      const { height, url, width } = header.groups;
      frame = {
        annotations: [],
        evidence: [],
        height: Number(height),
        url,
        width: Number(width),
      };
      frames.push(frame);
      lastAnnotation = undefined;
      continue;
    }
    const annotation = line.match(
      /^\s*\{ x: (?<x>[^,]+), y: (?<y>[^,]+), width: (?<width>[^,]+), height: (?<height>[^}]+) \}: (?<comment>.*)$/u
    );
    if (annotation && frame) {
      const { comment, height, width, x, y } = annotation.groups;
      lastAnnotation = {
        comment,
        height,
        width,
        x,
        y,
      };
      frame.annotations.push(lastAnnotation);
      continue;
    }
    const evidence = line.match(
      /^- \[Annotation (?:image|snapshot)(?: \d+)?\]\((?<path>[^)]+)\)$/u
    );
    if (evidence && frame) {
      frame.evidence.push(evidence.groups.path);
      lastAnnotation = undefined;
      continue;
    }
    if (frame && lastAnnotation && line) {
      lastAnnotation.comment += `\n${line}`;
      continue;
    }
    if (!frame && line) {
      feedback.push(line);
    }
  }

  const findings = [];
  const overallFeedback = feedback.join("\n").trim();
  if (overallFeedback) {
    findings.push({
      actual: `Feedback: ${overallFeedback}`,
      category: "visual",
      evidence: [responseRel],
      severity: "Medium",
      summary: overallFeedback.replaceAll("\n", " "),
      title: titleFromComment(overallFeedback),
      url: target,
    });
  }
  for (const annotatedFrame of frames) {
    for (const annotation of annotatedFrame.annotations) {
      findings.push({
        actual: [
          `Comment: ${annotation.comment}`,
          `Coordinates: x=${annotation.x}, y=${annotation.y}, width=${annotation.width}, height=${annotation.height}`,
          `Viewport: ${annotatedFrame.width}x${annotatedFrame.height}`,
        ].join("\n"),
        category: "visual",
        evidence: [...annotatedFrame.evidence, responseRel],
        severity: "Medium",
        summary: annotation.comment.replaceAll("\n", " "),
        title: titleFromComment(annotation.comment),
        url: annotatedFrame.url,
      });
    }
  }
  return findings;
};

const readDevToolsPort = async (userDataDir, attemptsLeft = 100) => {
  const portFile = path.join(userDataDir, "DevToolsActivePort");
  const contents = await fs.readFile(portFile, "utf-8").catch(() => "");
  const [port] = contents.split("\n");
  if (/^\d+$/u.test(port)) {
    return port;
  }
  if (attemptsLeft === 1) {
    throw new Error("Chromium did not publish DevToolsActivePort");
  }
  await delay(50);
  return readDevToolsPort(userDataDir, attemptsLeft - 1);
};

const runCli = async (cliArgs, cwd) => {
  try {
    return await execFileAsync("playwright-cli", cliArgs, {
      cwd,
      maxBuffer: 10 * 1024 * 1024,
    });
  } catch (error) {
    const detail = error.stderr?.trim() || error.message;
    throw new Error(`playwright-cli ${cliArgs.join(" ")} failed: ${detail}`, {
      cause: error,
    });
  }
};

const collectAnnotations = async ({ output, target, userDataDir }) => {
  const help = await runCli(["show", "--help"], output);
  if (!help.stdout.includes("--annotate")) {
    throw new Error("playwright-cli does not support show --annotate");
  }

  const port = await readDevToolsPort(userDataDir);
  const session = `dogfood-annotate-${process.pid}-${Date.now()}`;
  await runCli(
    [`-s=${session}`, "attach", `--cdp=http://127.0.0.1:${port}`],
    output
  );

  let annotationResult;
  let annotationError;
  try {
    process.stderr.write(
      "Waiting for visual annotations in Playwright Dashboard...\n"
    );
    annotationResult = await runCli(
      [`-s=${session}`, "show", "--annotate", "--json"],
      output
    );
  } catch (error) {
    annotationError = error;
  }
  try {
    await runCli([`-s=${session}`, "detach"], output);
  } catch (error) {
    annotationError ??= error;
  }
  if (annotationError) {
    throw annotationError instanceof Error
      ? annotationError
      : new Error(String(annotationError));
  }

  const annotationDir = path.join(output, "annotations");
  const responseRel = "annotations/response.json";
  await fs.mkdir(annotationDir, { recursive: true });
  await fs.writeFile(path.join(output, responseRel), annotationResult.stdout);
  return parseAnnotationResponse(annotationResult.stdout, target, responseRel);
};

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
if (args.annotate) {
  launchArgs.push("--remote-debugging-port=0");
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
let runError;

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
  if (args.annotate) {
    findings.push(
      ...(await collectAnnotations({
        output: args.output,
        target: args.target,
        userDataDir,
      }))
    );
  }
} catch (error) {
  runError = error;
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

if (runError) {
  console.error(runError.message);
  process.exitCode = 1;
}

// Headless run where the SW never registered: signal failure so SKILL.md Step 4 retries headed.
// In headed mode a missing SW is final and is already captured as the Critical finding above.
if (!swRegistered && !args.headed) {
  process.exitCode = 1;
}
