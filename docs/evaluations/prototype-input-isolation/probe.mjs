// PROTOTYPE: run from any cwd. No LLM calls and no changes to existing evaluations.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";

const dir = import.meta.dirname;
const root = path.resolve(dir, "../../..");
const sha = (data) => createHash("sha256").update(data).digest("hex");
const scratch = fs.mkdtempSync(
  path.join(os.tmpdir(), "evaluation-input-prototype-")
);
const snapshot = path.join(scratch, "inputs");
fs.mkdirSync(path.join(snapshot, "references"), { recursive: true });
const names = ["SKILL.md", "references/tanstack-effect.md", "task.txt"];
const pinned = {
  "SKILL.md":
    "b41003050263f896d24ffb101c4b61b4f94ff93a7f1fcbad98779945574d2c24",
  "references/tanstack-effect.md":
    "110b25b8ba320ac61ceb38c19142f5028aabfcc28a27cfd6b7a51b0eef288cca",
};
const expected = {};
for (const name of names) {
  const source = path.join(dir, "inputs", name);
  const stat = fs.lstatSync(source);
  assert.ok(
    stat.isFile() && stat.nlink === 1,
    "regular, non-hardlinked input required"
  );
  const bytes = fs.readFileSync(source);
  expected[name] = sha(bytes);
  if (pinned[name]) {
    assert.equal(expected[name], pinned[name]);
  }
  fs.writeFileSync(path.join(snapshot, name), bytes, { mode: 0o600 });
}
const manifest = () => {
  const found = {};
  for (const name of fs.readdirSync(snapshot, { recursive: true }).toSorted()) {
    const p = path.join(snapshot, name);
    const stat = fs.lstatSync(p);
    assert.ok(!stat.isSymbolicLink(), "symlink input rejected");
    if (stat.isDirectory()) {
      continue;
    }
    assert.ok(stat.isFile() && stat.nlink === 1, "non-regular input rejected");
    found[name] = sha(fs.readFileSync(p));
  }
  assert.deepEqual(found, expected, "input set or content changed");
  return sha(JSON.stringify(Object.entries(found).toSorted()));
};
const digest = manifest();
// vm loads the exact browser gate; it is NOT the isolation boundary.
const {
  groups: { gateSource },
} = fs
  .readFileSync(path.join(dir, "prototype.html"), "utf-8")
  .match(/<script id="gate">(?<gateSource>[\s\S]*?)<\/script>/u);
