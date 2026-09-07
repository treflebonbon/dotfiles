---
type: reference
title: ユーザー環境キャッシュ #224 の検証記録
description: 入力内容・環境選択による単独更新、初回導入の依存、実 Nix 生成と読込みの確認範囲
tags: [nix, shell, cache, verification]
---

# ユーザー環境キャッシュ #224 の検証記録

2026-09-08、Issue [#224](https://github.com/treflebonbon/dotfiles/issues/224) を linked worktree `fix-nix`、開始 commit `8f810e8` で実装した。以下は単独更新の検証であり、競合と評価中の入力変更は #225 に残る。利用中の HOME、live source、chezmoi 配備は変更していない。

## 受入条件と検証

| #224 の条件                                  | 確認方法・結果                                                                                                                                                                                                                                 |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ソースの内容・追加・削除を拡張子によらず反映 | `tests/refresh-cache.bats` で `.mjs` の mtime を保持した差し替え、追加・削除・改名、隠しファイル、改行を含む名前、実行権限、symlink、空ディレクトリを更新 interface から確認。最初に旧実装の `.mjs` 更新漏れでテストが失敗することを確認した。 |
| WSL／通常環境の選択を鮮度に含める            | 同じキャッシュで通常→WSL→通常を切り替え、環境値と Nix の評価有無を確認。通常側は host の `/proc` 判定だけを adapter で固定した。                                                                                                               |
| 入力が同じなら再評価しない                   | 更新の反復、mtime だけの変更、`.direnv` 状態・`result` 出力リンクの追加変更、呼出し元の glob option・IFS 変更で Nix が呼ばれないことを確認。                                                                                                   |
| キャッシュと入力情報を一体で保護・採用       | 有効な既存キャッシュから入力を変え、空・構文不正・rename 失敗・指紋計算失敗を再現。全内容の不変と旧環境の読込みを確認。入力を元へ戻すと評価不要となり、新しい入力での再実行は成功する。                                                        |
| 旧形式からの移行と読込み                     | 旧形式を `ensure_nix_devshell_env` で読込み、必須更新で再生成、反復時の評価省略を確認。新形式も既存 zsh 起動から plugin を取り込める。既存 bash プロンプト再読込み・shell identity・shell option の回帰テストを維持。                          |
| 通常配備・APM・初回導入から利用              | `tests/run_after_00-refresh-nix-devshell-cache.bats`、`tests/apm-cache-refresh.bats`、`tests/install.bats` で実際の入口と更新 lib を実行。変更なしの省略、非 Nix 入力追加での更新、失敗時の停止と後続処理の未実行を確認。                      |
| 初回キャッシュと依存                         | キャッシュなし、PATH を OS コマンドと Nix adapter に限定して生成。`sha256sum` なしの `shasum` 経路でも初回導入が成功し、両コマンドの切替で指紋が変わらない。両方ない場合は必須更新が失敗し、背景更新は旧キャッシュを保持。                     |
| 実 Nix による生成・読込み                    | 下記の一時 flake で WSL 用環境値とコンパイラの利用、内容更新、変更なしの再利用を観測。                                                                                                                                                         |

## 実 Nix の実行

実行環境は x86_64 Linux / WSL2（kernel `6.18.33.2-microsoft-standard-WSL2`、`WSL_DISTRO_NAME=Ubuntu-24.04`）、Nix `2.34.6`、OS Bash `5.2.21`。`/tmp/issue-224-real-nix-2dm3umea` に入力・HOME・キャッシュ・ログを隔離した。

一時 flake は repo の lock にある nixpkgs store path を入力とし、`mkShell` の `CACHE_SMOKE` に `builtins.readFile ./payload.txt` を設定した。`default` と `wsl` の両 output を定義し、`wsl` 側には `wsl-` prefix を付けた。生成前に一時 flake の lock を作成し、実装した `refresh_nix_devshell_cache <input> <cache> <log>` を `NIX_DEVSHELL_CACHE_REQUIRED=1` で実行した。PATH は `/nix/var/nix/profiles/default/bin:/usr/bin:/bin`、HOME は一時領域に限定した。

観測結果:

- 初回キャッシュなしから `nix print-dev-env .#wsl` が生成に成功。別 Bash process の `ensure_nix_devshell_env` で `CACHE_SMOKE=wsl-old` を確認。
- `command -v cc` は `/nix/store/788mx070y81zjlg5ipcl0cra3afviw9k-gcc-wrapper-15.2.0/bin/cc` を返した。`SHELL=/bin/bash` を保持。
- 直後の反復は更新通知なし、キャッシュの内容は `cmp` で不変。
- `payload.txt` を `old` から `fresh` へ差し替え、`touch -r` で元の mtime を復元した後、再生成・再読込みで `CACHE_SMOKE=wsl-fresh` を確認。
- 変更後の反復も更新通知なしで再利用した。

実行スクリプトは `/tmp/issue-224-real-smoke.sh`、出力は `/tmp/issue-224-real-smoke.log`。一時証跡は永続保存を保証しないため、観測値と実行条件を本書に残す。

## 依存と確認の限界

新しい外部コマンドは SHA-256 用の `sha256sum` または `shasum -a 256`、末尾の入力情報を読む `tail -n 1`、symlink を読む `readlink`。GNU/BSD 間で差が出る `stat` や NUL sort、生成後の Python／Node には依存しない。SHA-256 は標準入力で計算して出力のファイル名表示差を除く。`shasum` の方式と標準入力の仕様は [Perl の公式マニュアル](https://perldoc.perl.org/5.40.5/shasum) に従う。

Linux／WSL の初期 PATH は OS の coreutils を前提とし、この WSL2 環境の `/usr/bin/sha256sum`、`tail`、`readlink` で実行した。macOS 向け経路は OS の `shasum`／`tail`／`readlink` を前提とする。Linux 上で `sha256sum` を PATH から外し、`/usr/bin/shasum` だけで初回生成と移行を検証したが、macOS 実機の標準 PATH・Bash 3.2・BSD コマンドの組合せは未確認。通常 Linux の選択は adapter で検証し、非 WSL の実機での実 Nix 更新は未確認。

実 Nix の確認は小さな `mkShell` の単独更新経路に限る。ユーザー devShell 全体の再ビルドや実配備、並行更新、評価中の入力変更、プロセス中断後の後始末は今回の実機確認に含まない。

## 最終品質確認

- `bun run test`: 全492件成功、失敗・skipなし。
- 最終実装で `tests/refresh-cache.bats` と通常配備・APM・初回導入の4ファイルを再実行: 67件成功。
- `bunx tsc --noEmit`、ShellCheck、shfmt、oxfmt、gitleaks、`cog verify` が成功。コミットフックの迂回なし。
- `code-review` は開始 commit `8f810e8` からの変更を Standards／Spec の2軸で独立レビューし、各0件。呼出し元 IFS に依存する指紋解析を追加の red→green で修正した `0397042` も、両軸の再レビューで各0件。

全体テストのログは `/tmp/issue-224-full.log`、最終実装の関連テストは `/tmp/issue-224-final-targeted.log` に残した。
