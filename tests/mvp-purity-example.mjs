import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const skill = readFileSync(
  new URL(
    "../local-skills/mvp-mediator-architecture/SKILL.md",
    import.meta.url
  ),
  "utf-8"
);

test("documented purity example accepts pure transitions and rejects changes on either call", () => {
  const example = skill.match(/```js\n(?<example>[\s\S]*?)\n\s*```/u)?.groups
    ?.example;
  assert.ok(example, "the skill must supply its executable comparison example");
  const check = (transition) =>
    runInNewContext(example, {
      assertEqual: assert.deepStrictEqual,
      event: { type: "start" },
      snapshot: structuredClone,
      state: { count: 0 },
      transition,
    });
  check((state) => ({ effects: [], state: { count: state.count + 1 } }));

  let calls = 0;
  assert.throws(
    () =>
      check((state) => {
        calls += 1;
        state.count = calls % 2;
        return { effects: [], state: { count: 0 } };
      }),
    { code: "ERR_ASSERTION" }
  );
  assert.equal(
    calls,
    1,
    "reject the first mutation before a second call can restore the input"
  );

  calls = 0;
  assert.throws(
    () =>
      check((state) => {
        calls += 1;
        if (calls === 2) {
          state.count = 1;
        }
        return { effects: [], state: { count: 0 } };
      }),
    { code: "ERR_ASSERTION" }
  );

  let sequence = 0;
  assert.throws(
    () =>
      check(() => {
        sequence += 1;
        return { effects: [], state: { count: sequence } };
      }),
    { code: "ERR_ASSERTION" }
  );

  const reused = { effects: [], state: { count: 0 } };
  assert.throws(
    () =>
      check(() => {
        reused.effects.push("command");
        return reused;
      }),
    { code: "ERR_ASSERTION" }
  );
});
