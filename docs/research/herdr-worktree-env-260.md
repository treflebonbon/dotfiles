---
type: research
title: Herdr で新規 worktree に .env を複製する方法
description: Issue #260 の repo-local event plugin、元仕様との差分、Herdr 0.9.0 での検証記録
tags: [research, herdr, worktree, dotenv, plugins]
timestamp: 2026-09-09
---

# Herdr で新規 worktree に `.env` を複製する方法

Issue [#260](https://github.com/treflebonbon/dotfiles/issues/260) は Herdr で新規 worktree を作るときの `.env` コピーを扱う。2026-09-09 時点の最新安定版・導入版は [Herdr 0.9.0](https://github.com/herdrdev/herdr/releases/tag/v0.9.0)。公式設定と実イベントを調べ、利用者が承認した **repo-local の `herdr-plugin.toml` 一つにコピー処理を直接書く方式**を実装した。

## 2026-09-10 の仕様更新

全リポジトリへの適用と chezmoi による自動登録へ変更した。manifest 0.2.0 は plugin 配置元 repo との一致条件を除き、各イベントの primary checkout から `.env` をコピーする。不在は正常スキップ、symlink・既存コピー先・Git 非除外は引き続き拒否する。`run_after_setup-herdr.sh` が毎回登録を確認し、手動 disable を維持する。現行の利用手順は [ai-runtimes](../../runtime/ai-runtimes.md#新規-worktree-への-env-コピー) を参照する。

更新後は `tests/run_after_setup-herdr.bats` で登録の冪等性・無効化維持・source 移動・失敗伝播・実 chezmoi apply を検証する。`HERDR_COPY_ENV_REAL=1` で `tests/helpers/herdr-copy-env-live.py` による隔離 Herdr 0.9.0 の検証も実行できる。Linux ではサーバー停止中の登録、移動時の無効化維持、別々の2 repo のコピーと `.env` 不在の3つ目の repo の正常スキップが成功した。macOS native / TUI 操作は今回未検証。

以下は #260 実装当時の仕様と検証記録であり、repo 限定・コピー元不在時の失敗・手動登録に関する記述は今回の更新で置き換わった。

## 採用した設定

[`.herdr/herdr-plugin.toml`](../../.herdr/herdr-plugin.toml) の `[[events]]` で `worktree.created` を購読し、`command` に Bash の処理を定義する。Herdr 公式の plugin 機構は使うが、外部 plugin の install、npm 依存、別ファイルの実行 script は追加しない。実行依存は既存ユーザー devShell が供給する Bash・jq・Git・cp。Python は TOML を読み取るテストにだけ使い、`tomllib` に必要な3.11以上を repo 用 `flake.nix` の `basePackages` から供給する。[公式 manifest 定義](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/app/api/plugins/manifest.rs)

コピー元・先は `HERDR_PLUGIN_EVENT_JSON` から取得する。

| 用途                        | イベントのフィールド                |
| --------------------------- | ----------------------------------- |
| コピー元の primary checkout | `data.workspace.worktree.repo_root` |
| 作成された linked worktree  | `data.worktree.path`                |

Herdr はこの JSON と `HERDR_PLUGIN_ROOT` を event command に渡す。登録した manifest の親ディレクトリとコピー元が一致する repo だけを対象にする。[イベント定義](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/api/schema/events.rs) [イベント環境の生成](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/app/api/plugins/runtime.rs#L32-L61)

処理は両パスが絶対パスであること、作成先が同じ Git repository の linked worktree であること、作成先の `.env` が ignore されることを確認する。ルート `.env` 一件を `umask 077` のもとで通常コピーし、最後に作成先へ `cd` する。`.env.local` などの探索や dotenv の環境注入は行わない。コピー元不在、symlink、既存のコピー先は失敗し、コピー・移動の非0終了を後続処理で隠さない。作成後の同期や既存 worktree の backfill はしない。

`cd` は plugin の subprocess にだけ作用する。pane の cwd は Herdr 自身が新 worktree に設定する。with-env は配置後の現在の worktree 直下 `.env` の読込みだけを担当し、この処理とは別の責務とする。

## 登録と利用

`.herdr` は [`.chezmoiignore`](../../.chezmoiignore) でホーム配備から除外する。受入・merge 後、primary checkout の source から一度登録する。

```bash
herdr plugin link "$(chezmoi source-path)/.herdr"
```

task worktree 側の manifest を登録すると、対象 repo の判定もその checkout に限定されるため、通常利用には primary checkout のものを登録する。対象 repo の primary workspace を Herdr で開き、そこから新規 worktree を作る。Herdr 0.9.0 は linked worktree を source とする新規作成を `linked_worktree_source` エラーで拒否する。

agent を起動する前にログを確認する。

```bash
herdr plugin log list --plugin dotfiles.copy-env --limit 10
```

対象 worktree の作成時刻に対応する `status = succeeded` / `exit_code = 0` と、`copy-env: copied .env to <作成先>` の出力を確認する。他 repo のイベントは何もせず成功するため、状態だけではコピー完了と判断しない。`.env` の内容はログへ出力しない。

コピー失敗でも worktree 自体の作成は成功する。失敗した worktree で agent を起動せず、原因を修正して新しい worktree を作る。自動再試行・再コピーはしない。コピーは通常の `cp` であり、書込み完了前から作成先が存在し得るため、存在確認だけで完了と判断しない。

## 元の Issue から承認された変更

元の指定は `.herdr/config.toml` の `[setup].script` と `HERDR_SOURCE_TREE_PATH` / `HERDR_WORKTREE_PATH` だった。Herdr 0.9.0 の設定・実装にこの機構はなく、隔離 repo で実際に新規作成しても実行されなかった。[日本語設定ドキュメントの source](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/docs/versions/0.9.0/website/src/content/docs/ja/configuration.mdx) 調査時点の master `b9ce96869e89937278d673d70ae4c135dd318469` の [next 設定ドキュメント](https://github.com/herdrdev/herdr/blob/b9ce96869e89937278d673d70ae4c135dd318469/docs/next/website/src/content/docs/configuration.mdx)にも記載はない。開発版の実行は検証していない。

また、event command は別 thread で非同期実行されるため、plugin 単体では agent 起動前のコピー完了を保証できない。失敗は plugin log に記録されるが、worktree create の成功応答には連動しない。[event hook の起動実装](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/app/api/plugins/runtime.rs#L218-L266) [worktree 作成の完了処理](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/app/api/worktrees/deferred.rs)

これらを説明したうえで、利用者は外部 plugin の信頼性を理由に自前化を求め、`worktree.created` の処理を TOML 一つに直接書く案へ「これでいい」と承認した。実装の契約を次に変更する。

| 元の条件 | 承認後の扱い |
| --- | --- |
| `.herdr/config.toml` の setup | repo-local `.herdr/herdr-plugin.toml` の event command |
| `HERDR_SOURCE_TREE_PATH` / `HERDR_WORKTREE_PATH` | 公式 event JSON の絶対パス。コピー元は primary checkout |
| agent 起動前に setup が必ず完了 | 非同期コピー後、対象 worktree の成功ログを確認してから手動で起動 |
| ホーム全体へ配備しない | 維持。受入後の primary source を `plugin link` で登録 |
| `.env` 一件の独立コピー、失敗通知、秘密値非出力 | 維持。with-env や agent の権限・注入範囲は変更しない |

## 参考にした外部 plugin

[`tdi/herdr-worktree-setup`](https://github.com/tdi/herdr-worktree-setup/tree/4527a11bd5444dbce34c3d4f459b49d704cc12a7) の manifest 0.2.0 は `worktree.created` を購読し、`[[project]]` の `steps` を新 worktree で実行する。primary checkout は Git の worktree 一覧から解決し、step へ `HERDR_MAIN_REPO` / `HERDR_WORKTREE` を渡す。Node と `smol-toml` に依存する。隔離した Herdr で `.env` コピーと非同期性を確認したが、最終実装の依存には含めない。[manifest](https://github.com/tdi/herdr-worktree-setup/blob/4527a11bd5444dbce34c3d4f459b49d704cc12a7/herdr-plugin.toml) [runner](https://github.com/tdi/herdr-worktree-setup/blob/4527a11bd5444dbce34c3d4f459b49d704cc12a7/src/runner.js)

[`shizlie/herdr-setup-bootstrap`](https://github.com/shizlie/herdr-setup-bootstrap/tree/5e2a5bc1e2f3b153a0844908e0279a6758408093) の manifest 0.1.2 は `worktree_init.toml` を読み、作成・focus で backfill する。`copy = "./.env"` ならルートだけを対象にできるが、`.env` だけでは任意の深さも探索する。コピー元不在でも warning 後に完了 marker を残すため、今回の失敗通知要件とは異なる。こちらは source 調査だけで実行していない。[コピーと marker の実装](https://github.com/shizlie/herdr-setup-bootstrap/blob/5e2a5bc1e2f3b153a0844908e0279a6758408093/bootstrap.sh)

## 検証記録

2026-09-09、x86_64-linux、Herdr 0.9.0。実在する秘密値は使わず、空白を含むパスのダミー repo と `.env` / `.env.local` を作成した。Herdr の HOME・XDG・設定・named session を隔離し、今回の管理対象 TOML をそのままダミー repo に登録して実 CLI の `worktree create` を呼び出した。検証用 server は最後に停止し、process 終了を確認した。

| 条件 | 方法・結果 |
| --- | --- |
| AC1 作成イベントでの実行・repo 限定 | 実 Herdr の `worktree.created` で `dotfiles.copy-env` が成功。Bats で別 repo はコピーしないことと chezmoi の Linux/macOS ホーム配備からの除外を確認 |
| AC2 絶対パス・空白を含むパス | 実イベントの primary / target パスでコピー成功。Bats で相対パス・欠落・不正 JSON を拒否 |
| AC3 通常コピー・独立性・cwd | 内容一致、非 symlink、コピー後の target 編集で source 不変。Bats で処理終了時 cwd、実 Herdr で pane cwd を確認 |
| AC4 失敗通知 | Bats で変数欠落、source 不在、copy exit 74、cd exit 75 を確認。実 Herdr でも source 不在は plugin `failed` / exit 1、別名への fallback なし |
| AC5 Git 除外・秘密値非出力 | 実 Herdr で `git check-ignore` 成功、`.env.local` 非コピー、dummy 値が plugin log にないことを確認。Bats で source 0644 に対し target 0600、既存 target・symlink・別 repo・Git 非除外を拒否 |
| AC6 非同期コピーの利用手順 | 検証用 manifest にだけ2秒待機を挿入し、create 応答時は `.env` 不在、後から成功することを実測。待機を除いて管理対象と同じ内容に復元。with-env・agent 権限・dotenv 注入設定の変更なし |
| AC7 実設定を使うテスト | `tests/herdr-copy-env.bats` の15件と実 Herdr smoke が成功。manifest の実 command を TOML parser で読み取り、終了状態とファイル・cwd を観測 |
| AC8 作成時限定・文書 | 既存 worktree の open で再コピーしないことを実 Herdr で確認。[利用案内](../../runtime/ai-runtimes.md#新規-worktree-への-env-コピー)に登録、成功確認、責務、同期しない方針を記載 |

管理対象の検証結果は `/tmp/herdr-260-local-w8zr_yq8/result.json`。同じディレクトリに `first-worktree-plugin.json`、`missing-source-plugin.json`、`delayed-copy-plugin.json`、各 create の応答と `stop.log` を保存した。再現 script は task worktree の `tmp/issue-260/local-probe.py`。元の無効な setup 設定の検証は `/tmp/herdr-260-lljk55sx/result.json`、参考 `tdi` plugin の検証は `/tmp/herdr-260-plugin-hkq5dm9q/result.json` に分けて残す。これらはローカルの一時証跡であり、恒久的な成果物ではない。

macOS の native 実行、TUI の実操作、実 agent の起動待機は未検証。TUI も同じ `Method::WorktreeCreate` を送るため同じイベントになるという判断は [TUI source](https://github.com/herdrdev/herdr/blob/b99002ac99b09e00b4ca692436cb15a6b0d676f1/src/client/shell/worktrees.rs#L263-L305) からの推論に限る。Windows はこの plugin の対象外。live source の更新、通常 Herdr への登録、task worktree からの `chezmoi apply` は行っていない。

### 必須チェックとレビュー

追加 Bats は15/15成功。`bunx tsc --noEmit`、実 command を抽出した ShellCheck / shfmt、`git diff --check` と commit hook の oxfmt / gitleaks / cog が成功した。`code-review` は fixed point `f0257af752718826b81f15736862b9ead9a452a0` から実装 commit `5486199` までを独立した2軸で確認し、Standards / Spec ともに指摘0件だった。

`env -u FORCE_COLOR bun run test` は全544件を実行し、535件成功・9件失敗・skip 0、exit 1。失敗は既存の `tests/design-hook.bats` の9件で、即時・Stop finding が出力されないもの。変更前の `f0257af` から同テスト・Claude 設定・Codex hook 設定を隔離ディレクトリへ取り出し、現在の3ファイルと内容が同一であることを確認したうえで、同じ9件の失敗を再現した。この実装による回帰ではないが、全体テストの成功とは扱わない。Herdr パッケージの全対応 system / shell 評価を含む残りは成功した。ログは task worktree の `tmp/issue-260/full-suite.log` と `tmp/issue-260/baseline-design-hook.log` に保存し、既存失敗を隠すための skip やテスト変更はしていない。

### PR #261 のレビュー対応

repo 用 `flake.nix` の共通 `basePackages` に `python3` を追加した。既存の lock のまま、3 system × `default` / `wsl` の全6出力が Python 3.13.13 を供給することを評価した。x86_64-linux では `nix develop .#wsl --ignore-environment --command python3 ...` による `tomllib` の import と TOML 解析が成功し、ユーザー環境からの Python 継承に依存しないことを確認した。同 devShell の Python 3.13.13 で Herdr の Bats 15件も成功した。`nix flake check --no-build --all-systems` と `nixfmt --check flake.nix` が成功。ARM の native 実行は未確認で、全体テストの再実行はしていない。

証跡は task worktree の `tmp/issue-260/review-python-eval.json`、`review-python-isolated.log`、`review-python-bats.log`、`review-flake-check.log`。既存 Design Hook の9件の失敗は、前回の全体検証記録を維持する。
