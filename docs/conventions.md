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

## レビュー

削除・権限判定の変更では、承認された要件に照らし、検査不能な状態を接続コードから最終操作まで追う。読取り失敗・一部しか見えない状態・検査中の対象消失をどう扱うか、許可条件と拒否条件の両方をレビュー担当が確認する。

## テスト

`lefthook run test` で `tests/` の全 Bats を実行し、install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証する。lefthook の `test` は `bun run test` → `scripts/test.sh` を呼ぶ。入口で実際の `python3 -I` が `dotenv.parser` を import でき、`with-env` が Nix store 内へ解決されることを確認してから、依存関係の frozen install と Bats の実行を行う。不足時は devShell を準備して再実行する。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、Bats 非対象）。`.chezmoiignore` で home には非配備。

テスト入口は明示的に TAP 形式を使い、試行ごとに `tmp/test-run.*/` へ `tap.log`、環境確認・install のログ（`setup.log`）、選択された Python・with-env の実体パス（`environment`）、終了コード（`exit-code`）を保存する。環境確認や install が失敗した場合も記録し、Bats 未実行なら TAP ログは空になる。lefthook が出力をまとめて表示する場合も、このログで実行中の進捗を確認できる。進捗はログ全体の TAP 結果行から集計する。成功はスキップ指定のない `ok` 行、失敗は `not ok` 行、スキップは `# skip` 指定付きの `ok` 行として数える。入口は Bats が正常終了した後も、計画が1つで結果件数と一致し、結果番号が1から連続し、失敗結果や中断宣言がないことを確認する。不整合な TAP は終了コード1で拒否し、元のログを残す。Bats が正常終了する空 suite（`--allow-empty-suite` の `1..0`）は受け入れる。完了時は保存された終了コードも確認する。再実行の結果は初回の結果と分けて報告する。

topic branch の push・PR 公開前に、validated task worktree で `lefthook run test` を実行する。同じソース・依存関係・検証環境で全 Bats が成功済みなら、公開直前の繰り返しは不要。検証後にソース・依存関係・検証環境を変更した場合は再実行する。失敗が残る場合は修正してから公開する。認証・実モデル等の opt-in 検証は既定の skip を維持し、skip を実行済みの検証として扱わない。`pre-commit` は軽い lint のまま維持し、`pre-push` に全 Bats を自動実行する hook は追加しない。

更新時のcanonical検証には、repo内の手動入口 `python3 scripts/verify-canonical.py` を使える。入口自身が置かれたlinked task worktreeを対象にするため、検証する変更をcommitしてcleanにし、既存手順で両devShellとruntimeを準備してから起動する。`IMPECCABLE_HOOK_RUNTIME`、`IMPECCABLE_BIN`、`TEST_PLAYWRIGHT_PACKAGE` には準備済みの絶対パスを渡す。入口は `lefthook run test` を一度だけ呼び、開始前後のHEAD・全tracked内容・runtime、同じ実行のTAP・終了コード、Design Hook 13件とPlaywright runtime 2件の存在・成功・skipなしを照合する。

開始前は `git status` に加えて、全tracked内容とGit modeをHEADのtree/blobへ直接照合する。`assume-unchanged`／`skip-worktree` に隠れた未commitの変更もBats開始前に拒否し、flag自体は変更しない。実行後にHEADの内容・Git modeと異なるfileは `after.json` の `head_mismatches` に記録し、前後記録とTAPを保持する。

記録は `tmp/canonical-run.*/` の `before.json`／`after.json`、`command.log`、`runner-path`、`result.json` に残る。runnerが作成した `tmp/test-run.*/` と相互参照し、最新directory探索やconsoleの表示文言には依存しない。通常のテスト入口は維持し、受渡し情報をテスト内の別runnerへ引き継がない。Bats自体の結果と証拠照合の問題を区別し、不足・不一致・中断は非0終了する。全Batsコマンドの所要時間は実測し、環境準備の時間は含めない。自動再実行やNix build／APM再生成、PR／CIの照合は行わない。これは実行時点の証拠であり、後続のPR HEADや配備との一致確認は別に行う。

進捗は `python3 scripts/verify-canonical.py --status <canonical-run-directory>` でJSON表示する。この操作は保存記録を読むだけで、全Batsやruntime検査を開始しない。`state` は完了記録がなければ `incomplete`、`result.json` の終了コードが0なら `passed`、非0なら `failed`。`plan`／`pass`／`skip`／`fail` と `exit_code` を表示し、完了前の終了コードは `null`、完了後は記録の終了コードをコマンドの終了コードにも使う。`incomplete` は実行中か中断済みかを区別せず、TAPの全結果が出そろっても成功とはしない。破損した記録や異なる実行のrunner参照は非0終了で拒否する。

ローカルのユーザー devShell のツールと repo devShell を使い、Nix の取得・build 成果物とブラウザ環境を再利用する。環境を明示的に準備する場合は、worktree root から次を実行する。WSL2 では両方の `#default` を `#wsl` に置き換え、Managed Playwright Chrome を利用する。

