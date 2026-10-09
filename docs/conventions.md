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

`lefthook run test` で `tests/` の全 Bats を実行し、install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証する。lefthook の `test` は `bun run test` → `scripts/test.sh` を呼ぶ。入口で実際の `python3 -I` が `dotenv.parser` を import でき、`with-env` が Nix store 内へ解決されることを確認してから、依存関係の frozen install と Bats の実行を行う。不足時は devShell を準備して再実行する。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、Bats 非対象）。`.chezmoiignore` で home には非配備。

テスト入口は明示的に TAP 形式を使い、試行ごとに `tmp/test-run.*/` へ `tap.log`、環境確認・install のログ（`setup.log`）、選択された Python・with-env の実体パス（`environment`）、終了コード（`exit-code`）を保存する。環境確認や install が失敗した場合も記録し、Bats 未実行なら TAP ログは空になる。lefthook が出力をまとめて表示する場合も、このログで実行中の進捗を確認できる。進捗はログ全体の TAP 結果行から集計する。成功はスキップ指定のない `ok` 行、失敗は `not ok` 行、スキップは `# skip` 指定付きの `ok` 行として数える。入口は Bats が正常終了した後も、計画が1つで結果件数と一致し、結果番号が1から連続し、失敗結果や中断宣言がないことを確認する。不整合な TAP は終了コード1で拒否し、元のログを残す。Bats が正常終了する空 suite（`--allow-empty-suite` の `1..0`）は受け入れる。完了時は保存された終了コードも確認する。再実行の結果は初回の結果と分けて報告する。

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

## ツール・スキル更新の追跡とレビュー

更新開始時に既存の調査記録へ、更新単位、適用するADRの箇所、予定する変更（文書訂正を含む）を記録する。更新単位の分離は [ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md) に従う。PRを分割したときは、元の差分から外した変更を一件ずつ記録し、採用・却下・保留の扱い、理由、対応先のPR／commit、反映・検証の状態を追跡する。対応先が未定の必要変更は保留とする。

`code-review` のStandards／Spec両軸へ、現在の要件、適用するADRの箇所、調査記録を渡す。各軸は予定した変更と実際の差分を照合し、分割で外した変更の扱いも確認する。過去の調査記録は参考資料と現在の要件を区別する。

更新全体の完了報告前に、調査記録をマージ済みの成果物と照合する。今回必要な変更が保留・未反映・未検証なら、各PRの完了を個別に報告しても更新全体は未完了とする。今回の対象に採用しなかった候補は理由付きの却下として区別する。この追跡手順はツール・スキル更新に適用する。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
