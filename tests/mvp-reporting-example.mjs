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

test("reporting example checks stale state and empty effects at their own observation", () => {
  const section = skill.split("**根拠表の記入例**")[1]?.split("## ")[0];
  const example = section?.match(/```js\n(?<example>[\s\S]*?)\n```/u)?.groups
    ?.example;
  assert.ok(example, "the reporting section must contain its code example");
  const check = (staleEffects) =>
    runInNewContext(
      `
    const pending = { id: 2, phase: "pending" };
    const oldCompletion = { id: 1 };
    const currentCompletion = { id: 2 };
    const expectedCurrent = { id: 2, phase: "done" };
    const observe = (state) => state;
    const transition = (state, event) => event.id === state.id
      ? { state: { id: 2, phase: "done" }, effects: ["current effect is unchecked"] }
      : { state, effects: ${JSON.stringify(staleEffects)} };
    ${example}
  `,
      { assert }
    );
  check([]);
  assert.throws(() => check(["unexpected stale effect"]), {
    code: "ERR_ASSERTION",
  });
});
