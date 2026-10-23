import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

const digest = (data) =>
  `sha256:${createHash("sha256").update(data).digest("hex")}`;
const key = (dependency) =>
  JSON.stringify([dependency.repo_url, dependency.virtual_path ?? ""]);
const readYaml = (file) => Bun.YAML.parse(readFileSync(file, "utf-8"));
const sorted = (items) => [...items].toSorted();
const difference = (left, right) =>
  left.filter((item) => !right.includes(item));

const indexDependencies = (dependencies) => {
  assert.ok(Array.isArray(dependencies), "dependencies が配列ではありません");
  const indexed = new Map();
  for (const dependency of dependencies) {
    assert.ok(typeof dependency.repo_url === "string", "repo_url がありません");
    const identity = key(dependency);
    assert.ok(!indexed.has(identity), `dependency 重複: ${identity}`);
    indexed.set(identity, dependency);
  }
  return indexed;
};

const verifyFrontmatter = (bytes, file) => {
  const frontmatter = /^---\r?\n(?<metadata>[\s\S]*?)\r?\n---(?:\r?\n|$)/u.exec(
    bytes.toString("utf-8")
  );
  assert.ok(frontmatter, `SKILL frontmatter がありません: ${file}`);
  const metadata = Bun.YAML.parse(frontmatter.groups.metadata);
  for (const field of ["name", "description"]) {
    assert.ok(
      typeof metadata?.[field] === "string" && metadata[field].trim(),
      `SKILL ${field} 不正: ${file}`
    );
  }
};

const verifyUnchanged = (previous, dependency, identity) => {
  const floating = !previous.ref && !previous.resolved_ref;
  const fields = new Set([
    ...Object.keys(previous),
    ...Object.keys(dependency),
  ]);
  for (const field of fields) {
    if (field === "resolved_commit" && floating) {
      continue;
    }
    assert.ok(
      isDeepStrictEqual(dependency[field], previous[field]),
      `候補外の drift: ${identity} ${field}`
    );
  }
};

const verify = (baseFile, runtimeDirectory, planFile) => {
  const runtime = realpathSync(runtimeDirectory);
  const base = indexDependencies(readYaml(baseFile).dependencies);
  const candidate = indexDependencies(
    readYaml(path.join(runtime, "apm.lock.yaml")).dependencies
  );
  assert.ok(
    isDeepStrictEqual(sorted(candidate.keys()), sorted(base.keys())),
    "dependency の構成が変わっています"
  );
  const plans = indexDependencies(
    JSON.parse(readFileSync(planFile, "utf-8")).candidates
  );
  for (const identity of plans.keys()) {
    assert.ok(candidate.has(identity), `計画に未知の dependency: ${identity}`);
  }
  const skills = { ".agents": new Set(), ".claude": new Set() };
  const verifiedFiles = new Set();
  const retainedFiles = new Set(
    [...candidate.values()].flatMap((dependency) => dependency.deployed_files)
  );
  let added = 0;
  let removed = 0;
  for (const [identity, dependency] of candidate) {
    const previous = base.get(identity);
    const files = dependency.deployed_files;
    const hashes = dependency.deployed_file_hashes;
    assert.ok(
      Array.isArray(files) && new Set(files).size === files.length,
      `deployed_files 不正: ${identity}`
    );
    assert.ok(
      hashes && typeof hashes === "object" && !Array.isArray(hashes),
      `hash 台帳がありません: ${identity}`
    );
    const plan = plans.get(identity);
    if (plan) {
      for (const operation of ["added", "removed"]) {
        assert.ok(
          Array.isArray(plan[operation]) &&
            new Set(plan[operation]).size === plan[operation].length,
          `計画不正: ${operation}`
        );
      }
      const additions = difference(files, previous.deployed_files);
      const removals = difference(previous.deployed_files, files);
      assert.ok(
        isDeepStrictEqual(sorted(additions), sorted(plan.added)),
        `予定外の追加: ${identity}`
      );
      assert.ok(
        isDeepStrictEqual(sorted(removals), sorted(plan.removed)),
        `予定外の削除: ${identity}`
      );
      for (const file of removals) {
        assert.ok(
          retainedFiles.has(file) ||
            !lstatSync(path.resolve(runtime, file), { throwIfNoEntry: false }),
          `削除fileが残存: ${file}`
        );
      }
      added += additions.length;
      removed += removals.length;
    } else {
      verifyUnchanged(previous, dependency, identity);
    }
    for (const file of Object.keys(hashes)) {
      assert.ok(files.includes(file), `hash 台帳だけに存在: ${file}`);
    }
    for (const file of files) {
      const match =
        /^\.(?<target>agents|claude)\/skills\/(?<skill>[^/]+)(?:\/.*)?$/u.exec(
          file
        );
      assert.ok(
        match && !file.split("/").some((part) => part === ".." || part === "."),
        `配備先不正: ${file}`
      );
      const deployedPath = realpathSync(path.resolve(runtime, file));
      const location = path.relative(runtime, deployedPath);
      assert.ok(
        location !== ".." && !location.startsWith(`..${path.sep}`),
        `runtime 外の配備先: ${file}`
      );
      skills[`.${match.groups.target}`].add(match.groups.skill);
      if (statSync(deployedPath).isDirectory()) {
        assert.ok(!(file in hashes), `directory に file hash: ${file}`);
        continue;
      }
      assert.ok(
        statSync(deployedPath).isFile(),
        `通常 file ではありません: ${file}`
      );
      const bytes = readFileSync(deployedPath);
      // APM は lock に改行を LF へ正規化した hash を記録するが、配備 file は CRLF のまま残る。
      const actual = [
        digest(bytes),
        digest(
          Buffer.from(
            bytes.toString("latin1").replaceAll("\r\n", "\n"),
            "latin1"
          )
        ),
      ];
      assert.ok(actual.includes(hashes[file]), `file hash 不一致: ${file}`);
      verifiedFiles.add(file);
      if (file.endsWith("/SKILL.md")) {
        verifyFrontmatter(bytes, file);
      }
    }
  }
  for (const [target, expected] of Object.entries(skills)) {
    const directory = path.join(runtime, target, "skills");
    const discovered = readdirSync(directory).filter((name) =>
      statSync(path.join(directory, name)).isDirectory()
    );
    assert.ok(
      isDeepStrictEqual(sorted(discovered), sorted(expected)),
      `${target} の skill discovery 不一致`
    );
    for (const name of expected) {
      assert.ok(
        verifiedFiles.has(`${target}/skills/${name}/SKILL.md`),
        `未検証の SKILL.md: ${target}/${name}`
      );
    }
  }
  console.log(
    `PASS: dependency ${candidate.size}、skill .agents=${skills[".agents"].size} .claude=${skills[".claude"].size}、追加${added}・削除${removed}`
  );
};

try {
  assert.equal(
    process.argv.length,
    5,
    "使用法: bun scripts/verify-apm-deployment.mjs BASE_LOCK RUNTIME PLAN.json"
  );
  verify(...process.argv.slice(2));
} catch (error) {
  console.error(`REJECT: ${error.message}`);
  process.exitCode = 1;
}
