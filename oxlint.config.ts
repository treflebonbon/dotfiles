import { defineConfig } from "oxlint";

import { projectIgnorePatterns } from "./project-ignore-patterns.ts";
import core from "./scripts/vendor/ultracite/config/oxlint/core/index.mjs";

export default defineConfig({
  extends: [core],
  ignorePatterns: [...(core.ignorePatterns ?? []), ...projectIgnorePatterns],
});
