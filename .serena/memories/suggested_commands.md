# Suggested Commands

## Source and deployment

- Enter the source of truth: `cd "$(chezmoi source-path)"`.
- Preview/apply managed-home changes: `chezmoi diff`; `chezmoi apply`.
- Import an intentional direct `$HOME` edit: `chezmoi re-add <deployed-file>`.

## Development and checks

- Enter the repository devShell: `nix develop` (normally loaded by direnv in the source directory).
- Run the full Bats suite: `bun run test`.
- Run focused tests: `bats tests/<area>.bats`; combine related files in one invocation when useful.
- Validate repository flake outputs without building: `nix flake check --all-systems --no-build`.
- Validate the deployed user shell separately: `nix flake check ./private_dot_config/nix-devshell --all-systems --no-build`.
- Run configured hooks: `lefthook run pre-commit --all-files`.
- Check a commit message before committing: `cog verify '<type>(<scope>): <subject>'` or let the commit-msg hook validate the file.
- Check Serena memory references after memory changes: `serena memories check`.

## Templates and publication

- Instantiate a language shell: `nix flake init -t 'github:treflebonbon/dotfiles#<go|rust|elixir|perl|gleam|bun>'`.
- Publish the current topic branch with `git-push-topic`; raw `git push` and force-push are not part of this repository workflow.
