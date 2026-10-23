// 2 つの APM lock の差分から verify-apm-deployment.mjs 用の PLAN_JSON 下書きを標準出力へ出す。
// 候補は「floating の resolved_commit だけが前進した場合を除き、いずれかの field が変わった dependency」で、
// verifier の候補外 drift 判定と同じ基準にする。出力は人が確認してから verifier へ渡す。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";

const key = (dependency) =>
  JSON.stringify([dependency.repo_url, dependency.virtual_path ?? ""]);
const readYaml = (file) => Bun.YAML.parse(readFileSync(file, "utf-8"));
const sorted = (items) => [...items].toSorted();
const difference = (left, right) =>
  left.filter((item) => !right.includes(item));

const indexDependencies = (lock, label) => {
  assert.ok(
    Array.isArray(lock?.dependencies),
    `${label}: dependencies が配列ではありません`
  );
  const indexed = new Map();
  for (const dependency of lock.dependencies) {
    assert.ok(
      typeof dependency.repo_url === "string",
      `${label}: repo_url がありません`
    );
    const identity = key(dependency);
    assert.ok(!indexed.has(identity), `${label}: dependency 重複: ${identity}`);
    indexed.set(identity, dependency);
  }
  return indexed;
};

const changed = (previous, dependency) => {
  const floating = !previous.ref && !previous.resolved_ref;
  const fields = new Set([
    ...Object.keys(previous),
    ...Object.keys(dependency),
  ]);
  return [...fields].some(
    (field) =>
      !(field === "resolved_commit" && floating) &&
      !isDeepStrictEqual(dependency[field], previous[field])
  );
};

const plan = (baseFile, candidateFile) => {
  const base = indexDependencies(readYaml(baseFile), "base");
  const candidate = indexDependencies(readYaml(candidateFile), "candidate");
  assert.ok(
    isDeepStrictEqual(sorted(candidate.keys()), sorted(base.keys())),
    "dependency の構成が変わっています"
  );
  const candidates = [];
  for (const [identity, dependency] of candidate) {
    const previous = base.get(identity);
    if (!changed(previous, dependency)) {
      continue;
    }
    const before = previous.deployed_files ?? [];
    const after = dependency.deployed_files ?? [];
    const [repo_url, virtual_path] = JSON.parse(identity);
    candidates.push({
      added: sorted(difference(after, before)),
      removed: sorted(difference(before, after)),
      repo_url,
      virtual_path,
    });
  }
  return { candidates };
};

const [baseFile, candidateFile, ...rest] = process.argv.slice(2);
if (!baseFile || !candidateFile || rest.length > 0) {
  console.error("Usage: plan-apm-deployment.mjs BASE_LOCK CANDIDATE_LOCK");
  process.exit(2);
}
try {
  console.log(JSON.stringify(plan(baseFile, candidateFile), null, 2));
} catch (error) {
  console.error(`REJECT: ${error.message}`);
  process.exit(1);
}
