import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import fs from "node:fs/promises";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

export const withBrowserLock = async (filename, action, shared = false) => {
  await fs.mkdir(path.dirname(filename), { mode: 0o700, recursive: true });
  const guard = spawn(
    process.env.MANAGED_CHROME_FLOCK || "flock",
    [
      shared ? "--shared" : "--exclusive",
      "--wait",
      "30",
      filename,
      process.execPath,
      "-e",
      "process.stdout.write('locked\\n');process.stdin.resume()",
    ],
    { stdio: ["pipe", "pipe", "pipe"] }
  );
  let detail = "";
  guard.stderr.on("data", (chunk) => {
    detail += chunk;
  });
  guard.stdin.on("error", () => {
    /* empty */
  });
  const ended = once(guard, "close");
  try {
    await Promise.race([
      once(guard.stdout, "data"),
      ended.then(() => {
        throw new Error(`resource-busy: ${detail}`);
      }),
    ]);
    return await action();
  } finally {
    guard.stdin.end();
    await ended;
  }
};

export const publishEvidence = ({
  repo,
  pr,
  placeholder,
  asset,
  directory,
  github,
}) => {
  const key = createHash("sha256")
    .update(`${repo.toLowerCase()}#${pr}`)
    .digest("hex");
  return withBrowserLock(path.join(directory, `pr-${key}.lock`), async () => {
    const current = JSON.parse(
      await github(["pr", "view", String(pr), "--repo", repo, "--json", "body"])
    ).body;
    if (current.includes(asset)) {
      return;
    }
    if (!placeholder || current.split(placeholder).length !== 2) {
      throw new Error(
        "body-conflict: expected exactly one placeholder in the fresh PR body"
      );
    }
    const updated = current.replace(placeholder, `![Evidence](${asset})`);
    const filename = path.join(directory, `body-${randomUUID()}.md`);
    await fs.writeFile(filename, updated, { flag: "wx", mode: 0o600 });
    try {
      await github([
        "pr",
        "edit",
        String(pr),
        "--repo",
        repo,
        "--body-file",
        filename,
      ]);
      const verified = JSON.parse(
        await github([
          "pr",
          "view",
          String(pr),
          "--repo",
          repo,
          "--json",
          "body",
        ])
      ).body;
      if (!verified.includes(asset)) {
        throw new Error("body-conflict: published image missing after update");
      }
    } finally {
      await fs.unlink(filename);
    }
  });
};

export const uploadEvidence = async (context, { repo, pr, image }) => {
  const page = await context.newPage();
  try {
    await page.goto(`https://github.com/${repo}/pull/${pr}`, {
      timeout: 30_000,
    });
    if (new URL(page.url()).pathname.startsWith("/login")) {
      throw new Error("authentication-required");
    }
    const body = page.locator(".js-comment-container").first();
    await body.locator("summary.timeline-comment-action").click();
    await body.getByText("Edit", { exact: true }).click();
    const textarea = body.locator('textarea[name="pull_request[body]"]');
    await textarea.waitFor({ state: "visible" });
    const pattern =
      /https:\/\/github\.com\/user-attachments\/assets\/[a-zA-Z0-9-]+/gu;
    const initialBody = await textarea.inputValue();
    const before = new Set(initialBody.match(pattern) || []);
    const started = Date.now();
    await body.locator("input[type=file]").setInputFiles(image);
    let asset;
    while (Date.now() - started < 60_000) {
      // eslint-disable-next-line no-await-in-loop -- Poll this owned editor until GitHub inserts its asset.
      const text = await textarea.inputValue();
      asset = (text.match(pattern) || []).find((url) => !before.has(url));
      if (asset) {
        break;
      }
      // eslint-disable-next-line no-await-in-loop -- Bound polling cadence.
      await delay(100);
    }
    if (!asset) {
      throw new Error("upload timeout");
    }
    return { asset, finished: Date.now(), started };
  } catch (error) {
    throw new Error(
      error.message === "authentication-required"
        ? "authentication-required: complete dedicated browser setup outside to-pr"
        : "upload-failed: verify PR edit access and connectivity; other requests were preserved",
      { cause: error }
    );
  } finally {
    await page.close();
  }
};
