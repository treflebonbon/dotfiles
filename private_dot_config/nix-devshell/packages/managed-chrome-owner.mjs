#!/usr/bin/env node
import { execFile, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";

const exec = promisify(execFile);

const root = path.resolve(
  process.env.BROWSER_OWNERSHIP_DIR ||
    path.join(
      process.env.XDG_RUNTIME_DIR || process.env.TMPDIR || "/tmp",
      "browser-ownership"
    )
);
const ownerFile = path.join(root, "owner");

const validEndpoint = (value) => {
  try {
    const url = new URL(value);
    return (
      url.protocol === "http:" &&
      url.hostname === "127.0.0.1" &&
      Number(url.port) > 0 &&
      !url.username &&
      !url.password &&
      !url.search &&
      !url.hash &&
      url.pathname === "/"
    );
  } catch {
    return false;
  }
};

const validUUID = (value) =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(value);

const validOwner = (owner) =>
  owner?.version === 1 &&
  validUUID(owner.token) &&
  ["playwright", "dogfood"].includes(owner.role) &&
  ["reserved", "starting", "settled", "active"].includes(owner.phase) &&
  ["headless", "headed"].includes(owner.mode) &&
  [owner.id, owner.profile, owner.workspace].every(
    (value) => typeof value === "string" && value.length > 0
  ) &&
  validEndpoint(owner.endpoint) &&
  Number.isInteger(owner.caller?.pid) &&
  owner.caller.pid > 0 &&
  typeof owner.caller.start === "string" &&
  /^[0-9]+$/u.test(owner.caller.start) &&
  validUUID(owner.caller.boot) &&
  (owner.phase === "active"
    ? Number.isInteger(owner.browserPid) && owner.browserPid > 0
    : owner.browserPid === null);

const readOwner = async () => {
  try {
    const owner = JSON.parse(await fs.readFile(ownerFile, "utf-8"));
    if (!validOwner(owner)) {
      throw new Error("invalid owner");
    }
    return owner;
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw new Error(
      `Legacy or invalid ownership at ${ownerFile}. Close the old managed sessions and Dashboard before switching; the record was preserved.`,
      { cause: error }
    );
  }
};

const writeOwner = async (owner) => {
  const temporary = `${ownerFile}.${randomUUID()}`;
  await fs.writeFile(temporary, `${JSON.stringify(owner)}\n`, {
    flag: "wx",
    mode: 0o600,
  });
  await fs.rename(temporary, ownerFile);
};

const processIdentity = async (pid) => {
  try {
    const stat = await fs.readFile(`/proc/${pid}/stat`, "utf-8");
    const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    const boot = await fs.readFile("/proc/sys/kernel/random/boot_id", "utf-8");
    return { boot: boot.trim(), pid, start: fields[19] };
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ESRCH") {
      return null;
    }
    throw error;
  }
};

const callerAlive = async (owner) => {
  const current = await processIdentity(owner.caller.pid);
  return (
    current?.start === owner.caller.start && current?.boot === owner.caller.boot
  );
};

const locked = async (action) => {
  const dogfoodRoot = process.env.DOGFOOD_BROWSER_OWNERSHIP_DIR;
  const dogfoodTmp = process.env.DOGFOOD_TMPDIR;
  if (
    (dogfoodRoot && path.resolve(dogfoodRoot) !== root) ||
    (dogfoodTmp && path.resolve(dogfoodTmp, "browser-ownership") !== root)
  ) {
    throw new Error(
      "Use the shared BROWSER_OWNERSHIP_DIR; role-specific ownership directories cannot differ."
    );
  }
  await fs.mkdir(root, { mode: 0o700, recursive: true });
  await fs.chmod(root, 0o700);
  if (
    await fs.lstat(path.join(root, "acquire.lock")).catch((error) => {
      if (error.code !== "ENOENT") {
        throw error;
      }
      return null;
    })
  ) {
    throw new Error(
      `Legacy acquisition lock at ${root}/acquire.lock. Finish the old managed consumers before cutover; the lock was preserved.`
    );
  }
  // A pipe keeps flock alive only while this process owns the operation.
  // Unlike a PID-directory lock, it is also released after an abrupt exit.
  const guard = spawn(
    process.env.MANAGED_CHROME_FLOCK || "flock",
    [
      "--exclusive",
      "--wait",
      "5",
      path.join(root, "ownership.lock"),
      process.execPath,
      "-e",
      "process.stdout.write('locked\\n'); process.stdin.resume()",
    ],
    { stdio: ["pipe", "pipe", "pipe"] }
  );
  let detail = "";
  guard.stderr.on("data", (chunk) => {
    detail += chunk;
  });
  const ended = once(guard, "close");
  guard.stdin.on("error", (error) => {
    detail ||= error.message;
  });
  try {
    await Promise.race([
      once(guard.stdout, "data"),
      ended.then(() => {
        throw new Error(`Ownership lock unavailable: ${detail}`);
      }),
    ]);
    return await action();
  } finally {
    guard.stdin.end();
    await ended;
  }
};

const conflict = (owner) =>
  new Error(
    `Managed ${owner.role} Chrome is already owned by '${owner.id}' in '${owner.workspace}'. Close that consumer, then run managed-chrome-owner recover if ownership remains.`
  );

const matching = (owner, token) => {
  if (!owner || owner.token !== token) {
    throw new Error("Ownership changed; refusing an outdated request.");
  }
  return owner;
};

