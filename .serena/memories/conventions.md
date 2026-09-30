# Conventions

- Preserve chezmoi source ownership: never patch the deployed `$HOME` copy when the source repository is available.
- Choose package placement globally: repository-only editing/test tools belong in root `flake.nix`; cross-project runtimes/tools belong in `private_dot_config/nix-devshell`; project-language toolchains belong in per-repo flakes/templates.
- Keep x86_64-linux, aarch64-linux, and aarch64-darwin evaluable in the user shell. Intel Darwin support ended in ADR-0034.
- Commits and PR titles use Conventional Commits without agent prefixes. Authentication is HTTPS through `gh auth git-credential`; SSH and force-push are prohibited.
- Feature work starts in one isolated worktree and stays there through design, implementation, review, and optional PR creation. Do not create a new worktree at each workflow stage.
- 個別 ticket は `implement`、仕様全体は `implement-spec` で実装する。合意済みの seam で動作を検証し、Standards と Spec を別々にレビューする。PR 本文は `pr`、振り返りは `retro` を使い、公開はユーザーの依頼または `implement-spec` の承認範囲で行う。
- `AGENTS.md` is shared Codex/OpenCode/Zed/Cursor guidance; `CLAUDE.md` is maintained independently for Claude Code. Do not synchronize them mechanically.
- `GLOSSARY.md` と `docs/adr/` はこの repo の workflow domain を記録する。`runtime/` は home 共通の知識バンドルなので repo 固有の内容を分ける。
- Prefer dense, durable documentation. Do not add compatibility shims, speculative abstractions, or comments for self-evident logic.
