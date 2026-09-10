/* eslint-disable no-await-in-loop -- Lifecycle transitions and bounded readiness retries must run in order. */
/* eslint-disable promise/avoid-new -- Adapt native server and child-process callbacks. */
import assert from "node:assert/strict";
// Throwaway #301 probe. Run only after approval of process-scoped PowerShell policy.
import { execFileSync, spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import http from "node:http";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

if (!process.argv.includes("--allow-process-policy")) {
  throw new Error(
    "Explicit approval is required before --allow-process-policy. See README.md."
  );
}
const { chromium } = await import(process.env.PROTOTYPE_PLAYWRIGHT_CORE);
const output = `/tmp/prototype-301-${Date.now()}`;
mkdirSync(output);
const windowsPath = (name) =>
  execFileSync(
    "wslpath",
    ["-w", fileURLToPath(new URL(name, import.meta.url))],
    { encoding: "utf-8" }
  ).trim();
const helper = windowsPath("../dogfood-chrome-windows.ps1");
const observer = windowsPath("./focus-observer.ps1");
const flags = [
  "-NoProfile",
  "-NonInteractive",
  "-WindowStyle",
  "Hidden",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
];
const ps = (args) =>
  execFileSync("powershell.exe", [...flags, helper, ...args], {
    encoding: "utf-8",
    timeout: 20_000,
  }).trim();

const results = [];
const record = (name, detail) => {
  results.push({ detail, name });
  writeFileSync(`${output}/results.json`, JSON.stringify(results, null, 2));
};
const owned = new Map();
const until = async (fn) => {
  let last;
  for (let n = 0; n < 30; n += 1) {
    try {
      return await fn();
    } catch (error) {
      last = error;
      await delay(200);
    }
  }
  throw last;
};
const start = async (id, port) => {
  const args = [
    "-RunId",
    `${output.split("/").pop()}-${id}`,
    "-DebugPort",
    String(port),
    "-Mode",
    "headless",
  ];
  assert.equal(ps(["-Action", "Inspect", ...args]), "absent");
  record(`profile-${id}`, ps(["-Action", "Resolve", ...args]));
  // Retain identity even if Start or CDP readiness fails. Never force-kill or delete profiles.
  const item = { args, browser: null, port };
  owned.set(id, item);
  assert.equal(ps(["-Action", "Start", ...args]), "started");
  item.browser = await until(() =>
    chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 1000 })
  );
  return item.browser;
};
const stop = async (id) => {
  const item = owned.get(id);
  if (!item) {
    return;
  }
  if (!item.browser) {
    throw new Error(
      `Unconfirmed startup for ${id}; retain profile and inspect manually.`
    );
  }
  const session = await item.browser.newBrowserCDPSession();
  await session.send("Browser.close").catch((error) => {
    if (!error.message.includes("closed")) {
      throw error;
    }
  });
  await until(() =>
    assert.equal(ps(["-Action", "Inspect", ...item.args]), "absent")
  );
  owned.delete(id);
  record(`confirmed-stop-${id}`, true);
};
const server = http.createServer((_request, response) => {
  response.setHeader("Content-Type", "text/html; charset=utf-8");
  response.end(
    "<!doctype html><title>Prototype 301 dummy origin</title><h1>Dummy profile data only</h1>"
  );
});
await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(19_433, "127.0.0.1", resolve);
});
const samples = [];
let partial = "";
const monitor = spawn(
  "powershell.exe",
  [...flags, observer, "-Seconds", "90"],
  { stdio: ["ignore", "pipe", "pipe"] }
);
monitor.stdout.on("data", (chunk) => {
  partial += chunk.toString();
  const lines = partial.split("\n");
  partial = lines.pop();
  for (const line of lines) {
    if (line.trim()) {
      samples.push(JSON.parse(line));
    }
  }
});
let monitorError = "";
monitor.stderr.on("data", (chunk) => {
  monitorError += chunk.toString();
});
const monitorDone = new Promise((resolve) => {
  monitor.once("error", (error) => {
    monitorError += error.message;
    resolve(-1);
  });
  monitor.once("exit", resolve);
});
const getState = (page) =>
  page.evaluate(() => ({
    cookie: document.cookie,
    value: localStorage.getItem("prototype301"),
  }));
try {
  await until(() =>
    assert.ok(
      samples.length >= 5,
      "Observer must be ready before any Chrome launch."
    )
  );
  record("operations-start", new Date().toISOString());
  const a = await start("a", 19_431);
  const b = await start("b", 19_432);
  const pa = await a.contexts()[0].newPage();
  const pb = await b.contexts()[0].newPage();
  await Promise.all(
    [pa, pb].map((page) => page.goto("http://127.0.0.1:19433"))
  );
  for (const [page, value] of [
    [pa, "A"],
    [pb, "B"],
  ]) {
    await page.evaluate((dummy) => {
      localStorage.setItem("prototype301", dummy);
      // eslint-disable-next-line unicorn/no-document-cookie -- Explicitly probe legacy cookie persistence with dummy data.
      document.cookie = `prototype301=${dummy}; Max-Age=3600; SameSite=Lax`;
    }, value);
  }
  assert.deepEqual(await getState(pa), {
    cookie: "prototype301=A",
    value: "A",
  });
  assert.deepEqual(await getState(pb), {
    cookie: "prototype301=B",
    value: "B",
  });
  record("same-origin-independent-profiles", true);
  await stop("a");
  const survivingState = await getState(pb);
  assert.equal(survivingState.value, "B");
  const restarted = await start("a", 19_431);
  const page = await restarted.contexts()[0].newPage();
  await page.goto("http://127.0.0.1:19433");
  assert.deepEqual(await getState(page), {
    cookie: "prototype301=A",
    value: "A",
  });
  record("restart-retains-A-and-B-survives", true);
} catch (error) {
  record("failure", error.message);
  process.exitCode = 1;
} finally {
  for (const id of owned.keys()) {
    try {
      await stop(id);
    } catch (error) {
      record(`retained-unconfirmed-${id}`, error.message);
      process.exitCode = 1;
    }
  }
  record("operations-end", new Date().toISOString());
  server.close();
  const code = await monitorDone;
  writeFileSync(
    `${output}/focus-samples.json`,
    JSON.stringify(samples, null, 2)
  );
  record("observer", {
    code,
    cursorChanged: new Set(samples.map((s) => `${s.x},${s.y}`)).size > 1,
    error: monitorError,
    foregroundChanged: new Set(samples.map((s) => s.foreground)).size > 1,
    limitation:
      "200ms samples can miss transient changes. Human input is indistinguishable; changes require investigation. Does not cover Dashboard or Dogfood coexistence.",
    samples: samples.length,
  });
  console.log(output);
  process.exit(process.exitCode || 0);
}
