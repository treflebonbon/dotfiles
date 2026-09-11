#!/usr/bin/env node
/* eslint-disable no-await-in-loop -- Lifecycle readiness and confirmed-stop polling must be sequential. */
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";

import {
  withBrowserLock,
  publishEvidence,
  uploadEvidence,
} from "./pr-evidence.mjs";

const exec = promisify(execFile);
const run = async (command, args) => {
  const result = await exec(command, args, {
    maxBuffer: 2 * 1024 * 1024,
    timeout: 90_000,
  });
  return result.stdout.trim();
};
const root = path.resolve(
  process.env.BROWSER_OWNERSHIP_DIR ||
    path.join(
      process.env.XDG_RUNTIME_DIR || process.env.TMPDIR || "/tmp",
      "browser-ownership"
    )
);
const directory = path.join(root, "attachments");
const owner = (...args) =>
  run(process.env.MANAGED_CHROME_OWNER || "managed-chrome-owner", args);
const digest = (value) => createHash("sha256").update(value).digest("hex");
const github = (args) => run(process.env.BROWSER_ATTACHMENTS_GH || "gh", args);
const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: Object.fromEntries(
    ["repo", "pr", "image", "placeholder", "request-id"].map((key) => [
      key,
      { type: "string" },
    ])
  ),
});
const [command] = positionals;
if (!["upload", "auth", "close"].includes(command)) {
  throw new Error(
    "Usage: browser-attachments upload --repo owner/repo --pr NUMBER --image PATH --placeholder TEXT --request-id ID | auth | close"
  );
}
if (
  command === "upload" &&
  (!/^[\w.-]+\/[\w.-]+$/u.test(values.repo || "") ||
    !/^[1-9][0-9]*$/u.test(values.pr || "") ||
    !values.image ||
    !values.placeholder ||
    !values["request-id"])
) {
  throw new Error(
    "upload requires repo, pr, image, placeholder and request-id"
  );
}
const modulePath =
  process.env.BROWSER_ATTACHMENTS_PLAYWRIGHT ||
  fileURLToPath(
    new URL(
      "../../lib/node_modules/playwright-cli-agent/node_modules/playwright-core/index.mjs",
      import.meta.url
    )
  );
const { chromium } = await import(modulePath);
let allocation;
const ps = async (action, mode) => {
  let script =
    process.env.PWCLI_WINDOWS_SCRIPT ||
    fileURLToPath(new URL("windows.ps1", import.meta.url));
  if (!/^[A-Za-z]:/u.test(script)) {
    script = await run("wslpath", ["-w", script]);
  }
  return [
    "-NoProfile",
    "-NonInteractive",
    "-WindowStyle",
    "Hidden",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    script,
    "-Action",
    action,
    "-ProfileDir",
    allocation.profile,
    "-DebugPort",
    new URL(allocation.endpoint).port,
    ...(mode ? ["-Mode", mode] : []),
  ];
};
const powershell = () => process.env.PWCLI_POWERSHELL || "powershell.exe";
const scoped = (...args) => owner("--identity", allocation.identity, ...args);
const connect = async () => {
  for (let n = 0; n < 30; n += 1) {
    try {
      return await chromium.connectOverCDP(allocation.endpoint, {
        timeout: 1000,
      });
    } catch {
      await delay(200);
    }
  }
  throw new Error(
    "cdp-unavailable: dedicated attachment browser did not become reachable"
  );
};
const ensure = (mode) =>
  withBrowserLock(path.join(directory, "startup.lock"), async () => {
    const status = JSON.parse(await scoped("status"));
    if (status) {
      if (status.phase !== "active" || status.mode !== mode) {
        throw new Error(
          "ownership-conflict: attachment browser has a different mode or incomplete startup; preserve it and inspect status"
        );
      }
      return status;
    }
    const token = await scoped(
      "reserve",
      "--role",
      "attachment",
      "--id",
      "shared-attachments",
      "--pid",
      String(process.pid),
      "--mode",
      mode,
      "--profile",
      allocation.profile,
      "--endpoint",
      allocation.endpoint
    );
    try {
      const state = await run(powershell(), await ps("Inspect"));
      if (state !== "absent") {
        throw new Error(
          "ownership-conflict: existing browser or endpoint has no matching attachment owner"
        );
      }
      await scoped(
        "run",
        token,
        "--",
        powershell(),
        ...(await ps("Start", mode))
      );
      const browser = await connect();
      await browser.close();
      await scoped("activate", token);
    } catch (error) {
      // release refuses live or unconfirmed startup, retaining the evidence for recovery.
      await scoped("release", token).catch(() => {
        /* empty */
      });
      throw error;
    }
  });
