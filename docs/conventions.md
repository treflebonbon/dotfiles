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

`lefthook run test` で `tests/` の全 Bats を実行し、install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証する。lefthook の `test` は既存の `bun run test` を呼び、依存関係の frozen install と Bats の実行を行う。コマンド定義は `lefthook.yml` と `package.json` の `scripts.test` を参照する。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、Bats 非対象）。`.chezmoiignore` で home には非配備。

テストは試行ごとにログを保存し、進捗はログ全体の TAP 結果行から集計する。成功はスキップ指定のない `ok` 行、失敗は `not ok` 行、スキップは `# skip` 指定付きの `ok` 行として数える。完了時は終了コードと、計画数（`1..N`）に対する結果行数も確認する。再実行の結果は初回の結果と分けて報告する。

topic branch の push・PR 公開前に、validated task worktree で `lefthook run test` を実行する。同じソース・依存関係・検証環境で全 Bats が成功済みなら、公開直前の繰り返しは不要。検証後にソース・依存関係・検証環境を変更した場合は再実行する。失敗が残る場合は修正してから公開する。認証・実モデル等の opt-in 検証は既定の skip を維持し、skip を実行済みの検証として扱わない。`pre-commit` は軽い lint のまま維持し、`pre-push` に全 Bats を自動実行する hook は追加しない。

ローカルのユーザー devShell のツールと repo devShell を使い、Nix の取得・build 成果物とブラウザ環境を再利用する。環境を明示的に準備する場合は、worktree root から次を実行する。WSL2 では両方の `#default` を `#wsl` に置き換え、Managed Playwright Chrome を利用する。

```bash
nix develop ./private_dot_config/nix-devshell#default --command \
  nix develop .#default --command lefthook run test
```

GitHub Actions で全 Bats とそのための Nix cache 準備は実行しない。OSV の [PR scan](../.github/workflows/osv-scanner-pr.yml) と [full scan](../.github/workflows/osv-scanner-full.yml) は引き続き GitHub Actions で実行する。

品質 floor 判定は `tests/ai-quality-floor.bats` が実際の Nix package 出力を通して検証する。床上げ時は `modules/ai.nix` の値と、このテストの独立した期待値を更新する（[ADR-0047](adr/0047-test-quality-floors-through-package-outputs.md)）。

## 言語バージョンの更新

変更前に、更新対象の汎用ランタイムと言語テンプレートを漏れなく確認し、公式安定版・採用する Nix revision の実解決版・lint/LSP の互換性・環境間の版差・採否理由を照合する。公式リリースの安定性と Nix チャンネルへの収録状況は別々に判断し、既存の配布経路を維持するかは現在の依頼と照らして決める。

候補を固定してから言語本体と必要な周辺ツールを検証し、評価のみの対象環境と実行確認した環境を区別して報告する。取得元の構造は [architecture](architecture.md#per-repo-言語テンプレート)、独立展開の検証は `tests/helpers/template-with-env.py` を参照する。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
