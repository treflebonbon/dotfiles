import { defineConfig } from "oxfmt";
import ultracite from "ultracite/oxfmt";

import { projectIgnorePatterns } from "./project-ignore-patterns.ts";

export default defineConfig({
  ...ultracite,
  ignorePatterns: [
    ...(ultracite.ignorePatterns ?? []),
    ...projectIgnorePatterns,
  ],
});
