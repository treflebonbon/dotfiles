import { defineConfig } from "oxlint";
import core from "ultracite/oxlint/core";

import { projectIgnorePatterns } from "./project-ignore-patterns.ts";

export default defineConfig({
  extends: [core],
  ignorePatterns: [...(core.ignorePatterns ?? []), ...projectIgnorePatterns],
});
