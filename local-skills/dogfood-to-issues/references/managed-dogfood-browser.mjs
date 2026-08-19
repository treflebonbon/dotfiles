import { execFile } from "node:child_process";
import fsSync from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const run = async (command, args, options = {}) => {
  try {
    const result = await execFileAsync(command, args, {
      maxBuffer: 2 * 1024 * 1024,
      ...options,
    });
    return result.stdout.trim();
  } catch (error) {
    const detail = error.stderr?.trim() || error.message;
    throw new Error(`${command} ${args.join(" ")} failed: ${detail}`, {
      cause: error,
    });
  }
};

export const isWsl = () => {
  if (process.env.DOGFOOD_TEST_WSL !== undefined) {
    return process.env.DOGFOOD_TEST_WSL === "1";
  }
  return Boolean(
    process.env.WSL_DISTRO_NAME ||
    (() => {
      try {
        return /microsoft|wsl/iu.test(
          fsSync.readFileSync("/proc/sys/kernel/osrelease", "utf-8")
        );
      } catch {
        return false;
      }
    })()
  );
};

const stateRoot = () =>
  process.env.BROWSER_OWNERSHIP_DIR ||
  process.env.DOGFOOD_BROWSER_OWNERSHIP_DIR ||
  path.join(
    process.env.XDG_RUNTIME_DIR || process.env.DOGFOOD_TMPDIR || os.tmpdir(),
    "browser-ownership"
  );

const readOwner = async (ownerFile) => {
  const content = await fs.readFile(ownerFile, "utf-8").catch(() => "");
  const lines = content.split("\n").filter(Boolean);
  if (!lines.length) {
    return null;
  }
  return Object.fromEntries(
    ["role", "id", "pid", "mode", "profile", "endpoint", "workspace"].map(
      (key, index) => [key, lines[index] ?? ""]
    )
  );
};

const acquireOwner = async (owner) => {
  const root = stateRoot();
  await fs.mkdir(root, { mode: 0o700, recursive: true });
  const lock = path.join(root, "acquire.lock");
  const ownerFile = path.join(root, "owner");
  let lockAcquired = true;
  try {
    await fs.mkdir(lock, { mode: 0o700 });
  } catch {
    lockAcquired = false;
    const lockPid = Number(
      await fs.readFile(path.join(lock, "pid"), "utf-8").catch(() => "0")
    );
    if (lockPid > 0) {
      try {
        process.kill(lockPid, 0);
      } catch {
        await fs.rm(lock, { force: true, recursive: true });
        await fs.mkdir(lock, { mode: 0o700 });
        lockAcquired = true;
      }
    }
    if (!lockAcquired) {
      if (!(await fs.stat(lock).catch(() => null))) {
        throw new Error("browser ownership lock disappeared; retry");
      }
      throw new Error(
        `browser ownership is busy (lock pid ${lockPid || "unknown"})`
      );
    }
  }
  await fs.writeFile(path.join(lock, "pid"), `${process.pid}\n`);
  try {
    const existing = await readOwner(ownerFile);
    if (existing) {
      throw new Error(
        `Managed ${existing.role} Chrome is already owned by '${existing.id}' (pid ${existing.pid}). Close that consumer before starting Managed ${owner.role} Chrome.`
      );
    }
    await fs.writeFile(
      ownerFile,
      [
        owner.role,
        owner.id,
        String(owner.pid),
        owner.mode,
        owner.profile,
        owner.endpoint,
        owner.workspace,
        "",
      ].join("\n"),
      { mode: 0o600 }
    );
  } finally {
    await fs.rm(lock, { force: true, recursive: true });
  }
  return { ownerFile, root };
};

const releaseOwner = async (ownerFile, id) => {
  const current = await readOwner(ownerFile);
  if (current?.role === "dogfood" && current.id === id) {
    await fs.rm(ownerFile, { force: true });
  }
};

const powershell = () => process.env.DOGFOOD_POWERSHELL || "powershell.exe";
const script = () => {
  if (!process.env.DOGFOOD_WINDOWS_SCRIPT) {
    throw new Error(
      "DOGFOOD_WINDOWS_SCRIPT is unavailable. Use the managed nix-devshell dogfood package."
    );
  }
  return process.env.DOGFOOD_WINDOWS_SCRIPT;
};
const wslpath = () => process.env.DOGFOOD_WSLPATH || "wslpath";

let windowsScriptPath;
const windowsScript = async () => {
  if (windowsScriptPath) {
    return windowsScriptPath;
  }
  const value = script();
  windowsScriptPath =
    value.includes("\\") || /^[A-Za-z]:/u.test(value)
      ? value
      : await run(wslpath(), ["-w", value]);
  return windowsScriptPath;
};

const powershellAction = async (args) => {
  const scriptPath = await windowsScript();
  return run(powershell(), [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath,
    ...args,
  ]);
};

