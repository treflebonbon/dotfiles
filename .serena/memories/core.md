# Project Core

- chezmoi source repository for a shared DevPod / VS Code Dev Containers environment; login shell is bash and the visual theme is Dracula.
- Edit managed files in the validated task worktree; apply accepted changes from the live source identified by `chezmoi source-path`. If a deployed file was edited directly, restore the source of truth with `chezmoi re-add <file>`.
- Root `flake.nix` is the repository-development shell and template publisher. `private_dot_config/nix-devshell/flake.nix` is the deployed, user-wide runtime/tool shell. Never add a package without first choosing between those roles.
- repo の構造・規約・用語・判断は `docs/architecture.md`、`docs/conventions.md`、`GLOSSARY.md`、`docs/adr/` に置く。home 共通の runtime／skill 知識は `runtime/index.md` から読み、repo 固有の domain 文書と分ける。
- Toolchain and pinned-platform facts: `mem:tech_stack`.
- Commands for editing, testing, deployment, and publication: `mem:suggested_commands`.
- Source, workflow, Git, and style invariants: `mem:conventions`.
- Proportional completion checks: `mem:task_completion`.
- Memory graph style and maintenance threshold: `mem:memory_maintenance`.
