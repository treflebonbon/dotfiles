---
type: reference
title: ユーザー環境キャッシュ #225 と親仕様の検証記録
description: 更新競合・入力変更・終了後の復旧と、親 #222 の全14受入条件の対応
tags: [nix, shell, cache, verification]
---

# ユーザー環境キャッシュ #225 と親仕様の検証記録

2026-09-08、linked worktree `fix-nix` の `6f8ffac` から Issue [#225](https://github.com/treflebonbon/dotfiles/issues/225) を実装した。同じブランチの #224 を引き継ぎ、#223 は base の `8f810e8` に含まれている。利用中の HOME・live source・chezmoi 配備は変更していない。

## 親 #222 の14ACとの対応

| AC                                    | 担当       | 最終形での検証と結果                                                                                                                                                                                                                                        |
| ------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AC1 シェル起動を待たせない            | #223       | `tests/user-environment-startup.bats` の bash／zsh、旧キャッシュ有無の4件を再実行。Nix が起動完了の marker を待つ adapter で、シェルが先に起動し生成失敗後も継続することを確認。                                                                            |
| AC2 内容・追加・削除・mtime保持差替え | #224       | `tests/refresh-cache.bats` の既存テストを最終形で再実行し成功。非 Nix 入力、相対名、隠しファイル、symlink、実行可能性、空ディレクトリを含む。                                                                                                               |
| AC3 選択環境と同じ入力の再利用        | #224       | WSL／通常切替、実行時生成物除外、IFS／glob option 変更での同じ入力の再利用が成功。#225 の待機後の再利用も複数 process で確認。                                                                                                                              |
| AC4 Nix途中出力・非0終了とpipefail    | #223       | `tests/refresh-cache.bats` の背景／必須×pipefail有無の既存検証を再実行し成功。入力変化を伴う失敗した評価だけは #225 の上限付き再試行へ進む。                                                                                                                |
| AC5 検査・置換失敗時の保護            | #223・#224 | 空・構文不正・rename・指紋計算・準備失敗でキャッシュ全体を保持し、再実行できる既存検証が成功。ロック依存／保存先の不備も追加確認。                                                                                                                          |
| AC6 更新の直列化と待機後の再確認      | #225       | `tests/refresh-cache-concurrency.bats` で背景更新の即時省略、必須更新の待機と同じ入力の再利用、先行採用後もロック待機中に変わった入力の再評価を確認。評価開始の順序と採用値を観測。                                                                         |
| AC7 評価中の変更で1回再試行           | #225       | Nix adapter の同期点で入力を変更。1回目の結果が読み手に見えず、2回目の最新入力だけを採用。失敗出力を伴う1回目でも同様に再試行し復旧。                                                                                                                       |
| AC8 再試行中の変更で停止              | #225       | 背景／必須それぞれで2回の評価中に入力を変更。3回目の評価なし、旧キャッシュ全体の不変、終了状態0／1を確認。その後の安定した更新は成功。                                                                                                                      |
| AC9 旧形式からの移行                  | #224       | 旧形式の読込み、必須更新での移行、変更なしの再利用を最終形で再実行し成功。                                                                                                                                                                                  |
| AC10 読込みの整合と終了後の復旧       | #224・#225 | 単一ファイルの採用単位を維持。評価を止めた状態、1回目を破棄して2回目を待つ状態でも読み手は旧値を取得。評価中の更新元を SIGKILL、採用前の指紋確認中を SIGTERM で終了し、残る子を待たず次の更新が成功。古い子の完了で上書きされず、一時出力も次の更新で回収。 |
| AC11 必須更新失敗時の配備停止         | #223・#225 | 通常配備・APM・初回導入の各実入口で先行背景更新と競合。待機中の変更後の成功、変わり続ける入力、途中出力を伴う生成失敗の9件を確認。失敗時は既存キャッシュ保持、APM install／prune、direnv allow、導入成功表示を実行しない。                                  |
| AC12 既存の読込み・シェル識別情報     | #223・#224 | ensure-env、bashプロンプトのGNU／BSD stat対応、既存zsh起動から新形式のplugin取込み、shell identity／option保持を再実行し成功。CONTEXT.md の既存「ユーザー環境キャッシュ」定義はこの責務と一致し、用語の追加・変更は不要。                                   |
| AC13 初回導入と依存                   | 全3件      | キャッシュ不在、初期PATHのOSコマンドとNix adapterで成功。shasumだけの経路も維持。system Perl不在は配備前に停止。WSL2で実Nixを確認。macOS実機／Bash3.2と非WSL Linux実機は未確認であり、全OS実機確認済みとはしない。                                          |
| AC14 実Nixの生成・読込み              | #224・#225 | 下記の一時環境で最終形の生成、環境値・コンパイラの読込み、背景／必須の重なり、変更なしの再利用を確認。実ユーザーdevShell全体のビルド・実配備は対象外。                                                                                                      |

#223／#224 の根拠は [#224 検証記録](user-environment-cache-224-verification.md) と既存の入口テストに保持する。今回の更新経路に関係する95件を再実行し成功した。

## 最終品質確認

実装コミットは `44b23cf`（`fix(nix): serialize cache refreshes and retry changed inputs`）。最終実装で以下を確認した。

- `bun run test`: 全511件成功、失敗0件、skip0件。ログは `/tmp/issue-225-full.log`。
- `bunx tsc --noEmit`: 成功。
- 更新ライブラリ・`install.sh`・追加した配備競合helperのShellCheck、およびコミット時のlefthook検査（shfmt、ShellCheck、oxfmt、gitleaks、Conventional Commits）: 成功。
- `git diff --check`: 成功。
- `6f8ffac...44b23cf` を対象に、独立した2つのagentで規約・仕様をレビュー。Standardsは規約違反0件・コードスメル0件、SpecはIssue #225・ADR・本検証記録との不一致0件。

親の14ACについて、この環境で検証可能な自動テストと実Nix確認は成功した。OS実機ごとの未確認範囲はAC13と下記に明記する。

## 再現と終了処理の診断

旧実装では `bats tests/refresh-cache-concurrency.bats` の背景更新省略が失敗し、2つ目も評価に入り完了待ちとなった。ロック導入後、評価中の変更テストは再試行せず古い結果を採用して失敗した。二段階の同期点で、それぞれ red→green を確認した。

採用前の確認中に更新元を終了するテストでは、入力確認の内部だけでロック記述子を閉じても、結果を待つ command substitution の中間 Bash が descriptor 9 を保持して次の更新を止めた。対象ファイルの `lsof` で残存 Bash の保持を確認し、中間 process 自体でも閉じるように修正した。同じテストで次の更新が完了し、古い評価結果は採用されないことを確認した。調査用の `lsof` 計測はテストから除去済み。

## 初回導入・OS依存

排他は初期 PATH の system `perl` と core の `Config`／`Fcntl` を使う。`Config` の `d_flock=define` を要求し、native flock がない実装の emulation は使わない。生成後の devShell の Perl／Python／Node、GNU util-linux の `flock` CLI、PID記録と期限によるlock強制回収には依存しない。

Perlの `flock` は native flock 以外に emulation も持つため、継承した open file description を使うこの実装では native 対応を確認する。LOCK_NB による非待機の動作は [Perl公式マニュアル](https://perldoc.perl.org/functions/flock)、fork／dupでの同一lockの参照と非待機のエラーは [Appleのflock(2)資料](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html)、最後のdescriptorを閉じたときの解放は [Linuxのflock(2)資料](https://man7.org/linux/man-pages/man2/flock.2.html) を照合した。

WSL2上の `/usr/bin/perl` 5.38.2 とOSコマンドで、ロックの継承・背景省略・必須待機・更新元終了後の解放を実行した。READMEのWSL導入コマンドに `perl` を明示し、`install.sh` の前提確認にも追加した。macOSは初期PATHのnative flock対応Perlを前提にするが、現行macOSでの標準搭載状況・Bash3.2・BSDコマンドとの組合せはこのホストでは未確認。Linux上のshasum経路のテストはmacOS実機確認の代用とはしない。キャッシュは既存のローカルHOME filesystemを対象とし、network filesystemのlock挙動は未検証。

## 最終形の実 Nix

環境は x86_64 WSL2（Ubuntu-24.04、kernel `6.18.33.2-microsoft-standard-WSL2`）、Nix `2.34.6`、Bash `5.2.21`。`/tmp/issue-225-real-nix-lgqx3m20` に入力・HOME・キャッシュ・ログ・呼出し記録用のNix wrapperを隔離し、wrapperは実Nixバイナリへそのまま委譲した。

#224と同じlock済みの小さな `mkShell` flakeを使い、`CACHE_SMOKE` がpayloadファイルの内容を返す `default`／`wsl` outputを定義した。初期PATHは一時wrapperとNixの導入先、`/usr/bin:/bin` だけとした。

- 初回キャッシュなしから `.#wsl`の生成に成功。`ensure_nix_devshell_env` で `CACHE_SMOKE=wsl-old`、`SHELL=/bin/bash` を確認。
- `command -v cc` は `/nix/store/788mx070y81zjlg5ipcl0cra3afviw9k-gcc-wrapper-15.2.0/bin/cc` を返した。
- 変更なしの反復はキャッシュ全体が `cmp` で不変。
- mtimeを保持してpayloadを `fresh` へ変更し、背景更新と必須更新を重ねて実行。両方が正常終了し、読込み値は `wsl-fresh` となった。
- その後の変更なしの必須更新も含め、実Nix呼出しは初回と変更後の計2回だけだった。

実行スクリプト `/tmp/issue-225-real-smoke.sh`、ログ `/tmp/issue-225-real-smoke.log`、同期点付きテストのログ `/tmp/issue-225-related.log` を残した。一時証跡の永続保存は保証しないため、観測値と条件を本書に記録する。実Nixの同時実行はスケジューラ依存の開始順を固定していない。競合順序・強制終了・再試行の決定的な検証はBatsの同期点付きadapterが担う。
