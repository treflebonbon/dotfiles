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

`bun run test` で `tests/` の bats を実行し、install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証する。コマンド定義は `package.json` の `scripts.test` を参照する。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、bats 非対象）。`.chezmoiignore` で home には非配備。

テストは試行ごとにログを保存し、進捗はログ全体の TAP 結果行から集計する。成功はスキップ指定のない `ok` 行、失敗は `not ok` 行、スキップは `# skip` 指定付きの `ok` 行として数える。完了時は終了コードと、計画数（`1..N`）に対する結果行数も確認する。再実行の結果は初回の結果と分けて報告する。

PR ごとに [Bats workflow](../.github/workflows/bats.yml) が Linux で通常の全 Bats を実行する。ユーザー devShell と repo devShell を重ね、実 Codex の sandbox 検証を含むツールを揃え、隔離 HOME で `bun run test` を実行する。認証・実モデル等の opt-in 検証は既定の skip を維持する。CI が失敗したら原因を直し、成功を確認してから merge する。GitHub の required check 設定による強制は行わない。

Nix store は GitHub Actions cache で再利用する。main への push では devShell の準備だけを行い、別の PR でも復元できるキャッシュを保存する。Nix 定義・lock・ローカル package source の変更で key を更新し、以前のキャッシュも prefix で復元して不足分を build する。保存前の runner 内 GC では、二つの devShell の profile が実行用 closure を保護する。初回やキャッシュの失効時は通常の build が必要になる。ローカル lefthook は引き続き pre-commit の lint を担当する。

品質 floor 判定は `tests/ai-quality-floor.bats` が実際の Nix package 出力を通して検証する。床上げ時は `modules/ai.nix` の値と、このテストの独立した期待値を更新する（[ADR-0047](adr/0047-test-quality-floors-through-package-outputs.md)）。

## 言語バージョンの更新

変更前に、更新対象の汎用ランタイムと言語テンプレートを漏れなく確認し、公式安定版・採用する Nix revision の実解決版・lint/LSP の互換性・環境間の版差・採否理由を照合する。公式リリースの安定性と Nix チャンネルへの収録状況は別々に判断し、既存の配布経路を維持するかは現在の依頼と照らして決める。

候補を固定してから言語本体と必要な周辺ツールを検証し、評価のみの対象環境と実行確認した環境を区別して報告する。取得元の構造は [architecture](architecture.md#per-repo-言語テンプレート)、独立展開の検証は `tests/helpers/template-with-env.py` を参照する。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
