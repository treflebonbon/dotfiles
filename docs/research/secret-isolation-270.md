---
type: research
title: 専用 Nix store と実 Codex の隔離起動検証
description: Issue 270 の合成 fixture、公開する入力、検証結果と本番移行前の未確認事項。
tags: [research, nix, codex, sandbox, secrets]
timestamp: 2026-09-09
---

# 専用 Nix store と実 Codex の隔離起動検証

対象は [#270](https://github.com/treflebonbon/dotfiles/issues/270)、親仕様は [#268](https://github.com/treflebonbon/dotfiles/issues/268)。検証コードは [起動 script](../../scripts/secret-isolation-probe.py) と [合成連携](../../tests/fixtures/secret-isolation/runtime.py)、自動検証の入口は [Bats](../../tests/secret-isolation.bats)。本番の `codex-worktree`、Herdr、配備済み設定は変更しない。

以下は初回と PR #276 の記録である。通常 Linux・実サービス・実 worktree に残っていた不足の追加検証は文末を参照する。

## 検証する境界

host 上では固定された公開 CLI の closure を `nix copy --to <専用ディレクトリ> --no-check-sigs` で準備する。この時点ではプロジェクトの flake や shellHook を評価しない。環境は専用 HOME と固定 PATH から構築し、呼出し元の認証・設定を継承しない。コピー元は明示したツールの Nix store path とその依存だけで、host の store 全体を bind しない。署名検査の省略は既にローカルで信頼する入力を検証専用 store へコピーする操作に限る。

bubblewrap が mount/user/PID/network 等の namespace を分離し、空の root、HOME、`/tmp`、専用 `/proc` と `/dev` を用意する。その後に初めて flake を評価し、`nix print-dev-env` の結果を読み、shellHook、実 Codex、コマンドと子プロセス、stdio MCP を実行する。

Nix の build sandbox はこの外側隔離の内側でだけ無効化する。専用 local store を非特権で使うためであり、host Nix daemon へ接続する fallback はない。Codex は合成設定の workspace permission profile を使い、Git metadata と証跡ディレクトリへの必要な書込みだけを加える。Codex の sandbox bypass flag は使わない。

bare `builtins.derivation` の fixture では `outputs = [ "out" ]` を明記する。`nix print-dev-env` は builder を環境取得用 script に置換し、その script は `$outputs` を列挙して出力を書き込む。明記せずに発生した「output を生成しない」失敗は fixture の欠陥であり、Nix と外側隔離の非互換ではなかった。[Nix develop.cc](https://raw.githubusercontent.com/NixOS/nix/2.34.6/src/nix/develop.cc)、[get-env.sh](https://raw.githubusercontent.com/NixOS/nix/2.34.6/src/nix/get-env.sh)

## 入力の契約と保証の限界

| 領域         | 公開範囲                                                                    |
| ------------ | --------------------------------------------------------------------------- |
| Nix          | 明示した CLI closure、専用 DB と生成物。host daemon socket は非公開         |
| 通常コード   | fixture が選んだ秘密を含まないファイルの独立コピー                          |
| Git          | 隔離内で作成した primary repo と linked worktree の metadata のみ           |
| HOME・cache  | 新規の空の領域。host の CODEX_HOME、Git/GH 設定、MCP 認証は非公開           |
| プロセス     | 同じ外側 PID namespace のプロセスだけ                                       |
| ネットワーク | 独立 namespace の loopback に作成した合成サービスだけ                       |
| 認証         | 合成 GitHub API 用のダミー値のみ。モデル API と stdio MCP は実認証なし      |
| 証跡         | この fixture だけのディレクトリ。実プロジェクト・実秘密を入力に受け付けない |

秘密を含む host worktree 全体を mount して deny pattern で隠す構成ではない。**独立コピーの成功を、実際の Herdr worktree の直接編集・変更返却・Git metadata 共有の成立と読み替えない。** 任意の許可入力に秘密が埋め込まれている場合の検出器でもない。秘密のない入力を選定する責務と、snapshot から成果を返す方式は本番化前の課題として残る。

モデル側は合成 Responses API で、実 Codex がツール要求を受信して実行する。GitHub 側も loopback の合成 API へ実 `gh` を接続する。stdio MCP server は合成だが、起動と JSON-RPC の実行主体は実 Codex である。[プロトコルの一次資料](codex-secret-isolation-protocol-270.md)を参照。実モデル推論、GitHub 認証・書込み、Context7/Serena の認証付き実接続を検証したものではない。

## 再現方法

Linux または WSL2 で user namespace と bubblewrap が利用でき、Nix store 由来の `nix`、`bash`、`coreutils`、`python3`、`git`、`codex`、`gh`、`bwrap` が PATH にあることを前提とする。

```bash
python3 scripts/secret-isolation-probe.py --output /tmp/secret-isolation-270-result
SECRET_ISOLATION_REAL_RUNTIME=1 bats tests/secret-isolation.bats
```

repo の devShell 単体は `codex`・`gh`・`bwrap` を提供しないため、通常の `bun run test` では実ランタイムを要するケースを理由付きで skip する。リンク入力の拒否は通常実行でも検証する。実ランタイム検証は上記の明示指定で実行し、指定後の OS・ツール不足や隔離構成失敗を skip／成功へ変えない。必要な CLI はユーザー環境などで事前に用意する。skip した実行は #270 の受入証跡にならない。

`--output` は新規ディレクトリを指定する。専用 store は closure 分のディスクを使用する。生成するログは合成データだけであり、repo へ自動追加しない。Bats は自身の一時 fixture を後始末する。

## 結果

2026-09-09、WSL2 x86_64、kernel `6.18.33.2-microsoft-standard-WSL2` で実測した。Nix 2.34.6、Codex 0.153.4、bubblewrap 0.11.2、Bash 5.3.9、Python 3.13.14、Git 2.54.0、GitHub CLI 2.96.0、coreutils 9.11 を使用した。取込み元は 8 個の tool root、依存 closure は 120 store path、専用 store は約 1 GiB だった。Nix の版や closure は環境ごとに `report.json` と `closure.txt` へ記録する。

| #270 の受入項目                        | 観測結果                                                                                                                                                              |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nix より前の隔離・専用 store・devShell | WSL2 で成功。Nix 評価中と shellHook 内の境界検査も成功                                                                                                                |
| 実 Codex 本体・コマンド・子・local MCP | 成功。本体の namespace・環境を確認し、各実行経路で同じ秘密取得プローブを実行                                                                                          |
| 通常編集・build・test・stage・commit   | 隔離内の linked worktree で成功。Git common dir は `/repo/.git`、worktree metadata は `/repo/.git/worktrees/work`                                                     |
| GitHub・MCP                            | 実 `gh` の GET と実 Codex の stdio MCP handshake/tool call が成功。API/MCP server は合成で、実接続・実認証は未確認                                                    |
| 公開入力・HOME・cache・process・socket | 表の範囲だけを公開。host namespace と異なること、host provider TCP/Unix socket に接続できないことを確認                                                               |
| link・起動後の追加/差替え              | 入力が symlink/hardlink なら起動前に拒否。実行中の外向き link も取得失敗。handshake 後に host dotenv と公開元ファイルを差替え・秘密を追加しても独立コピーは変化しない |
| 失敗時の動作                           | 不在 mount を注入すると隔離作成に失敗し、Nix/Codex は未起動。Nix の `throw` と shellHook の非0終了では Codex 未起動のまま隔離内診断が成功                             |
| Linux と WSL2                          | WSL2 で確認。通常 Linux は実行先がなく未確認。WSL2 の kernel 名を変えて代用しない                                                                                     |

保存した実測のコマンドは次のとおり。

```bash
python3 scripts/secret-isolation-probe.py --output /tmp/secret-isolation-270-reviewed-20260909
bats tests/secret-isolation.bats
```

実測ディレクトリには `report.json`、`launch.json`（実際の bubblewrap argv）、`closure.txt`、`store-copy.log`、`runtime.log` と `evidence/` の Codex JSONL／合成 provider request を残す。全てのログ・証跡を、親で作成したダミー秘密と合成 GitHub 認証値の sentinel に照合する。成功・失敗のどちらでも検査し、検出した値を保存ログで伏せ、端末への出力を停止して失敗する。意図的な生入力（fixture の `.env`、攻撃用 flake）と専用 store は証跡ログの走査対象に含めない。親側の証跡読取りも symlink／hardlink を受理しない。`fixture_result = "passed"` はこの合成 fixture の成功のみを表し、`production_ready` は常に `false` とする。

失敗経路は `--scenario isolation-failure`、`nix-failure`、`hook-failure`、`symlink-input`、`hardlink-input` で再現する（各回で別の新規 `--output` を指定）。`log-leak` と `log-leak-success` は、秘密の取得を伴わずダミー値を意図的に出力し、失敗時・成功時のログ検出器の感度を確認するケースである。初期化失敗時の診断は境界の再検査だけで、通常作業を未初期化環境に迂回させない。独立コピー後の追加・差替えを検証しており、コピー作業そのものに並行する書換えを安全に取り込めるとは保証しない。

`isolation-timeout`／`isolation-timeout-leak` は外側プロセスを2秒で停止し、途中の stdout／stderr を `runtime.log` に保存する。`codex-timeout` は合成 API の応答を遅延させ、実 Codex を5秒で停止する。Codex の stdout／stderr と provider の要求記録を保存してから失敗を返す。いずれも `report.json` に `timeout_stage` と `timeout_seconds` を残し、ログの秘密値検査を終えてから簡潔なエラーで終了する。通常実行の期限は外側180秒、Codex90秒のまま。タイムアウトも受入成功にはしない。

**初回記録時点では #270 は未完了として扱う。** 通常 Linux での同一コマンドの実測と、実サービスの最小認証・通信経路、実 worktree から秘密のない入力を選び成果を返す契約が残る。host network・HOME・control socket・worktree 全体を共有することで、この未確認を埋めない。#271 以降の本番移行を開始する根拠にはしない。

関連 Bats 4 件は成功し、Python 構文検査・`bunx tsc --noEmit` も成功した。`bun run test` の最終実行は **602 件中 594 成功・4 skip・4 失敗**だった（`/tmp/secret-isolation-270-full-tests-final.log`）。本 fixture の 4 件は全体実行でも成功。skip は既存の実 Nix テンプレート・with-env 等の opt-in 検証であり、本 fixture の実 Nix／Codex 検証を skip したものではない。

失敗は `tests/dogfood-to-issues.bats` の `dogfood without annotation`、`annotated dogfood`、`empty annotation`、`annotation attaches` の 4 件。次の単独再実行では現行コードの全 4 件が成功した。変更前 `0ebc984` の archive でもこれらを含む 5 件が成功している。一括実行での不安定さは未解消で、全体 suite が green とは報告しない。ブラウザーの原因修正は本タスクに含めていない。

```bash
bats --print-output-on-failure --filter 'dogfood without|annotated dogfood|empty annotation|annotation attaches' tests/dogfood-to-issues.bats
```

差分レビューでは Standards の命名改善 1 件と Spec のログ検査不足 2 件を指摘され、検査関数の改名、全ログの検査、合成認証値と漏洩注入テストの追加で対応した。再レビューのコード指摘は両軸とも 0 件。別エージェントによる `log-leak` の実行でも、標準出力・標準エラー・保存ログへの値の残存がないことを確認した。上記の要件未確認事項はこのレビュー結果とは別に残る。pre-commit の gitleaks／oxfmt、commit-msg の `cog verify` も成功した。

## PR #276 のレビュー対応（2026-09-10）

実ランタイムテストの依存不足と、タイムアウト時に診断を失う2件を修正した。Nix／Codex 等を含まない PATH の通常実行は1成功・4 skipとなり、`codex`・`gh`・`bwrap` を個別に除いた明示実行は、それぞれ不足ツール名を示して失敗する。タイムアウトの3ケースは実 bubblewrap／Codex を使い、途中ログ・期限・発生段階・秘密値の伏せ字と traceback 非出力を確認した。

`SECRET_ISOLATION_REAL_RUNTIME=1 bun run test` は **610件中606成功・4 skip・失敗0件**（`/tmp/review-276.6KQhnA/full-tests.log`）。本 fixture の5件は全て実行・成功し、skip は既存の実 Nix opt-in 検証4件。以前失敗した dogfood の4件も今回は全体実行で成功した。これは今回の実測結果であり、以前の不安定さの原因を解消したという主張ではない。Python構文検査も成功した。通常 Linux・実認証接続・実 worktree の入力と成果返却は引き続き未確認で、#270 の未完了扱いを維持する。

## #271 着手時の追加検証（2026-09-10）

#270 が merge 済みでも上記の未完了が明記されていたため、ユーザーの指示でその解消を今回の作業に含めた。本番入口を先に置き換えず、次の実行可能な証跡を追加した。

| 追加項目   | 結果と範囲                                                                                                                                                                                                                    |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 通常 Linux | QEMU/KVM の Linux 6.18.33、非 root uid 1000 で既存の統合 probe が成功。kernel 名を変えた代用ではない。                                                                                                                        |
| 実サービス | WSL2 の同じ隔離起動から Nix・shellHook、hosted model を使う実 Codex、子プロセスの edit/build/test/commit、実 gh の認証付き公開 GET、stdio MCP tool call、host worktree への同一 commit 返却が成功。                           |
| 入力と返却 | 明示した public HEAD/history とファイル hash のみを独立コピー。host 全体や Git metadata の共有を使わない。commit と stage/未 stage の区別、新規通常ファイル、次回起動の保持、host 競合の拒否を WSL2/通常 Linux の両方で確認。 |
| 依存取得   | WSL2 の外側隔離内で実 Nix が公開 cache を取得。固定 host:443・public DNS IP の gateway 経由で、別 domain・localhost・別 port を拒否。                                                                                         |

方式、入力契約、再現コマンド、結果と残る範囲は [worktree input/return](secret-isolation-worktree-270.md)、[Linux VM](secret-isolation-linux-vm-270.md)、[認証・通信](codex-isolation-connectivity-271.md) に記録した。使った runtime の版は上記の初回記録と同じである。

主な追加コマンドは以下。公開 CA の絶対パスは、信頼済み Nix `cacert` package の証明書 bundle を明示する。

```bash
SECRET_ISOLATION_REAL_RUNTIME=1 \
SECRET_ISOLATION_REAL_SERVICES=1 \
SECRET_ISOLATION_REAL_MODEL=1 \
SECRET_ISOLATION_REAL_DEPENDENCIES=1 \
SECRET_ISOLATION_CA_BUNDLE=/nix/store/SELECTED-cacert/etc/ssl/certs/ca-bundle.crt \
bats --print-output-on-failure tests/secret-isolation-worktree.bats

python3 scripts/secret-isolation-linux-vm.py --output /tmp/secret-isolation-linux-vm-270-result
```

追加検証の成功を #271 の実装完成とは扱わない。公開 `codex-worktree` への接続、既存 trust/permission/network/output、Git hooks、通常起動と失敗時の回帰は #271 の対象として残る。通常 Linux の実サービス認証、managed proxy と dependency gateway の重ね合わせ、GitHub push/PR と管理 MCP の利用者設定統合は上表の成功に含めない。既存合成 probe の `production_ready=false` は維持する。
