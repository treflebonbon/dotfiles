---
type: research
title: 長い一時パスでの Unix socket 失敗の修正と再検証
description: PR 296 の受入時に残った TMPDIR 短縮回避を、gateway と Playwright のソケット生成で解消する。
tags: [unix, codex-isolation, playwright, regression]
timestamp: 2026-09-10
---

# 長い一時パスでの Unix socket 失敗の修正と再検証

## Contract

ユーザーの「パス長エラーの解消と再検証」「対応して」を受けた、PR #296 のフォローアップ。基点は merge commit `ce608b8b6b5127b238dbc267a60e1cc3cc06de8c`。

- AC1: Linux/WSL2 の隔離 gateway が、Unix socket 上限を超える一時ディレクトリでも起動し、既存の認可・拒否動作を維持する。
- AC2: Playwright CLI の通常の一時パスが長くても、Dogfood の注釈接続・通信・終了が手動の TMPDIR 短縮なしで動作する。
- AC3: ソケットの分離、ディレクトリの所有者・権限、正常終了・起動失敗時のリソース管理を維持する。既存の短いパスと明示的なソケット保存先指定を尊重する。
- AC4: 元の失敗を再現し、長い一時パスのままで影響テストと全体回帰を実行し、結果と実行できなかった検証を区別する。

対象外はツールの再更新、APM の live audit、既に merge 済みの PR の変更。修正の配備は新しい PR の受入後とする。

## 原因と修正

Linux の pathname socket は `sun_path[108]` に終端を含めて収める必要があり、ファイルシステム自体が扱えるパスより短い。[Linux unix(7)](https://www.man7.org/linux/man-pages/man7/unix.7.html)。Node の IPC も OS の同じ制限を受ける。[Node net documentation](https://nodejs.org/api/net.html#identifying-paths-for-ipc-connections)。

gateway の `mkdtemp(prefix="cxi-")` は TMPDIR を継承するため、短い prefix でも二重の Nix shell や Bats の親ディレクトリが長い場合に失敗した。Linux で実際のソケットアドレスが107バイトを超える場合だけ、開いたディレクトリの `/proc/<pid>/fd/<fd>/service.sock` を使って bind する。ソケットファイルの置き場所は指定ディレクトリのまま維持し、隔離内は従来の `/gateway/<service>/service.sock` に接続する。ホスト側のテストクライアントは `server.server_address` を使う。descriptor は server の生存期間だけ保持し、起動失敗時と `server_close()` で閉じる。

Playwright CLI 0.1.19 の上流 `makeSocketPath` はファイル名をハッシュ化しても親ディレクトリが長いと例外を出していた。Nix パッケージ内でこの境界だけを patch し、通常の一時パスから作るソケットが上限を超えたときに `/tmp/pwcli-<uid>/<hash>.sock` を使う。hash は元のディレクトリとセッション名の両方から計算する。保存先は0700・現在の uid 所有の実ディレクトリであることを確認し、symlink や不適切な権限は拒否する。空のディレクトリをセッションごとに増やさず、ソケット自体の削除は上流の終了処理が担う。

短いアドレスは既存経路を使う。明示された `PWTEST_SOCKETS_DIR` が長すぎる場合はエラーを維持し、その指定を無言で他の場所へ移さない。TMPDIR、profile、ログ、daemon registry は変更しない。gateway の長いパス対応は既存の raw isolation 対応先である Linux/WSL2 が対象。Playwright の fallback は Unix 向けだが、実行検証はこの WSL2 ホストで行う。

## 検証

作業ログは task worktree の `tmp/socket-path-fix/`。以前の受入記録の「短い TMPDIR による回避」は履歴として保持する。

| 検証 | 結果 |
| --- | --- |
| gateway の既存通信テスト、長い TMPDIR | 修正前2回とも約0.4秒で `AF_UNIX path too long`。修正後10件PASS |
| gateway の恒久回帰テスト | 長い2つの保存先、別プロセスからの接続、0700、descriptor 解放、ログイン欠如での起動失敗を検証 |
| 実 bubblewrap namespace から gateway へ接続 | ホストのソケットパス231バイト、隔離内の短い mount から403応答を確認 |
| Dogfood の注釈接続 | 修正前は186バイトの socket directory で失敗。修正パッケージで通常注釈・MV3注釈の2件PASS |
| Playwright のソケット回帰テスト | 日本語を含む長いパス、セッション・親ディレクトリの分離、別プロセス IPC、0700、所有者、終了時の socket 削除、明示指定のエラーを確認 |
| 全体回帰 | 実行中。完了後に件数と結果を追記する |

macOS 実行は未確認。live source への `chezmoi apply` はこの修正ブランチから実行しない。
