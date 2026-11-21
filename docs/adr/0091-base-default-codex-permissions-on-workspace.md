---
type: decision
title: 日常の Codex 権限を標準の workspace から継承する
description: linked worktree の Git 参照を復旧し、日常起動で必要な機密パスを保護する
tags: [adr, codex, permissions, git, worktree]
timestamp: 2026-11-21
status: accepted
---

# 日常の Codex 権限を標準の workspace から継承する

通常の `codex` が使用する `dotfiles-secure` は、checkout 外の Git 管理情報を `:root` の読み取り拒否で隠す。Orca の `pyrosome` linked worktree で、Codex 0.170.0 の `git status` と `git rev-parse HEAD` は終了コード 128 になった。同じ設定の `:root` を `read` に変えると両方成功した。別の候補で `:workspace` を継承した場合も両方成功し、Git 管理ファイルは書き込み用に開けなかった。

## 合意済みの方針

- 通常の Codex CLI と管理設定を同期する Codex Desktop では、`:workspace` を継承する `dotfiles` を既定にする。raw の `codex-worktree` と `codex-reviewer` はそれぞれの既存プロファイルを使い、Orca の Agent Picker は Orca が起動権限を所有する。[raw の隔離](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境) · [ADR-0080](0080-grant-reviewer-codex-read-only-git-metadata.md) · [ADR-0046](0046-separate-orca-native-worktree-entry.md)
- 作業中の workspace、`~/ghq/github.com`、`~/orca/workspaces` では、dotenv・鍵など既存の機密ファイル名の読み取りを拒否する。`.envrc` と `.env.example` は参照できるようにする。共有一時領域は [ADR-0074](0074-allow-codex-tmp-workspace.md) に従い `/tmp/codex` に限定し、各セッションの `$TMPDIR` も使えるようにする。
- 日常用の `glob_scan_max_depth` は6にする。Linux／WSL では、走査上限を越える名前や同じプロセスの起動後に現れたファイルに機密名の拒否は適用されない。`hosts.yml` などパスを指定した拒否は走査深さに依存しない。
- 日常用は `:workspace` 標準の通信制限を使い、承認が必要な操作は既存の `on-request` / `auto_review` に委ねる。[Codex のネットワーク設定](https://learn.chatgpt.com/docs/permissions#network-permissions)
- `~/.config/gh/hosts.yml` の読み取りは、通常の sandbox と承認後の実行で拒否する。認証付きリモート Git は日常用プロファイルで未対応とし、資格情報の保護を維持できる認証経路の設計と受入を後続に移す。

## 受入条件

- 通常の CLI と Desktop の新規セッションで日常用プロファイルが選択される。linked worktree の `git status` と `git rev-parse HEAD` が成功し、通常の sandbox から Git 管理情報の書き込みは拒否される。
- 両方の checkout 置き場を含む実環境で起動できる。ダミーファイルで機密名の拒否と公開サンプルの読み取りを確認する。`/tmp/codex` と `$TMPDIR` で一時ファイルを読み書きでき、通常の `/tmp` へのアクセスは拒否される。
- 通常の sandbox で `hosts.yml` の読み取りが拒否されることをダミーファイルで確認する。

## 検証状況

以下の実機検証では、候補時の名前 `dotfiles-daily` を使った。

`pyrosome` の一時設定で Git の読み取り、通常の `/tmp` の拒否、`/tmp/codex` と `$TMPDIR` の読み書きを確認した。機密ファイル名の拒否は作業中の workspace、ダミーの `ghq` 配下、`/tmp/codex`、ダミー HOME の指定した認証パスで確認した。実際の WSL 環境では、`ghq` 配下に読み取り不可のディレクトリがあり、深さ7以上の候補は走査中に停止した。深さ6では両ルートを含めた起動と Git の参照が成功した。

Desktop の新規 WSL セッションでは `dotfiles-daily` が選択され、`git status` と `git rev-parse HEAD` が成功した。Git の `HEAD` を書き込み用に開く操作と通常の `/tmp` の一覧取得は拒否され、ダミーの `.env` の内容は取得できなかった。`/tmp/codex` は読み書きでき、`.env.example` は参照できた。この Desktop セッションでは `$TMPDIR` が未設定だった。`$TMPDIR` を設定した場合の読み書きは実 sandbox の回帰テストで確認した。

ネットワークを無効にした一時 HOME で、Git 2.55.0 と `gh` 2.102.0 にダミーの `hosts.yml` を使わせた。標準の `:workspace` では Git が credential helper を呼び出せた。候補に `hosts.yml` の拒否を加えると、`gh` は設定の読み込みで停止し、Git は終了コード 128 になった。確認したのはファイルに資格情報を置く構成で、実環境の保存方式への影響は未確認。

対話 CLI の一時設定と Desktop の WSL 検証用プロジェクトで `dotfiles-daily` と `on-request` が有効になった。認証付き `git ls-remote` は両方で通常の sandbox からの名前解決に失敗し、承認経路での再試行は `bwrap` の読み取り専用エラーで停止した。Desktop では自動レビューによる承認と、`/tmp/codex` 配下の `.env` を隠すマウントの作成失敗を確認した。Codex 0.170.0 は承認後も読み取り拒否を維持するため、承認経路だけでは `hosts.yml` の読取りは許可されない。[Codex 0.170.0 の承認処理](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/core/src/tools/sandboxing.rs#L240-L281)
