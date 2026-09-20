import assert from "node:assert/strict";
import path from "node:path";
import { pathToFileURL } from "node:url";

const model = await import(pathToFileURL(path.resolve(process.argv[2])).href);
const mutant = process.argv.includes("--known-bug");
const results = [];
const targets = ["recording", "calibration"];

const session = () => {
  let state = model.initial();
  const commands = [];
  const ids = new Set();
  const acquiring = new Map();
  const view = () => model.observe(state);
  const send = (event) => {
    const before = structuredClone(state);
    const prior = view();
    // Negative control: reproduce the prior memo's in-flight-target no-op bug.
    const swallow =
      mutant &&
      prior.phase === "acquiring" &&
      event.type === "start" &&
      event.target === acquiring.get(prior.operationId);
    const out = swallow
      ? { effects: [], state }
      : model.transition(state, event);
    assert.deepEqual(state, before, "transition mutated its input");
    assert.ok(Array.isArray(out.effects));
    ({ state } = out);
    for (const effect of out.effects) {
      assert.ok(["acquire", "stop", "release"].includes(effect.type));
      assert.ok(targets.includes(effect.target));
      assert.ok(
        effect.id !== null && effect.id !== undefined && !ids.has(effect.id),
        "reused execution ID"
      );
      ids.add(effect.id);
      if (effect.type === "acquire") {
        assert.equal(view().owner, null, "acquired before release");
        acquiring.set(effect.id, effect.target);
      }
      commands.push(effect);
    }
    return out.effects;
  };
  const complete = (type = "ok") => send({ id: view().operationId, type });
  return { commands, complete, send, view };
};

const test = (name, check) => {
  try {
    check();
    results.push({ name, pass: true });
  } catch (error) {
    results.push({ error: error.message, name, pass: false });
  }
};

const waiting = (phase) => {
  const s = session();
  s.send({ target: "recording", type: "start" });
  if (phase !== "acquiring") {
    s.complete();
    s.send({ target: "calibration", type: "start" });
    if (phase === "releasing") {
      s.complete();
    }
  }
  assert.equal(s.view().phase, phase);
  return s;
};

const sequences = [[]];
for (let length = 1; length <= 3; length += 1) {
  for (const seq of sequences.filter((entry) => entry.length === length - 1)) {
    for (const target of targets) {
      sequences.push([...seq, target]);
    }
  }
}

for (const phase of ["acquiring", "stopping", "releasing"]) {
  for (const sequence of sequences) {
    test(`${phase}: ${sequence.join(" -> ") || "normal"}`, () => {
      const s = waiting(phase);
      const id = s.view().operationId;
      const expected = sequence.at(-1) ?? s.view().desired;
      for (const target of sequence) {
        assert.deepEqual(s.send({ target, type: "start" }), []);
        assert.equal(s.view().operationId, id);
        assert.equal(s.view().desired, target);
      }
      for (let n = 0; s.view().phase !== "active" && n < 8; n += 1) {
        s.complete();
      }
      assert.equal(s.view().phase, "active");
      assert.equal(s.view().owner, expected);
    });
  }
  test(`${phase}: stale/profile notifications`, () => {
    const s = waiting(phase);
    const before = structuredClone(s.view());
    for (const event of [
      { id: "stale", type: "ok" },
      { id: "stale", type: "fail" },
      { type: "profile" },
    ]) {
      assert.deepEqual(s.send(event), []);
      assert.deepEqual(s.view(), before);
    }
  });
}

for (const phase of ["stopping", "releasing"]) {
  test(`${phase}: failure blocks until explicit retry`, () => {
    const s = waiting(phase);
    const failedId = s.view().operationId;
    assert.deepEqual(s.complete("fail"), []);
    assert.equal(s.view().phase, "blocked");
    assert.equal(s.view().owner, "recording");
    for (const target of ["recording", "calibration", "recording"]) {
      assert.deepEqual(s.send({ target, type: "start" }), []);
      assert.equal(s.view().phase, "blocked");
      assert.equal(s.view().desired, target);
    }
    const effects = s.send({ type: "retry" });
    assert.equal(effects.length, 1);
    assert.equal(effects[0].type, phase === "stopping" ? "stop" : "release");
    assert.notEqual(effects[0].id, failedId);
    const before = structuredClone(s.view());
    assert.deepEqual(s.send({ id: failedId, type: "ok" }), []);
    assert.deepEqual(s.view(), before);
    for (let n = 0; s.view().phase !== "active" && n < 8; n += 1) {
      s.complete();
    }
    assert.equal(s.view().owner, "recording");
  });
}

test("stop then release then acquire", () => {
  const s = waiting("stopping");
  assert.equal(s.view().owner, "recording");
  assert.equal(s.complete()[0].type, "release");
  assert.equal(s.view().owner, "recording");
  assert.equal(s.complete()[0].type, "acquire");
  assert.equal(s.view().owner, null);
  s.complete();
  assert.equal(s.view().owner, "calibration");
  assert.deepEqual(s.send({ target: "calibration", type: "start" }), []);
});

test("acquisition failure has no automatic retry", () => {
  const s = waiting("acquiring");
  s.send({ target: "calibration", type: "start" });
  assert.deepEqual(s.complete("fail"), []);
  assert.equal(s.view().phase, "idle");
  assert.equal(s.view().owner, null);
});

console.log(
  JSON.stringify(
    {
      failures: results.filter((r) => !r.pass),
      negativeControl: mutant,
      passed: results.filter((r) => r.pass).length,
      total: results.length,
    },
    null,
    2
  )
);
process.exitCode = results.some((r) => !r.pass) ? 1 : 0;