```bash
nix develop ./private_dot_config/nix-devshell#default --command \
  nix develop .#default --command lefthook run test
```

ツール更新時の手動検証には [verify-ai-tools.py](../scripts/verify-ai-tools.py) を使う。Nix 評価と最初の shellHook より前に HOME と全 XDG directory を隔離し、source の `nativeBuildInputs` が選ぶ6 CLIの絶対パスと `command -v` を照合する。同じ版の別 output も拒否し、全 CLI の `--version` が成功した後だけ `--` 以降のコマンドを実行する。WSL2 では次のように `--shell wsl` を指定し、その他では `--shell default` を使う。

Managed Chromeの所有権記録は同じWindows資源を共有するため、`BROWSER_OWNERSHIP_DIR` は呼出元の共通記録先を保持する。未指定なら隔離前の `XDG_RUNTIME_DIR`、`TMPDIR`、`/tmp` の順で `browser-ownership` を解決し、最初のNix評価から後続コマンドまで同じ値を渡す。HOME/XDGを手動で分離する場合も、分離前にこの記録先を引き継ぐ。別の空の記録先を使うと、使用中のCDP portの予約を参照できなくなる。

```bash
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl -- lefthook run test
```

既存バイナリを使う方針の検証では `--no-codex-build` を指定する。最初の devShell 起動前に、選択された Codex output を既存の store または binary cache から確保し、取得できなければ後続の shellHook・コマンドを実行せず停止する。取得ログは `codex-cache.log`、検証中の GC を防ぐ output へのリンクは `codex` に残す。この指定は Codex に適用し、devShell や他の依存関係のビルドは従来どおり許可する。

評価・起動ログ、Nix の metadata 出力、終了コードは `tmp/ai-tools-*/` の `evaluation.log`／`startup.log`／`metadata.json`／`exit-code` に残す。不正 metadata の原文と診断も保持し、評価・metadata・version 検証に失敗した場合は後続コマンドを実行しない。後続テストの TAP は既存の `tmp/test-run.*/tap.log` で確認する。この helper は repo 内の手動入口で、HOME への配備や既存 runner／hook への自動配線はしない。HOME／XDG の分離は秘密分離や OS sandbox の保証ではなく、品質 floor の根拠機能、Playwright／Impeccable の runtime は既存の個別 gate で検証する。

GitHub Actions で全 Bats とそのための Nix cache 準備は実行しない。OSV の [PR scan](../.github/workflows/osv-scanner-pr.yml) と [full scan](../.github/workflows/osv-scanner-full.yml) は引き続き GitHub Actions で実行する。

品質 floor 判定は `tests/ai-quality-floor.bats` が実際の Nix package 出力を通して検証する。床上げ時は `modules/ai.nix` の値と、このテストの独立した期待値を更新する（[ADR-0047](adr/0047-test-quality-floors-through-package-outputs.md)）。

## 言語バージョンの更新

変更前に、更新対象の汎用ランタイムと言語テンプレートを漏れなく確認し、公式安定版・採用する Nix revision の実解決版・lint/LSP の互換性・環境間の版差・採否理由を照合する。公式リリースの安定性と Nix チャンネルへの収録状況は別々に判断し、既存の配布経路を維持するかは現在の依頼と照らして決める。

候補を固定してから言語本体と必要な周辺ツールを検証し、評価のみの対象環境と実行確認した環境を区別して報告する。取得元の構造は [architecture](architecture.md#per-repo-言語テンプレート)、独立展開の検証は `tests/helpers/template-with-env.py` を参照する。

## ツール・スキル更新の追跡とレビュー

設定変更でも、本体パッチの追加や package の取得経路を変える場合はツール更新として扱う。既存バイナリで可能な代替案を先に確認し、新しいソースビルドや独自パッチ保守が必要になる時点で、予想ビルド時間と継続保守の負担を提示してユーザーと方針を合わせる。レビューでは、この範囲拡大の判断と根拠も確認する。

更新開始時に既存の調査記録へ、更新単位、適用するADRの箇所、予定する変更（文書訂正を含む）を記録する。更新単位の分離は [ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md) に従う。PRを分割したときは、元の差分から外した変更を一件ずつ記録し、採用・却下・保留の扱い、理由、対応先のPR／commit、反映・検証の状態を追跡する。対応先が未定の必要変更は保留とする。

`code-review` のStandards／Spec両軸へ、現在の要件、適用するADRの箇所、調査記録を渡す。各軸は予定した変更と実際の差分を照合し、分割で外した変更の扱いも確認する。過去の調査記録は参考資料と現在の要件を区別する。

更新全体の完了報告前に、調査記録をマージ済みの成果物と照合する。今回必要な変更が保留・未反映・未検証なら、各PRの完了を個別に報告しても更新全体は未完了とする。今回の対象に採用しなかった候補は理由付きの却下として区別する。この追跡手順はツール・スキル更新に適用する。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
