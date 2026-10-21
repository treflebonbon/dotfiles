import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import nodePath from "node:path";

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "--help") {
  console.log("使い方: bun scripts/check-registry-locks.js [--staged]");
  console.log(
    "bun.lock と tracked な npm package-lock.json の取得先を検査します。"
  );
  process.exit(0);
}
if (args.length > 1 || (args.length === 1 && args[0] !== "--staged")) {
  console.error("使い方: bun scripts/check-registry-locks.js [--staged]");
  process.exit(2);
}

const staged = args[0] === "--staged";
const errors = [];

const git = (argv) => {
  const result = spawnSync("git", argv, { encoding: "buffer" });
  if (result.error || result.status !== 0) {
    throw new Error("Git の index を読み取れません");
  }
  return result.stdout;
};

const officialRegistry = (value, packageSource = false) => {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.hostname === "registry.npmjs.org" &&
      !url.port &&
      !url.username &&
      !url.password &&
      !url.search &&
      !url.hash &&
      (packageSource ? url.pathname !== "/" : url.pathname === "/")
    );
  } catch {
    return false;
  }
};

const textOf = (filePath) => {
  let bytes;
  try {
    bytes = staged
      ? git(["show", `:${filePath}`])
      : readFileSync(nodePath.resolve(filePath));
  } catch {
    errors.push(
      `${filePath}: ${staged ? "Git index" : "working tree"}から読み取れません`
    );
    return null;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    errors.push(`${filePath}: UTF-8として読み取れません`);
    return null;
  }
};

const checkBunfig = () => {
  const source = textOf("bunfig.toml");
  if (source === null) {
    return;
  }
  let config;
  try {
    config = Bun.TOML.parse(source);
  } catch {
    errors.push("bunfig.toml: TOMLを解析できません");
    return;
  }
  if (
    !config.install ||
    typeof config.install !== "object" ||
    !officialRegistry(config.install.registry)
  ) {
    errors.push(
      "bunfig.toml: [install].registry は公式 npm registry を一つだけ指定してください"
    );
  }
};

const checkNpmrc = () => {
  const path = "tests/experiments/rop-analysis/.npmrc";
  const source = textOf(path);
  if (source === null) {
    return;
  }
  let malformed = false;
  const registries = [];
  for (const line of source.split(/\r?\n/u).map((value) => value.trim())) {
    if (!line || line.startsWith("#")) {
      continue;
    }
    const setting = line.match(
      /^(?<key>(?:@[^:]+:)?registry)\s*=\s*(?<value>.*?)\s*$/u
    );
    if (setting) {
      registries.push([
        setting.groups.key,
        setting.groups.value.replace(/\s+#.*$/u, "").trim(),
      ]);
    } else if (/^(?:@[^:]+:)?registry\b/iu.test(line)) {
      malformed = true;
    }
  }
  const defaults = registries.filter(([key]) => key === "registry");
  if (
    malformed ||
    defaults.length !== 1 ||
    registries.some(([, value]) => !officialRegistry(value))
  ) {
    errors.push(
      `${path}: registry は公式 npm registry を一つだけ指定してください`
    );
  }
};

const checkBunLock = () => {
  const source = textOf("bun.lock");
  if (source === null) {
    return;
  }
  let lock;
  try {
    lock = Bun.JSONC.parse(source);
  } catch {
    errors.push("bun.lock: JSONCを解析できません");
    return;
  }
  if (
    !lock ||
    typeof lock !== "object" ||
    Array.isArray(lock) ||
    lock.lockfileVersion !== 1 ||
    !lock.packages ||
    typeof lock.packages !== "object" ||
    Array.isArray(lock.packages)
  ) {
    errors.push("bun.lock: 未対応のlockfile構造です");
    return;
  }
  for (const [name, entry] of Object.entries(lock.packages)) {
    if (
      !Array.isArray(entry) ||
      typeof entry[0] !== "string" ||
      typeof entry[1] !== "string"
    ) {
      errors.push(`bun.lock: ${name} の取得元形式は未対応です`);
    } else if (entry[1] !== "" && !officialRegistry(entry[1], true)) {
      errors.push(`bun.lock: ${name} は公式 npm registry 以外を参照しています`);
    }
  }
};

const checkNpmLock = (filePath) => {
  const source = textOf(filePath);
  if (source === null) {
    return;
  }
  let lock;
  try {
    lock = JSON.parse(source);
  } catch {
    errors.push(`${filePath}: JSONを解析できません`);
    return;
  }
  if (
    !lock ||
    lock.lockfileVersion !== 3 ||
    !lock.packages ||
    typeof lock.packages !== "object" ||
    Array.isArray(lock.packages)
  ) {
    errors.push(`${filePath}: npm package-lock v3 以外の形式は未対応です`);
    return;
  }
  for (const [name, entry] of Object.entries(lock.packages)) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(
        `${filePath}: ${name || "root"} のpackage entry形式は未対応です`
      );
    } else if (!Object.hasOwn(entry, "resolved")) {
      if (
        name.startsWith("node_modules/") &&
        entry.link !== true &&
        entry.inBundle !== true
      ) {
        errors.push(`${filePath}: ${name} に resolved がありません`);
      }
    } else if (
      typeof entry.resolved !== "string" ||
      !officialRegistry(entry.resolved, true)
    ) {
      errors.push(
        `${filePath}: ${name || "root"} は公式 npm registry 以外を参照しています`
      );
    }
  }
};

let paths;
try {
  process.chdir(git(["rev-parse", "--show-toplevel"]).toString("utf-8").trim());
  paths = git([
    "ls-files",
    "--cached",
    "-z",
    "--",
    "bun.lock",
    "package-lock.json",
    "**/package-lock.json",
  ])
    .toString("utf-8")
    .split("\0")
    .filter(Boolean);
} catch {
  console.error("registry-locks: Git worktree を確認できません");
  process.exit(2);
}

if (!paths.includes("bun.lock")) {
  errors.push("bun.lock: tracked lockfile がありません");
}
checkBunfig();
checkNpmrc();
checkBunLock();
const npmLockPaths = paths.filter(
  (name) => name === "package-lock.json" || name.endsWith("/package-lock.json")
);
for (const path of npmLockPaths) {
  checkNpmLock(path);
}

if (errors.length) {
  for (const error of errors) {
    console.error(`registry-locks: ${error}`);
  }
  process.exit(1);
}
console.log(
  `registry-locks: bun.lock と ${npmLockPaths.length} 個の npm lockfile は公式 registry を参照しています`
);