const choosePort = () => {
  if (process.env.DOGFOOD_CDP_ENDPOINT) {
    return new URL(process.env.DOGFOOD_CDP_ENDPOINT).port;
  }
  // Windows mirrored networking does not guarantee that a Linux-assigned
  // ephemeral port is bindable by a Windows process. Do not bind-and-release
  // a Linux socket here: the mirrored port proxy may still be draining when
  // Chrome starts. Keep dogfood in a small dedicated loopback range instead.
  const port = Number(
    process.env.DOGFOOD_CDP_PORT || 19_330 + (process.pid % 64)
  );
  if (!Number.isInteger(port) || port < 1024 || port > 65_535) {
    throw new Error(`DOGFOOD_CDP_PORT must be a TCP port, got '${port}'.`);
  }
  return String(port);
};

const waitForCdp = async (endpoint, attempts = 100) => {
  for (let i = 0; i < attempts; i += 1) {
    try {
      // eslint-disable-next-line no-await-in-loop -- poll the endpoint sequentially
      const response = await fetch(`${endpoint}/json/version`);
      if (response.ok) {
        return;
      }
    } catch {
      // Chrome is still starting.
    }
    // eslint-disable-next-line no-await-in-loop -- keep the retry cadence bounded
    await delay(100);
  }
  throw new Error(
    `Managed Dogfood Chrome did not expose CDP at ${endpoint}. Verify Windows Chrome, WSL2 mirrored networking, and the dedicated loopback port; no WSL browser fallback was attempted.`
  );
};

// eslint-disable-next-line complexity -- this is the fail-closed lifecycle boundary
export const acquireManagedDogfoodChrome = async ({
  extension,
  headed = false,
  runId,
}) => {
  if (!isWsl()) {
    return null;
  }
  const id = runId || `dogfood-${process.pid}-${Date.now()}`;
  const endpointOverride = process.env.DOGFOOD_CDP_ENDPOINT;
  if (endpointOverride && process.env.DOGFOOD_TEST_ALLOW_CDP_ENDPOINT !== "1") {
    throw new Error(
      "DOGFOOD_CDP_ENDPOINT is restricted to tests; dogfood must use the managed Windows Chrome launcher."
    );
  }
  const port = await choosePort();
  const endpoint = endpointOverride || `http://127.0.0.1:${port}`;
  const profile = await powershellAction(["-Action", "Resolve", "-RunId", id]);
  const extensionPath = extension
    ? await run(wslpath(), ["-w", path.resolve(extension)])
    : "";
  const owner = await acquireOwner({
    endpoint,
    id,
    mode: headed ? "headed" : "headless",
    pid: process.pid,
    profile,
    role: "dogfood",
    workspace: process.cwd(),
  });

  let started = false;
  try {
    if (!endpointOverride) {
      const status = await powershellAction([
        "-Action",
        "Inspect",
        "-RunId",
        id,
        "-Mode",
        headed ? "headed" : "headless",
        "-DebugPort",
        port,
        "-ProfileDir",
        profile,
      ]);
      if (status !== "absent") {
        let remediation =
          "Verify the Windows Chrome process and its dedicated profile before retrying.";
        if (status === "chrome-missing") {
          remediation = "Install the stable Windows Google Chrome release.";
        } else if (status.startsWith("port-conflict:")) {
          remediation =
            "Free the dedicated loopback CDP port; another process will not be replaced automatically.";
        } else if (status.startsWith("profile-conflict:")) {
          remediation =
            "Close the dedicated dogfood Chrome using that profile before retrying.";
        }
        throw new Error(
          `Managed Dogfood Chrome is not available for a fresh run (status: ${status}). ${remediation}`
        );
      }
      await powershellAction([
        "-Action",
        "Start",
        "-RunId",
        id,
        "-Mode",
        headed ? "headed" : "headless",
        "-DebugPort",
        port,
        "-ProfileDir",
        profile,
        ...(extensionPath ? ["-ExtensionPath", extensionPath] : []),
      ]);
      started = true;
      await waitForCdp(endpoint);
    }
  } catch (error) {
    if (started) {
      try {
        await powershellAction([
          "-Action",
          "Cleanup",
          "-RunId",
          id,
          "-ProfileDir",
          profile,
        ]);
      } catch (cleanupError) {
        error.message = `${error.message}; cleanup failed: ${cleanupError.message}`;
      }
    }
    await releaseOwner(owner.ownerFile, id);
    throw error;
  }

  return {
    async close() {
      let cleanupError;
      let releaseError;
      try {
        if (started) {
          await powershellAction([
            "-Action",
            "Cleanup",
            "-RunId",
            id,
            "-ProfileDir",
            profile,
          ]);
        }
      } catch (error) {
        cleanupError = error;
      } finally {
        try {
          await releaseOwner(owner.ownerFile, id);
        } catch (error) {
          releaseError = error;
        }
      }
      if (releaseError) {
        const releaseMessage =
          releaseError instanceof Error
            ? releaseError.message
            : String(releaseError);
        const cleanupMessage = cleanupError
          ? `; cleanup failed: ${
              cleanupError instanceof Error
                ? cleanupError.message
                : String(cleanupError)
            }`
          : "";
        throw new Error(`${releaseMessage}${cleanupMessage}`, {
          cause: releaseError,
        });
      }
      if (cleanupError) {
        throw cleanupError instanceof Error
          ? cleanupError
          : new Error(String(cleanupError));
      }
    },
    endpoint,
    id,
    mode: headed ? "headed" : "headless",
    ownerFile: owner.ownerFile,
    profile,
  };
};
