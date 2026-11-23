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
- 作業中の workspace、`~/ghq/github.com`、`~/orca/workspaces` では、dotenv・鍵など既存の機密ファイル名の読み取りを拒否する。`.envrc` と `.env.example` は参照できるようにする。
- 日常用の `/tmp` と `$TMPDIR` のアクセスは `:workspace` に委ねる。通常の `/tmp` も OS のファイル権限の範囲で読み書きできる。セッション間の共有先は [ADR-0074](0074-allow-codex-tmp-workspace.md) の `/tmp/codex` とし、起動時の準備と配下の機密名の拒否を維持する。機密名の走査範囲は一時領域では `/tmp/codex` に留める。`dotfiles-secure` の一時領域の規則は引き続き ADR-0074 に従う。
- 管理同期では、既存の日常用の `":slash_tmp" = "deny"` と `/tmp/codex` の管理済み書き込み指定を取り除き、新規配備と同じ継承結果に揃える。`/tmp/codex` 配下の拒否規則や利用者が追加した設定は保持する。
- 日常用の `glob_scan_max_depth` は6にする。Linux／WSL では、走査上限を越える名前や同じプロセスの起動後に現れたファイルに機密名の拒否は適用されない。`hosts.yml` などパスを指定した拒否は走査深さに依存しない。
- 日常用は `:workspace` 標準の通信制限を使い、承認が必要な操作は既存の `on-request` / `auto_review` に委ねる。[Codex のネットワーク設定](https://learn.chatgpt.com/docs/permissions#network-permissions)
- `~/.config/gh/hosts.yml` の読み取りは、通常の sandbox と承認後の実行で拒否する。認証付きリモート Git は日常用プロファイルで未対応とし、資格情報の保護を維持できる認証経路の設計と受入を後続に移す。

## 受入条件

- 日常用プロファイルを既定にする PR #620 のマージは、Linux／WSL 上の CLI と Desktop の両方で、既存の `.env` symlink がある workspace でも通常コマンドが起動し、ダミーのリンク先の内容を読み取れないことを確認するまで保留する。
- 通常の CLI と Desktop の新規セッションで日常用プロファイルが選択される。linked worktree の `git status` と `git rev-parse HEAD` が成功し、通常の sandbox から Git 管理情報の書き込みは拒否される。
- 両方の checkout 置き場を含む実環境で起動できる。ダミーファイルで機密名の拒否と公開サンプルの読み取りを確認する。`/tmp`、`/tmp/codex`、設定済みの `$TMPDIR` で一時ファイルを読み書きでき、`$TMPDIR` が未設定でも `mktemp` が成功する。`/tmp/codex` 配下のダミーの機密ファイルは読み取れない。
- 管理同期の新規・既存両ケースで同じ日常用プロファイルに収束する。既存の `dotfiles-secure` の規則と、利用者が追加した拒否は保持される。
- 通常の sandbox で `hosts.yml` の読み取りが拒否されることをダミーファイルで確認する。
- `.env` symlink の保護に対応した公式 Codex の配布を待つ。その版で symlink の保護、読み取り不可の別 checkout がある場合の起動、承認後の公開依存の取得を再検証する。起動と取得の結果も確認してマージ可否を判断する。

### 候補版の再検証

Linux／WSL の CLI と Desktop の新規セッションで、実行側の Codex の版、選択された `dotfiles` プロファイル、承認の結果を記録する。最初に linked worktree の Git 参照と書き込み拒否、通常の `.env` の拒否と `.env.example` の参照、一時領域、ダミーの `hosts.yml` の拒否を確認する。以下の各ケースを独立した検証環境で実行し、他のケースのダミーファイルが走査に入らないようにする。

| ケース | ダミー環境と確認項目 |
| --- | --- |
| `.env` symlink | workspace 直下に、名前による拒否に該当しないファイルを指す `.env` symlink を置く。通常コマンドが起動し、`.env` 経由でダミー値を取得できず、`.env.example` を参照できることを確認する。ダミーの実パスからの読み取り結果も別に記録する。 |
| 別 checkout の走査 | 別 checkout の走査範囲内に読み取り不可のディレクトリと、列挙可能な場所にダミーの `.env` を置く。正常な linked worktree から `git status` が成功し、別 checkout のダミー値を取得できないことを確認する。 |
| 承認後の sandbox 起動 | `/tmp/codex` の走査範囲内にダミーの `.env` を置く。既存の承認経路で承認されたコマンドが起動し、ダミーの `.env` と `hosts.yml` の内容が保護されることを確認する。コマンド起動前の `bwrap` エラーは終了コードとともに記録する。 |
| 承認後の通信 | `/tmp/codex` に機密名ファイルがない条件で、認証不要の公開依存を承認後に取得できることを確認する。sandbox の起動、名前解決、取得の成否を記録し、通信結果とマウントの失敗を区別する。 |

## 検証状況

以下の実機検証では、候補時の名前 `dotfiles-daily` を使った。

`pyrosome` の一時設定で Git の読み取り、通常の `/tmp` の拒否、`/tmp/codex` と `$TMPDIR` の読み書きを確認した。機密ファイル名の拒否は作業中の workspace、ダミーの `ghq` 配下、`/tmp/codex`、ダミー HOME の指定した認証パスで確認した。実際の WSL 環境では、`ghq` 配下に読み取り不可のディレクトリがあり、深さ7以上の候補は走査中に停止した。深さ6では両ルートを含めた起動と Git の参照が成功した。

Desktop の新規 WSL セッションでは `dotfiles-daily` が選択され、`git status` と `git rev-parse HEAD` が成功した。Git の `HEAD` を書き込み用に開く操作と通常の `/tmp` の一覧取得は拒否され、ダミーの `.env` の内容は取得できなかった。`/tmp/codex` は読み書きでき、`.env.example` は参照できた。この Desktop セッションでは `$TMPDIR` が未設定だった。`$TMPDIR` を設定した場合の読み書きは実 sandbox の回帰テストで確認した。

ネットワークを無効にした一時 HOME で、Git 2.55.0 と `gh` 2.102.0 にダミーの `hosts.yml` を使わせた。標準の `:workspace` では Git が credential helper を呼び出せた。候補に `hosts.yml` の拒否を加えると、`gh` は設定の読み込みで停止し、Git は終了コード 128 になった。確認したのはファイルに資格情報を置く構成で、実環境の保存方式への影響は未確認。

対話 CLI の一時設定と Desktop の WSL 検証用プロジェクトで `dotfiles-daily` と `on-request` が有効になった。認証付き `git ls-remote` は両方で通常の sandbox からの名前解決に失敗し、承認経路での再試行は `bwrap` の読み取り専用エラーで停止した。Desktop では自動レビューによる承認と、`/tmp/codex` 配下の `.env` を隠すマウントの作成失敗を確認した。Codex 0.170.0 は承認後も読み取り拒否を維持するため、承認経路だけでは `hosts.yml` の読取りは許可されない。[Codex 0.170.0 の承認処理](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/core/src/tools/sandboxing.rs#L240-L281)

### Codex 0.170.0 の Linux sandbox で確認した制約

- 明示的に承認されたコマンドのファイルシステム規則を再現した隔離環境では、`/tmp/codex/task/.env` のダミーファイルを置くと `bwrap` がマウント先を作れず、`true` の起動も失敗した。マウントの失敗はコマンドの実行前に起きるため、認証不要の依存取得にも影響する。[承認後のファイルシステム規則](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/protocol/src/permissions/target.rs#L46-L90)
- 深さ6以内の別 checkout に読み取り不可のディレクトリを置くと、glob の列挙エラーで正常な workspace のコマンドも起動しなかった。深さ6は実環境で観測した深いディレクトリを走査から外す設定であり、列挙エラーの扱いは Codex 本体が決める。[Linux の glob 列挙](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/linux-sandbox/src/bwrap.rs#L929-L1012)
- glob の列挙は子 symlink を対象外にする。workspace の `.env` から名前の拒否条件に該当しないダミーファイルへリンクすると、shell からリンク先の内容を取得できた。同じ `.env` を個別に `deny` すると、書き込み可能な symlink を検出して sandbox の起動自体が失敗した。[Linux の deny マウント](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/linux-sandbox/src/bwrap.rs#L1204-L1235)

公式安定版 0.171.0 と 0.173.0-alpha.4 のソースでも、glob の列挙は子 symlink を対象外にしている。両版の確認はソースの比較までで、実機での再検証は未実施。[0.171.0 のソース](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/linux-sandbox/src/bwrap.rs#L962-L984) · [0.173.0-alpha.4 のソース](https://github.com/openai/codex/blob/rust-v0.173.0-alpha.4/codex-rs/linux-sandbox/src/bwrap.rs#L962-L984)

### 2026-11-23 の一時領域の再評価

Codex 0.170.0 と管理テンプレートのダミー比較では、日常用の `/tmp` を標準に委ねると、`$TMPDIR` が未設定でも `mktemp` が成功した。承認後のファイルシステム規則を再現した試験でも、`/tmp/codex` にダミーの `.env` がある状態でコマンドが起動し、その内容は拒否された。共有領域外のダミーは読めた。`/tmp` 全体を機密名の走査対象にすると、読み取り不可のディレクトリで sandbox が起動しなかった。

管理同期のダミー比較では、テンプレートから一律拒否を省くだけでは、以前の `deny` が配備済みの設定に残った。候補設定を使った Desktop の実承認と公開依存の取得は、受入時に確認する。
