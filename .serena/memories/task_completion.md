# Task Completion

- Run the narrowest Bats files covering the changed behavior during development, then `bun run test` before handing off code changes.
- Run checks matching changed file types: shfmt/ShellCheck for `.sh`, Oxfmt/Oxlint for JS/TS/JSON/Markdown/YAML/TOML, nixfmt and flake evaluation for Nix, and action-specific workflow linters for GitHub Actions.
- Use `lefthook run pre-commit --all-files` as the integrated repository gate when the change spans multiple tool classes; inspect any formatter rewrites before commit.
- For user-shell changes, run `nix flake check ./private_dot_config/nix-devshell --all-systems --no-build`; do not claim Darwin build success from cross-system evaluation alone.
- For root flake/template changes, run `nix flake check --all-systems --no-build` and build the native output affected by the change when practical.
- For Serena memory changes, run `serena memories check` and ensure `.serena/cache/` and `.serena/project.local.yml` remain untracked.
- Before commit: `git diff --check`, inspect `git status --short`, verify unrelated user changes are absent, and use a Conventional Commit message. Never bypass hooks with `--no-verify`.
- Browser-observable acceptance criteria require browser evidence in the final PR workflow; non-UI changes need command output or another reproducible verification record.
