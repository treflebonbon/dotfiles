---
type: research
title: Herdr の dotenv コピーと raw Codex の隔離起動
description: Issue 273 の実 Herdr イベント・ターミナルから共通入口までの Linux／WSL2 検証
tags: [herdr, codex, dotenv, isolation, worktree]
timestamp: 2026-09-10
---

# Herdr の dotenv コピーと raw Codex の隔離起動 — #273

[#273](https://github.com/treflebonbon/dotfiles/issues/273) は、Herdr のホスト側 `.env` コピーを維持し、作成した worktree のターミナルから [#271 の共通入口](raw-codex-isolation-271.md)を使う統合単位。コピー機構・共通 launcher・permission の変更は不要だった。実 Herdr を使う再現可能な検証と、[コピー成功確認から起動・再起動までの利用案内](../../runtime/ai-runtimes.md#新規-worktree-への-env-コピー)を追加した。

## 実行経路

[`scripts/herdr-codex-isolation.py`](../../scripts/herdr-codex-isolation.py) は、ダミー repo、専用 HOME／XDG、named session に実 Herdr 0.9.0 server を起動する。管理対象 manifest をダミー primary repo へ登録し、`herdr worktree create` が linked worktree と pane を作る。実イベントの log ID、コピー成功の終了コードと作成先を含む出力、コピー結果・mode 0600 を別々に確認する。

確認した pane ID に対する `herdr pane run` で、`HERDR_ENV=1` とターミナルの cwd を検査し、実 `codex-worktree sandbox -- bash task.sh` を実行する。Nix、Codex、Git、bubblewrap は実バイナリ。GitHub／MCP の本番接続や hosted model は使わず、実プロジェクト秘密・認証値も使わない。これはモデルによる自律ターンや Herdr TUI のクリック操作を確認する試験ではない。Codex の `sandbox` サブコマンドは [公式 CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) にある公開検証入口を使う。

生の `git worktree add` で同型 fixture を作る既存 [`tests/herdr-copy-env.bats`](../../tests/herdr-copy-env.bats) と、実 Herdr イベント・ターミナルを使う [`tests/herdr-codex-isolation.bats`](../../tests/herdr-codex-isolation.bats) を区別する。統合テストは `HERDR_ISOLATION_REAL=1` で明示選択し、前提が欠けた場合の失敗を skip に変えない。通常の Bats 実行での opt-in skip は未実行を意味する。

## 検証対象と観測点

| #273 の AC                | 観測内容                                                                                                                                                                                                                                                       |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1: コピー契約の維持       | 既存15 Bats が root `.env` のみ、非上書き、所属、symlink 拒否、owner のみ、終了コード伝播を確認。実 Herdr でも独立コピー・別名非コピー・0600 を確認                                                                                                            |
| 2: コピー後の非開示       | Nix 評価で host `.env` の不在を検査。shellHook と Codex 子コマンドからダミー dotenv・継承変数・コピー元・別 worktree を取得できないことを確認                                                                                                                  |
| 3: 順序・競合・差替え     | コピー後に起動し、起動後に `.env` 差替え・通常名の秘密追加・コピー元への symlink 追加を行う。別試行では実 event command の `cp` 直前をテスト専用 gate で保留し、隔離内の開始を確認してからコピーを解放。公開コードの並行差替えは snapshot に現れず、返却を拒否 |
| 4: 通常の開発と所有権     | Herdr が作った pane の cwd から Python ファイルを作成、bytecode build、計算テスト、stage／commit。終了後に同じ host worktree のファイルと HEAD を確認                                                                                                          |
| 5: ホスト制御経路の非公開 | Herdr の環境変数・CLI が隔離内にないこと、実検証用 server の UNIX socket に接続できないことを shellHook／子コマンドで検査。ホスト側では同じ server の CLI が成功                                                                                               |
| 6: 拒否と保証範囲         | 実 Herdr ターミナルで未信頼 worktree と primary checkout の起動拒否を確認。隔離前提・未登録・入力差替え等は共通入口の既存 Bats を併せて検証。通常の直接起動・既存セッションは保証対象外と案内                                                                  |
| 7: Linux／WSL2 と運用     | WSL2 と KVM 上の別 Linux kernel で同じ script を実行。コピー結果の確認、共通入口、再登録・再起動・返却失敗の案内を更新                                                                                                                                         |
| 8: 再現手順・ダミー証跡   | script、Bats、VM の `--herdr` 選択肢を保存。`report.json` に kernel、tool version、manifest SHA-256、検証結果を記録                                                                                                                                            |

shellHook は確認成功後に `hook-calls` へ記録し、初回と再起動で1行ずつ増えることを確認する。子コマンドは `BOUNDARY_OK`、編集・検証・コミット後は `ISOLATED_TASK_OK` を出力する。`.env` の内容はログへ出さない。Codex が deny 対象に空の placeholder を作る場合は、内容がないことを検査する。

コピー失敗では実 Herdr の worktree 作成自体は成功し、plugin は `failed`／非0終了になる。コピー成功メッセージがないことを確認し、その worktree から Codex は起動しない。コピー保留用 gate は試験用 manifest にだけ挿入し、通常試行と失敗試行には管理対象の内容を使用する。

## 再現コマンドと証跡

repo devShell と、ユーザー環境の Nix store 由来の Herdr／Codex／bubblewrap 等を使用する。公開 CA bundle を `CODEX_ISOLATION_CA_BUNDLE` で渡す。専用 server のみを終了し、利用中の Herdr session は操作しない。

```bash
nix develop .#wsl --command env HERDR_ISOLATION_REAL=1 bats tests/herdr-codex-isolation.bats
nix develop .#wsl --command python3 scripts/herdr-codex-isolation.py --output /tmp/herdr-273-wsl
nix develop .#wsl --command python3 scripts/secret-isolation-linux-vm.py --herdr --output /tmp/herdr-273-linux
```

`--output` は未作成のパスを指定する。script の単体実行は復旧用の専用 store も保持する。Bats はテスト終了時に自身の一時 fixture を回収する。VM は host HOME・host Nix store を共有せず、列挙した公開 fixture と tool closure を image に含める。`--herdr` は外部認証を必要とする `--real-services` とは別の検証単位。

Session Scratchpad は提示されていないため、ローカル一時証跡には `/tmp` を fallback として使用した。Herdr の制御ディレクトリは UNIX socket のパス長制限に収まる専用 `/tmp/h273-*` に置き、検証用 server の停止後に回収する。通常の user config、live source の Herdr plugin 登録、chezmoi 配備は変更していない。

WSL2 の証跡は `/tmp/herdr-273-wsl-verified/`。kernel `6.18.33.2-microsoft-standard-WSL2`、Herdr 0.9.0、Nix 2.34.6、Codex 0.153.4、Python 3.13.13、Git 2.54.0、bubblewrap 0.11.2 で、`report.json` の6項目が成功した。Bats 経由の統合試験も成功し、ログは task worktree の `tmp/issue-273/herdr-bats-final.log` に残した。

通常 Linux の最終証跡は `/tmp/herdr-273-linux-63046be/`。実装 commit `63046be` を KVM 上の NixOS、通常ユーザー uid 1000、kernel `6.18.33` で実行し、6項目が成功、VM driver は exit 0。ツール版と管理対象 manifest の SHA-256 は上記 WSL2 と同一だった。

全 Bats は次のコマンドで675件を実行し、661成功・既存 opt-in 10 skip・4失敗、exit 1 だった。今回の実 Herdr 統合とコピー15件はすべて成功。ログは `tmp/issue-273/full-suite.log`、集計は `full-suite-summary.json` に保存した。

```bash
nix develop .#wsl --command env -u FORCE_COLOR SECRET_ISOLATION_REAL_RUNTIME=1 HERDR_ISOLATION_REAL=1 bun run test
```

4失敗は既存 `tests/secret-isolation.bats` のケースで、継承した長い `TMPDIR` 配下の fixture に `provider.sock` を bind すると `AF_UNIX path too long` になるもの。テスト・`scripts/secret-isolation-probe.py`・`tests/fixtures/secret-isolation/runtime.py` は固定点から変更されていない。コードは変更せず、`TMPDIR=/tmp BATS_TMPDIR=/tmp` だけを指定して同じファイルを再実行し、5件すべて成功、exit 0 を確認した。再実行ログは `tmp/issue-273/secret-isolation-short-tmp.log`。初回全体実行の exit 1 はそのまま記録し、全675件を再実行した成功結果とは扱わない。失敗を隠すテスト変更や skip は追加していない。

```bash
nix develop .#wsl --command env -u FORCE_COLOR TMPDIR=/tmp BATS_TMPDIR=/tmp SECRET_ISOLATION_REAL_RUNTIME=1 bats tests/secret-isolation.bats
```

既存コピー15件、TypeScript typecheck、Python の構文・Ruff、`nixfmt --check`、`nix flake check --no-build --all-systems`、差分検査は成功した。VM の既定経路も driver build が成功し、既存 Python testScript の構文・型検査を通過した。commit hook の oxfmt／gitleaks／cog も成功した。

`code-review` の固定点は `6412429243a4326fa2fc748eae445f35f10fcdc9`。実装 commit `63046be` に対する独立した Standards／Spec レビューでは、規約違反は0件、未依頼の拡張・実装内容の誤りも0件。Standards のテスト手順分割という非ブロッキング提案1件は、状態を引き継ぐ一連の統合試験を見渡せる現在の順序を維持して見送った。Spec の指摘1件は最終 Linux／全 Bats の検証記録が未確定というもので、上記の実行結果と再検証条件を確定して追記した。

## PR #282 のレビュー対応

検証用 flake の system は、既存 probe と同様にホストのアーキテクチャから `x86_64-linux`／`aarch64-linux` を選ぶ。専用 Herdr server の停止は終了コードを確認し、停止コマンドやログ保存が例外になってもプロセスを回収する。通常の停止待機がタイムアウトしたら TERM、さらに待機しても終了しなければ KILL と wait を行い、失敗は成功へ変換せず報告する。

`tests/helpers/herdr-codex-isolation.py` の7件は、両アーキテクチャを模した入力から生成した flake の Nix 評価と、実プロセスによる正常停止・停止コマンド非0・停止待機タイムアウト・TERM 無視・停止コマンド例外・ログ保存例外の終了／回収を確認する。ARM 実機での Herdr／Codex 統合は未実行。

修正後の WSL2 で `HERDR_ISOLATION_REAL=1` を指定し、`tests/herdr-codex-isolation.bats` と `tests/herdr-copy-env.bats` を実行して17件すべて成功、exit 0。新しい回帰7件、実 Herdr／Codex 統合、既存コピー15件を含む。証跡は `tmp/issue-273/review-round-bats.log`。上記の初回全675件の結果は変更せず、今回の追加検証として記録する。

同じ修正を `scripts/secret-isolation-linux-vm.py --herdr --output /tmp/herdr-273-linux-review-282` でも確認し、Linux kernel `6.18.33` の実 Herdr／Codex 統合6項目が成功、VM driver は exit 0。証跡は `/tmp/herdr-273-linux-review-282/evidence/report.json`。Ruff の lint／format、Nix と文書の format、差分検査も成功した。
