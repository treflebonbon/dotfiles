# Project Core

- chezmoi source repository for a shared DevPod / VS Code Dev Containers environment; login shell is bash and the visual theme is Dracula.
- Edit managed files only in the source returned by `chezmoi source-path`; apply source changes to `$HOME` with `chezmoi apply`. If a deployed file was edited directly, restore the source of truth with `chezmoi re-add <file>`.
- Root `flake.nix` is the repository-development shell and template publisher. `private_dot_config/nix-devshell/flake.nix` is the deployed, user-wide runtime/tool shell. Never add a package without first choosing between those roles.
- Repository structure and local decisions live in `docs/architecture.md`, `docs/conventions.md`, `CONTEXT.md`, and `docs/adr/`. Home-wide runtime/skill knowledge starts at `runtime/index.md`; do not mix it with repo-local domain docs.
- Toolchain and pinned-platform facts: `mem:tech_stack`.
- Commands for editing, testing, deployment, and publication: `mem:suggested_commands`.
- Source, workflow, Git, and style invariants: `mem:conventions`.
- Proportional completion checks: `mem:task_completion`.
- Memory graph style and maintenance threshold: `mem:memory_maintenance`.
