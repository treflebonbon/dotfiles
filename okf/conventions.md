---
type: concept
title: Conventions
description: コミット・lint・認証の規約
tags: [conventions, git, lint, lefthook]
---

# Conventions

- **コミット**: Conventional Commits 形式（`cog verify` で検証、`commit-msg` hook）
- **Linting / format**: lefthook `pre-commit` hook で自動実行（`lefthook.yml`）。pinact / shfmt / oxfmt / oxlint / ghalint / actionlint / shellcheck / gitleaks / typecheck の汎用品質ゲート
- **認証**: HTTPS + `gh auth git-credential`。SSH は不使用

## テスト

`tests/` の bats で install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証（`bun run test` = `bats tests/`）。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、bats 非対象）。`.chezmoiignore` で home には非配備。

関連: [architecture](architecture.md)
