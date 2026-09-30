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

`tests/` の bats で install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証（`bun run test` は `bun install --frozen-lockfile` 後に `bats tests/` を実行）。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、bats 非対象）。`.chezmoiignore` で home には非配備。

PR ごとに [Bats workflow](../.github/workflows/bats.yml) が Linux で通常の全 Bats を実行する。ユーザー devShell と repo devShell を重ね、実 Codex の sandbox 検証を含むツールを揃え、隔離 HOME で `bun run test` を実行する。認証・実モデル等の opt-in 検証は既定の skip を維持する。CI が失敗したら原因を直し、成功を確認してから merge する。GitHub の required check 設定による強制は行わない。

品質 floor 判定は `tests/ai-quality-floor.bats` が実際の Nix package 出力を通して検証する。床上げ時は `modules/ai.nix` の値と、このテストの独立した期待値を更新する（[ADR-0047](adr/0047-test-quality-floors-through-package-outputs.md)）。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
