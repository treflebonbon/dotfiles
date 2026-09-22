import assert from "node:assert/strict";
import path from "node:path";
import { pathToFileURL } from "node:url";

class EvaluationError extends Error {
  constructor(kind, message, options) {
    super(message, options);
    this.name = "EvaluationError";
    this.kind = kind;
  }
}

const validateState = (value, location, ancestors = new Set()) => {
  const require = (condition, reason) => {
    if (!condition) {
      throw new EvaluationError("contract-error", `${location}: ${reason}`);
    }
  };
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return;
  }
  if (typeof value === "number") {
    require(Number.isFinite(value), "finite number required");
    return;
  }
  require(typeof value === "object", "plain data required");
  const array = Array.isArray(value);
  require(Object.getPrototypeOf(value) ===
    (array
      ? Array.prototype
      : Object.prototype), "plain object or ordinary array required");
  require(!ancestors.has(value), "cyclic state");
  ancestors.add(value);
  const keys = Reflect.ownKeys(value);
  if (array) {
    require(keys.length ===
      value.length + 1, "dense array without extra properties required");
  }
  for (const key of keys) {
    if (array && key === "length") {
      continue;
    }
    require(typeof key === "string", "string keys required");
    if (array) {
      require(/^(?:0|[1-9][0-9]*)$/u.test(key) &&
        Number(key) < value.length, "array index required");
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    require(descriptor.enumerable &&
      Object.hasOwn(descriptor, "value"), "enumerable data property required");
    validateState(descriptor.value, `${location}.${key}`, ancestors);
  }
  ancestors.delete(value);
};

const mutant = process.argv.includes("--known-bug");
const results = [];
const targets = ["recording", "calibration"];
let fatal;
let executed = 0;
try {
  const model = await import(pathToFileURL(path.resolve(process.argv[2])).href);
  for (const name of ["initial", "transition", "observe"]) {
    if (typeof model[name] !== "function") {
      throw new EvaluationError(
        "contract-error",
        `${name}: function export required`
      );
    }
  }
  const invoke = (name, ...args) => {
    try {
      return model[name](...args);
    } catch (error) {
      throw new EvaluationError(
        "model-error",
        `${name}: ${error?.message ?? String(error)}`,
        {
          cause: error,
        }
      );
    }
  };
  validateState(invoke("initial"), "initial");
  const session = () => {
    let state = invoke("initial");
    validateState(state, "initial");
    const commands = [];
    const ids = new Set();
    const acquiring = new Map();
    const view = () => invoke("observe", state);
    const send = (event) => {
      const before = structuredClone(state);
      const prior = view();
      // Negative control: reproduce the prior memo's in-flight-target no-op bug.
      const swallow =
        mutant &&
        prior.phase === "acquiring" &&
        event.type === "start" &&
        event.target === acquiring.get(prior.operationId);
      const call = () => {
        const result = swallow
          ? { effects: [], state }
          : invoke("transition", state, event);
        validateState(state, "input after transition");
        assert.deepEqual(state, before, "transition mutated its input");
        if (
          !result ||
          !Object.hasOwn(result, "state") ||
          !Array.isArray(result.effects)
        ) {
          throw new EvaluationError(
            "contract-error",
            "transition: { state, effects: array } required"
          );
        }
        validateState(result.state, "transition.state");
        validateState(result.effects, "transition.effects");
        return { effects: result.effects, state: result.state };
      };
      const out = call();
      // Snapshot before repeating: a model may reuse and overwrite the returned object.
      const first = structuredClone(out);
      assert.deepEqual(call(), first, "transition was not deterministic");
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
    if (fatal) {
      return;
    }
    executed += 1;
    try {
      check();
      results.push({ name, pass: true });
    } catch (error) {
      let kind = "checker-error";
      if (error instanceof EvaluationError) {
        ({ kind } = error);
      } else if (error instanceof assert.AssertionError) {
        kind = "model-failure";
      }
      if (kind === "checker-error") {
        fatal = { case: name, error: error.message, status: kind };
        return;
      }
      results.push({ error: error.message, kind, name, pass: false });
      if (kind === "contract-error") {
        fatal = { error: error.message, status: kind };
      }
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
    for (const seq of sequences.filter(
      (entry) => entry.length === length - 1
    )) {
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
} catch (error) {
  fatal = {
    error: error.message,
    status: error instanceof EvaluationError ? error.kind : "checker-error",
  };
}
const failures = results.filter((r) => !r.pass);
console.log(
  JSON.stringify(
    {
      ...fatal,
      completed: results.length,
      executed,
      failures,
      negativeControl: mutant,
      notRun: 52 - executed,
      passed: results.filter((r) => r.pass).length,
      status: fatal?.status ?? (failures.length ? "fail" : "pass"),
      total: 52,
    },
    null,
    2
  )
);
process.exitCode = fatal || failures.length ? 1 : 0;
