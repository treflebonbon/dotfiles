# Conventions

- Preserve chezmoi source ownership: never patch the deployed `$HOME` copy when the source repository is available.
- Choose package placement globally: repository-only editing/test tools belong in root `flake.nix`; cross-project runtimes/tools belong in `private_dot_config/nix-devshell`; project-language toolchains belong in per-repo flakes/templates.
- Keep x86_64-linux, aarch64-linux, x86_64-darwin, and aarch64-darwin evaluable in the user shell until the documented Intel Darwin sunset decision changes that contract.
- Commits and PR titles use Conventional Commits without agent prefixes. Authentication is HTTPS through `gh auth git-credential`; SSH and force-push are prohibited.
- Feature work starts in one isolated worktree and stays there through design, implementation, review, and optional PR creation. Do not create a new worktree at each workflow stage.
- Required implementation discipline is Builder-Evaluator: use behavior-first tests where the seam is clear, then review Standards and Contract separately. Normal completion reports stop before `to-pr` unless the user invoked it or explicitly authorized autonomous publication.
- `AGENTS.md` is shared Codex/OpenCode/Zed/Cursor guidance; `CLAUDE.md` is maintained independently for Claude Code. Do not synchronize them mechanically.
- `CONTEXT.md` and `docs/adr/` describe this repository's workflow domain. `runtime/` is the deployed home-wide knowledge bundle; keep repo-only facts out of it.
- Prefer dense, durable documentation. Do not add compatibility shims, speculative abstractions, or comments for self-evident logic.
