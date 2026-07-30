# Tech Stack

- Configuration manager: chezmoi; `private_` / `dot_` source naming and `.tmpl` scripts produce deployed home files.
- Configuration/build language: Nix flakes. Root development flake tracks `nixos-unstable`; the user shell and per-language templates track `nixpkgs-26.05-darwin` and support x86_64/aarch64 on Linux and Darwin.
- Shell automation: bash is the Linux/container login shell; PowerShell appears only at Windows/WSL boundaries. Shell code is formatted with shfmt and checked with ShellCheck.
- Tests: Bats under `tests/`; `bun run test` installs the frozen Bun lockfile and runs the suite. Browser automation uses the Nix-provided Playwright driver.
- JavaScript/TypeScript tooling: Bun, Node.js 24 in the repository shell, Oxfmt, Oxlint, and TypeScript. `tsconfig.json` intentionally covers root TypeScript files only.
- Quality/commit tooling: Lefthook, Cocogitto, gitleaks, pinact, ghalint, and actionlint.
- External agent skills/plugins are pinned through `apm.yml` / `apm.lock.yaml`; private user-scoped skills use `local-skills/` as source and onchange deployment scripts to materialize runtime copies.
