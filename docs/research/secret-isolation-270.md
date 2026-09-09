---
type: research
title: 専用 Nix store と実 Codex の隔離起動検証
description: Issue 270 の合成 fixture、公開する入力、検証結果と本番移行前の未確認事項。
tags: [research, nix, codex, sandbox, secrets]
timestamp: 2026-09-09
---

# 専用 Nix store と実 Codex の隔離起動検証

対象は [#270](https://github.com/treflebonbon/dotfiles/issues/270)、親仕様は [#268](https://github.com/treflebonbon/dotfiles/issues/268)。検証コードは [起動 script](../../scripts/secret-isolation-probe.py) と [合成連携](../../tests/fixtures/secret-isolation/runtime.py)、自動検証の入口は [Bats](../../tests/secret-isolation.bats)。本番の `codex-worktree`、Herdr、配備済み設定は変更しない。

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
bats tests/secret-isolation.bats
```

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

**#270 は未完了として扱う。** 通常 Linux での同一コマンドの実測と、実サービスの最小認証・通信経路、実 worktree から秘密のない入力を選び成果を返す契約が残る。host network・HOME・control socket・worktree 全体を共有することで、この未確認を埋めない。#271 以降の本番移行を開始する根拠にはしない。

関連 Bats 4 件は成功し、Python 構文検査・`bunx tsc --noEmit` も成功した。`bun run test` の最終実行は **602 件中 594 成功・4 skip・4 失敗**だった（`/tmp/secret-isolation-270-full-tests-final.log`）。本 fixture の 4 件は全体実行でも成功。skip は既存の実 Nix テンプレート・with-env 等の opt-in 検証であり、本 fixture の実 Nix／Codex 検証を skip したものではない。

失敗は `tests/dogfood-to-issues.bats` の `dogfood without annotation`、`annotated dogfood`、`empty annotation`、`annotation attaches` の 4 件。次の単独再実行では現行コードの全 4 件が成功した。変更前 `0ebc984` の archive でもこれらを含む 5 件が成功している。一括実行での不安定さは未解消で、全体 suite が green とは報告しない。ブラウザーの原因修正は本タスクに含めていない。

```bash
bats --print-output-on-failure --filter 'dogfood without|annotated dogfood|empty annotation|annotation attaches' tests/dogfood-to-issues.bats
```

差分レビューでは Standards の命名改善 1 件と Spec のログ検査不足 2 件を指摘され、検査関数の改名、全ログの検査、合成認証値と漏洩注入テストの追加で対応した。再レビューのコード指摘は両軸とも 0 件。別エージェントによる `log-leak` の実行でも、標準出力・標準エラー・保存ログへの値の残存がないことを確認した。上記の要件未確認事項はこのレビュー結果とは別に残る。pre-commit の gitleaks／oxfmt、commit-msg の `cog verify` も成功した。