const save = async (filename, receipt) => {
  const temporary = `${filename}.${process.pid}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(receipt), { mode: 0o600 });
  await fs.rename(temporary, filename);
};
try {
  const located = await owner("locate", "--role", "attachment");
  const fields = located.split("\t");
  allocation = { endpoint: fields[2], identity: fields[0], profile: fields[1] };
  await withBrowserLock(
    path.join(directory, "requests.lock"),
    async () => {
      if (command === "close") {
        const status = JSON.parse(await scoped("status"));
        if (!status) {
          return;
        }
        if (status.phase !== "active") {
          throw new Error(
            "ownership-conflict: inspect incomplete startup before closing"
          );
        }
        await scoped("activate", status.token);
        const browser = await connect();
        try {
          const session = await browser.newBrowserCDPSession();
          await session.send("Browser.close").catch((error) => {
            if (!error.message.includes("closed")) {
              throw error;
            }
          });
        } finally {
          await browser.close();
        }
        for (let n = 0; n < 30; n += 1) {
          if ((await run(powershell(), await ps("Inspect"))) === "absent") {
            await scoped("release", status.token);
            return;
          }
          await delay(200);
        }
        throw new Error(
          "close-unconfirmed: attachment browser ownership was preserved"
        );
      }
      const mode = command === "auth" ? "headed" : "headless";
      const existing = await ensure(mode);
      if (existing) {
        const observed = await run(powershell(), await ps("Inspect"));
        if (observed !== `managed:${mode}:${existing.browserPid}`) {
          throw new Error(
            "ownership-conflict: attachment browser identity changed; consumer preserved"
          );
        }
      }
      if (command === "auth") {
        const browser = await connect();
        try {
          const page = await browser.contexts()[0].newPage();
          await page.goto("https://github.com/settings/profile");
        } finally {
          await browser.close();
        }
        console.log(
          "Complete authentication in the dedicated Chrome, then run browser-attachments close. Uploads use headless mode."
        );
        return;
      }
      const image = await fs.readFile(values.image);
      const key = digest(
        `${values.repo.toLowerCase()}#${values.pr}:${values["request-id"]}`
      );
      const filename = path.join(directory, `${key}.json`);
      await withBrowserLock(path.join(directory, `${key}.lock`), async () => {
        const signature = digest(`${digest(image)}:${values.placeholder}`);
        let receipt = await fs
          .readFile(filename, "utf-8")
          .then(JSON.parse)
          .catch((error) => {
            if (error.code !== "ENOENT") {
              throw error;
            }
            return null;
          });
        if (receipt && receipt.signature !== signature) {
          throw new Error(
            "request-conflict: request-id was already used with different content"
          );
        }
        if (receipt?.phase === "authentication-required") {
          receipt = null;
        }
        if (receipt && !receipt.asset) {
          throw new Error(
            "upload-unconfirmed: previous request has no confirmed asset; inspect it before requesting another upload"
          );
        }
        if (!receipt) {
          receipt = { phase: "uploading", signature };
          const browser = await connect();
          await save(filename, receipt);
          try {
            const result = await uploadEvidence(browser.contexts()[0], {
              image: values.image,
              pr: values.pr,
              repo: values.repo,
            });
            receipt = { phase: "uploaded", signature, ...result };
            await save(filename, receipt);
          } catch (error) {
            if (error.message.startsWith("authentication-required")) {
              await save(filename, {
                phase: "authentication-required",
                signature,
              });
            }
            throw error;
          } finally {
            await browser.close();
          }
        }
        await publishEvidence({
          asset: receipt.asset,
          directory,
          github,
          placeholder: values.placeholder,
          pr: values.pr,
          repo: values.repo,
        });
        await save(filename, { ...receipt, phase: "published" });
        console.log(
          JSON.stringify({
            asset: receipt.asset,
            finished: receipt.finished,
            requestId: values["request-id"],
            started: receipt.started,
          })
        );
      });
    },
    command === "upload"
  );
} catch (error) {
  console.error(`browser-attachments: ${error.message}`);
  process.exitCode = 1;
}
