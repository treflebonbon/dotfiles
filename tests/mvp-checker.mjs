import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const checker = fileURLToPath(
  new URL(
    "../docs/evaluations/mvp-mediator-evaluation-v10/check-device.mjs",
    import.meta.url
  )
);
// Kept under the test runner's temporary directory; no repository artifacts are changed.
const directory = mkdtempSync(path.join(tmpdir(), "mvp-checker-"));
const reference = `import * as base from ${JSON.stringify(new URL("fixtures/mvp-device.mjs", import.meta.url).href)};
export const initial = () => structuredClone(base.initial());
export const observe = base.observe;
`;
let sequence = 0;
const run = (source, ...args) => {
  const model = path.join(directory, `model-${sequence}.mjs`);
  sequence += 1;
  writeFileSync(model, source);
  const result = spawnSync(process.execPath, [checker, model, ...args], {
    encoding: "utf-8",
    timeout: 10_000,
  });
  assert.equal(result.error, undefined);
  return { exit: result.status, report: JSON.parse(result.stdout) };
};

test("unsupported opaque state is one contract error, not 52 mutation failures", () => {
  const result = run(
    "export const initial = () => Object.freeze(Object.create(null)); export const transition = s => ({state:s,effects:[]}); export const observe = () => ({});"
  );
  assert.equal(result.exit, 1);
  assert.equal(result.report.status, "contract-error");
  assert.equal(result.report.executed, 0);
  assert.equal(result.report.notRun, 52);
  assert.equal(result.report.failures.length, 0);
  assert.match(result.report.error, /initial.*plain object/u);
});

test("plain and frozen state retain all 52 cases and the known-bug negative control", () => {
  for (const source of [
    `${reference}export const transition = base.transition;`,
    `export * from ${JSON.stringify(new URL("fixtures/mvp-device.mjs", import.meta.url).href)};`,
  ]) {
    const result = run(source);
    assert.equal(result.exit, 0);
    assert.equal(result.report.passed, 52);
    assert.equal(result.report.notRun, 0);
    const mutant = run(source, "--known-bug");
    assert.equal(mutant.exit, 1);
    assert.ok(mutant.report.failures.length > 0);
  }
});

test("same-input nondeterminism is detected even when the returned object is reused", () => {
  const result = run(
    `${reference}
    let counter = 0;
    const output = {};
    export function transition(state, event) {
      const next = base.transition(state, event);
      output.state = {...next.state, counter: ++counter};
      output.effects = next.effects;
      return output;
    }
  `
  );
  assert.equal(result.exit, 1);
  assert.match(result.report.failures[0].error, /deterministic/u);
});

test("input mutations hidden from observe are caught on either invocation", () => {
  for (const condition of ["true", "++calls % 2 === 0"]) {
    const result = run(
      `${reference}
      let calls = 0;
      export function transition(state, event) {
        const next = base.transition(state, event);
        if (${condition}) state.next += 1;
        return next;
      }
    `
    );
    assert.equal(result.exit, 1);
    assert.match(result.report.failures[0].error, /mutated its input/u);
  }
});

test("all unsupported data shapes identify a contract error without invoking accessors", () => {
  for (const expression of [
    "{value: undefined}",
    "{value: NaN}",
    "{value: Infinity}",
    "{value: 1n}",
    "{value: Symbol()}",
    "{value() {}}",
    "new Map()",
    "new Set()",
    "new Date()",
    "new (class State {})()",
    "{[Symbol()]: 1}",
    "Object.create(null)",
    "Object.defineProperty({}, 'hidden', {value: 1})",
    "{get value() {throw new Error('accessor must not run')}}",
    "Array(1)",
    "Object.assign([], {extra: 1})",
  ]) {
    const result = run(
      `${
        reference
      }export function transition() { return {state: ${expression}, effects: []}; }`
    );
    assert.equal(result.exit, 1, expression);
    assert.equal(result.report.status, "contract-error", expression);
    assert.equal(result.report.executed, 1);
    assert.equal(result.report.notRun, 51);
    assert.match(result.report.error, /transition.state/u);
    assert.doesNotMatch(result.report.error, /accessor must not run/u);
  }
  const cyclic = run(
    `${
      reference
    }export function transition() {const state = {}; state.self = state; return {state,effects:[]};}`
  );
  assert.match(cyclic.report.error, /cyclic state/u);
});

test("model initialization errors and unavailable checker inputs are distinguished", () => {
  const broken = run(
    "export const initial = () => {throw new Error('initial failed')}; export const transition = () => {}; export const observe = () => ({});"
  );
  assert.equal(broken.exit, 1);
  assert.equal(broken.report.status, "model-error");
  assert.equal(broken.report.executed, 0);
  assert.equal(broken.report.notRun, 52);
  const missing = spawnSync(
    process.execPath,
    [checker, path.join(directory, "missing.mjs")],
    { encoding: "utf-8" }
  );
  assert.equal(missing.status, 1);
  assert.equal(JSON.parse(missing.stdout).status, "checker-error");
});

test("a checker failure during a case aborts remaining cases instead of reporting model failures", () => {
  const result = run(`
    export * from ${JSON.stringify(new URL("fixtures/mvp-device.mjs", import.meta.url).href)};
    globalThis.structuredClone = () => { throw new Error("snapshot unavailable"); };
  `);
  assert.equal(result.exit, 1);
  assert.equal(result.report.status, "checker-error");
  assert.equal(result.report.executed, 1);
  assert.equal(result.report.completed, 0);
  assert.equal(result.report.failures.length, 0);
  assert.equal(result.report.notRun, 51);
  assert.match(result.report.error, /snapshot unavailable/u);
});
