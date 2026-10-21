import { defineConfig } from "oxfmt";

import { projectIgnorePatterns } from "./project-ignore-patterns.ts";
import ultracite from "./scripts/vendor/ultracite/config/oxfmt/index.mjs";

export default defineConfig({
  ...ultracite,
  ignorePatterns: [
    ...(ultracite.ignorePatterns ?? []),
    ...projectIgnorePatterns,
  ],
});