const probe = async (owner) => {
  const prefix = owner.role === "playwright" ? "PWCLI" : "DOGFOOD";
  const filename =
    owner.role === "playwright" ? "windows.ps1" : "dogfood-chrome-windows.ps1";
  let script =
    process.env[`${prefix}_WINDOWS_SCRIPT`] ||
    fileURLToPath(new URL(filename, import.meta.url));
  if (!/^[A-Za-z]:/u.test(script)) {
    const converted = await exec(
      process.env[`${prefix}_WSLPATH`] || "wslpath",
      ["-w", script]
    );
    script = converted.stdout.trim();
  }
  const args = [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    script,
    "-Action",
    "Inspect",
  ];
  if (owner.role === "dogfood") {
    args.push(
      "-RunId",
      owner.id,
      "-ProfileDir",
      owner.profile,
      "-DebugPort",
      new URL(owner.endpoint).port
    );
  }
  const result = await exec(
    process.env[`${prefix}_POWERSHELL`] || "powershell.exe",
    args,
    { timeout: 15_000 }
  );
  const status = result.stdout.trim();
  if (
    status === "absent" ||
    /^managed:(?:headless|headed):[1-9][0-9]*$/u.test(status)
  ) {
    return status;
  }
  throw new Error(
    `Chrome state is unconfirmed (${status || "empty response"}); ownership was preserved.`
  );
};

const runStartup = async (token, [program, ...args]) => {
  if (!program) {
    throw new Error("run requires a startup command after --");
  }
  await locked(async () => {
    const owner = matching(await readOwner(), token);
    if (owner.phase !== "reserved") {
      throw new Error("Only a new reservation can start Chrome.");
    }
    await writeOwner({ ...owner, phase: "starting" });
  });
  let result;
  let failure;
  try {
    result = await exec(program, args, { maxBuffer: 2 * 1024 * 1024 });
  } catch (error) {
    failure = error;
  }
  // A killed supervisor must leave an uncertain launch reserved. A completed
  // command (including a nonzero exit) can no longer initiate another launch.
  if (!failure || Number.isInteger(failure.code)) {
    await locked(async () => {
      const owner = matching(await readOwner(), token);
      await writeOwner({ ...owner, phase: "settled" });
    });
  }
  if (failure) {
    throw failure instanceof Error ? failure : new Error(String(failure));
  }
  return result.stdout.trim();
};

const activate = async (owner, token) => {
  matching(owner, token);
  if (!["settled", "active"].includes(owner.phase)) {
    throw new Error("Startup has not completed.");
  }
  const status = await probe(owner);
  const [, mode, pid] = status.split(":");
  if (
    status === "absent" ||
    mode !== owner.mode ||
    (owner.browserPid && owner.browserPid !== Number(pid))
  ) {
    throw new Error(
      "The requested Chrome is not running; ownership was preserved."
    );
  }
  await writeOwner({ ...owner, browserPid: Number(pid), phase: "active" });
};

const release = async (owner, token, command) => {
  if (!owner && command === "recover") {
    return;
  }
  if (command === "release") {
    matching(owner, token);
  }
  if (owner.phase === "starting") {
    throw new Error(
      "Startup is still in progress or unconfirmed; ownership was preserved."
    );
  }
  if (
    command === "recover" &&
    owner.phase === "reserved" &&
    (await callerAlive(owner))
  ) {
    throw new Error(
      "A live startup reservation exists; ownership was preserved."
    );
  }
  const status = await probe(owner);
  if (status !== "absent") {
    throw new Error(
      "Chrome is still running; ownership was preserved. Close it, then run managed-chrome-owner recover."
    );
  }
  await fs.unlink(ownerFile);
};

const reserve = async (owner, values) => {
  if (owner) {
    if (
      owner.role === "playwright" &&
      values.role === owner.role &&
      values.token === owner.token &&
      owner.phase === "active"
    ) {
      return owner.token;
    }
    throw conflict(owner);
  }
  if (
    !["playwright", "dogfood"].includes(values.role) ||
    !values.id ||
    !values.profile ||
    !validEndpoint(values.endpoint) ||
    !["headless", "headed"].includes(values.mode)
  ) {
    throw new Error("reserve requires role, id, mode, profile and endpoint");
  }
  const caller = await processIdentity(Number(values.pid));
  if (!caller) {
    throw new Error("reserve requires the live caller's --pid");
  }
  const reservation = {
    browserPid: null,
    caller,
    endpoint: values.endpoint,
    id: values.id,
    mode: values.mode,
    phase: "reserved",
    profile: values.profile,
    role: values.role,
    token: randomUUID(),
    version: 1,
    workspace: process.cwd(),
  };
  await writeOwner(reservation);
  return reservation.token;
};

const main = () => {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: Object.fromEntries(
      ["role", "id", "pid", "mode", "profile", "endpoint", "token"].map(
        (key) => [key, { type: "string" }]
      )
    ),
  });
  const [command, token, ...startup] = positionals;
  if (command === "run") {
    return runStartup(token, startup);
  }
  return locked(async () => {
    const owner = await readOwner();
    if (command === "status") {
      return JSON.stringify(owner);
    }
    if (command === "check") {
      if (
        owner &&
        (owner.role !== values.role || owner.token !== values.token)
      ) {
        throw conflict(owner);
      }
      return;
    }
    if (command === "activate") {
      return activate(owner, token);
    }
    if (command === "release" || command === "recover") {
      return release(owner, token, command);
    }
    if (command === "reserve") {
      return reserve(owner, values);
    }
    throw new Error(
      "Use status, reserve, run, activate, release, check or recover."
    );
  });
};

try {
  const result = await main();
  if (result !== undefined) {
    process.stdout.write(`${result}\n`);
  }
} catch (error) {
  process.stderr.write(`managed-chrome-owner: ${error.message}\n`);
  process.exitCode = 1;
}