const Gate = vm.runInNewContext(`${gateSource}\nGate`);
const report = {
  cases: [],
  digest,
  expected,
  gate_sha256: sha(gateSource),
  launches: [],
  scratch,
  timestamp: new Date().toISOString(),
};
const command = (executable, args) => {
  const r = spawnSync(executable, args, { encoding: "utf-8", timeout: 30_000 });
  assert.equal(r.status, 0, r.stderr || String(r.error));
  return r.stdout.trim();
};
const python = fs.realpathSync(command("which", ["python3"]));
const bwrap = fs.realpathSync(command("which", ["bwrap"]));
const [pythonStore] = python.match(/^\/nix\/store\/[^/]+/u);
const closure = command("nix-store", [
  "--query",
  "--requisites",
  pythonStore,
]).split("\n");
report.runtime = { bwrap, closure, python };
const canary = path.join(scratch, "host-canary.txt");
fs.writeFileSync(canary, "synthetic-prototype-outside-inputs\n", {
  mode: 0o600,
});
const commonGit = command("git", ["-C", root, "rev-parse", "--git-common-dir"]);
const forbidden = {
  canary,
  git: path.resolve(root, commonGit, "HEAD"),
  previous_result: path.join(
    root,
    "docs/evaluations/mvp-mediator-evaluation-v2/run-20260921-01/results.md"
  ),
  source: path.join(root, "local-skills/mvp-mediator-architecture/SKILL.md"),
};
for (const target of Object.values(forbidden)) {
  assert.ok(fs.statSync(target).isFile());
}
report.host_canary_sha256 = sha(fs.readFileSync(canary));
const config = {
  expected,
  forbidden,
  host_network_namespace: fs.readlinkSync("/proc/self/ns/net"),
};
report.worker_sha256 = sha(fs.readFileSync(path.join(dir, "worker.py")));
report.probe_config = config;
const args = [
  "--unshare-all",
  "--die-with-parent",
  "--new-session",
  "--clearenv",
];
for (const dependency of closure) {
  args.push("--ro-bind", dependency, dependency);
}
args.push(
  "--proc",
  "/proc",
  "--dev",
  "/dev",
  "--tmpfs",
  "/tmp",
  "--dir",
  "/work",
  "--chdir",
  "/work",
  "--ro-bind",
  snapshot,
  "/inputs",
  "--ro-bind",
  path.join(dir, "worker.py"),
  "/worker.py",
  "--",
  python,
  "-I",
  "-S",
  "/worker.py"
);
const runWorker = (kind) => {
  const r = spawnSync(bwrap, args, {
    encoding: "utf-8",
    env: { PROTOTYPE_HOST_ONLY: "synthetic-host-environment-canary" },
    input: JSON.stringify(config),
    maxBuffer: 1024 * 1024,
    timeout: 30_000,
  });
  let output;
  try {
    output = JSON.parse(r.stdout);
  } catch {
    output = null;
  }
  const evidence = {
    command: [bwrap, ...args],
    error: r.error?.message,
    exit: r.status,
    kind,
    output,
    signal: r.signal,
    stderr: r.stderr,
  };
  report.launches.push(evidence);
  return evidence;
};
// Diagnostic preflight establishes boundary evidence; it is not an evaluation dispatch.
const preflight = runWorker("boundary-preflight");
const verified = (run) => {
  try {
    assert.equal(run.exit, 0);
    const o = run.output;
    assert.deepEqual(o.hashes, expected);
    assert.deepEqual(
      Object.keys(o.forbidden_reads).toSorted(),
      [
        ...Object.keys(forbidden),
        "symlink",
        "proc_root",
        "traversal",
      ].toSorted()
    );
    for (const r of Object.values(o.forbidden_reads)) {
      assert.equal(r.readable, false);
      assert.ok([2, 13].includes(r.errno));
    }
    assert.equal(o.input_write_errno, 30);
    assert.equal(o.environment_sentinel_visible, false);
    assert.notEqual(o.network_namespace, config.host_network_namespace);
    return true;
  } catch {
    return false;
  }
};
const boundaryValid = verified(preflight);
let actualDispatches = 0;
let state;
const reset = () => {
  state = { ...Gate.initial(), digest };
};
const act = (type, extra = {}) => {
  state = Gate.step(state, { type, ...extra });
};
const audit = (status = "valid") => {
  act("audit", {
    digest: manifest(),
    status: boundaryValid ? status : "unknown",
  });
};
const dispatch = (label, shouldLaunch) => {
  const before = actualDispatches;
  // Re-audit the concrete snapshot immediately before the gate, fail closed.
  try {
    act("input", { digest: manifest() });
  } catch {
    act("audit", { digest: null, status: "invalid" });
  }
  const oldStarted = state.started;
  act("dispatch");
  if (state.started > oldStarted) {
    actualDispatches += 1;
    const run = runWorker("gated-worker");
    if (!verified(run)) {
      act("audit", { digest, status: "invalid" });
    }
  }
  report.cases.push({
    after: actualDispatches,
    before,
    label,
    passed: actualDispatches - before === Number(shouldLaunch),
    state: { ...state },
  });
  assert.equal(actualDispatches - before, Number(shouldLaunch), label);
};
try {
  reset();
  dispatch("audit unknown: no process", false);
  assert.ok(
    boundaryValid,
    "boundary preflight failed; do not authorize evaluation"
  );
  reset();
  audit("invalid");
  dispatch("audit invalid: no process", false);
  audit();
  dispatch("invalid remains halted", false);
  reset();
  audit();
  state = { ...state, auditedDigest: "stale-digest" };
  dispatch("stale audit: no process", false);
  reset();
  audit();
  dispatch("valid audit: actual process starts", true);
  audit();
  dispatch("running: no overlapping process", false);
  act("finish");
  dispatch("finished but audit pending: no next process", false);
  audit();
  dispatch("new valid audit: second actual process starts", true);
  act("finish");
  audit("invalid");
  dispatch("invalid after completion: no next process", false);
  reset();
  audit();
  fs.writeFileSync(
    path.join(snapshot, "unexpected.txt"),
    "synthetic extra input"
  );
  dispatch("extra input after audit: no process", false);
  assert.equal(actualDispatches, 2);
  assert.ok(report.launches.every(verified));
  report.ok = true;
} catch (error) {
  report.ok = false;
  report.failure = error.message;
  process.exitCode = 1;
} finally {
  report.actual_dispatches = actualDispatches;
  report.scope =
    "Dedicated deterministic bwrap workers only; native collaboration and live LLM evaluation are not isolated by this entrypoint.";
  const output = process.argv[2]
    ? path.resolve(process.argv[2])
    : path.join(scratch, "evidence.json");
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, {
    flag: "wx",
  });
  console.log(
    JSON.stringify({
      cases: report.cases.length,
      dispatches: actualDispatches,
      evidence: output,
      ok: report.ok,
    })
  );
}
