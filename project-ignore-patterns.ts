export const projectIgnorePatterns = [
  "**/*.tmpl",
  "**/*.jsonl",
  "**/node_modules/**",
  "**/dist/**",
  "**/.agents/skills/**",
  "**/.claude/skills/**",
  "**/.claude/worktrees/**",
  "**/.worktrees/**",
  "CHANGELOG.md",
  // Frozen A/B inputs and outputs must retain their recorded hashes.
  "docs/evaluations/mvp-mediator-ab-20260924/original/**",
  "docs/evaluations/mvp-mediator-ab-20260924/*.json",
];
