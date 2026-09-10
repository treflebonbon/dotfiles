---
type: research
title: 隔離 Codex の管理 MCP と GitHub 連携
description: Issue 272 の選択入力、権限、実接続、拒否検証と未確認事項。
tags: [codex, mcp, github, isolation]
timestamp: 2026-09-10
---

# 隔離 Codex の管理 MCP と GitHub 連携

[#272](https://github.com/treflebonbon/dotfiles/issues/272) と親仕様 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の検証記録。共通 raw 入口と、秘密なしの公開 snapshot・専用 Nix store・変更返却は #271 の実装を使う。

## 選択入力と認証の範囲

| 入力                           | 使用先と制限                                                                                                                                                                                    |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 管理 MCP の command/args       | `--mcp` で選んだ Context7・Serena の既存 managed stdio 契約だけ。一致しない env・URL・追加 command は登録を拒否する。未選択サーバーの認証値を含む設定もコピーしない。                           |
| bunx・Node・uvx の Nix closure | 個別にコピーし隔離内で起動する。bunx/uvx は argv[0] が意味を持つため最終 symlink の名前を保持する。ホストの package cache は使用しない。                                                        |
| GitHub policy JSON             | worktree 外で人間が所有。公開 repository、1 topic、default branch、確認した commit、CI/外部連携の条件と根拠を固定する。private repository は本実装の対象外。                                    |
| host gh の既存認証             | host gateway だけが使う。HOME・token・credential helper・制御 socket を隔離内へ渡さない。プロジェクトコードから送れる要求を metadata・対象 PR・検査済み topic push に制限する。                 |
| 公開 Git 履歴・bundle          | 新規 commit の全 `.github` tree を確認済み commit と比較する。専用 publisher は checkout や project hook を実行しない。既存 `git-push-topic` の default branch 拒否・非 force push を維持する。 |
| network                        | 既存 domain allowlist と公開 IP resolver を使い、明示 deny を優先する。GitHub は既存 proxy の内部 HTTP envelope だけを受け、host が実サービスへ HTTPS 接続する。                                |

追加 MCP・Codex plugin・クラウドの取得サービスを無検査で接続しない。`automation` の確認は人間が所有する宣言であり、自動スキャンによる外部サービス全体の安全証明ではない。管理者が後から変更する CI、GitHub App、runner の状態まではローカル snapshot で固定できない。実シークレットを使う連携は、人間が確認済みのコードを AI がアクセスできない別環境で実行する条件に合わせる。

この repo の追跡済み `.github/workflows/osv-scanner-{pr,full}.yml` は固定 revision の OSV reusable workflow を呼ぶ。プロジェクト secret の参照・`secrets: inherit`・environment 指定はない。GitHub 外の連携や他 repo の保証と区別する。

## 実装判断の根拠

Codex の stdio MCP は `command`・`args`・`env_vars` と required startup を提供する。[公式 MCP 設定](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Codex 0.153.4 の Linux proxy 用 seccomp は IP socket を許可し、AF_UNIX の新規接続を拒否する。実 gh の `http_unix_socket` はここで EPERM となったため採用しない。限定 CLI が既存 HTTP proxy を使い、host gateway の固定 GitHub 操作へ接続する。Unix socket の包括許可、host network 共有、TLS 検証無効化は使用していない。[固定版の実装](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/linux-sandbox/src/landlock.rs)

AI の変更を secret 付き CI へ渡す危険はローカルファイル拒否では解消しない。確認済み automation の固定と人間の実行条件を別に扱う。[GitHub の安全な workflow 利用](https://docs.github.com/en/actions/reference/security/secure-use)

## WSL2 の検証

Linux `6.18.33.2-microsoft-standard-WSL2`、Codex 0.153.4、Nix 2.34.6、gh 2.96.0、bubblewrap 0.11.2 で測定。Session Scratchpad は提示されていないため、一般の検証ログは `/tmp/codex-services-272/` を fallback に使用した。

| 検証                | 結果・証跡                                                                                                                                                                                      |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 管理 MCP 選択       | 実 `codex-worktree mcp list --json` で両サーバーを確認。未選択設定の dummy credential は出力されない。`tests/raw-codex-services.bats`。                                                         |
| 実 Context7・Serena | 共通入口 → Nix/shellHook → hosted model を使う Codex → 両 stdio MCP。Context7 の Python 文書参照と Serena による `greeting.py` の before→after 編集・ホスト返却が成功。`mcp-home-fixture.log`。 |
| 実 GitHub 接続      | 共通入口の Codex command sandbox から公開 repo metadata を取得。host の実 gh が認証を使用。Secrets・Actions ログ・`.env` contents・GraphQL・dispatch の試行は拒否。`real-github-verified.log`。 |
| topic push の境界   | 実 Git object/bundle を socket 経由で受信し、正常 commit は dummy publisher まで到達。`.github` 変更・不一致 HEAD は publisher 前に拒否。実 GitHub push とは区別する。                          |
| PR の境界           | dummy upstream で選択 branch/base の PR 作成を許可。別 branch/base、state 変更、余分な field は拒否。実 GitHub PR 作成とは区別する。                                                            |
| ネットワーク拒否    | 許可外 domain、private IP、明示 deny、他 port を拒否する既存 gateway 検証を維持。                                                                                                               |

`/tmp` 配下の MCP fixture では、Serena の編集に対する Codex の自動承認レビューが `.env` マスク作成時の read-only filesystem エラーで失敗した。実利用先と同じ home 配下の linked worktree では、同じ managed permission/approval 設定のまま成功した。拒否を bypass する設定は加えていない。secret deny の空マスクを `.env` として読める場合も、ホストの dummy 値が取得されないことと区別する。`/tmp` 配下の MCP 編集は対応済みとしない。

実 MCP の再現は、ホスト側の公開 fixture の置き場所を home 配下にする（namespace 内の HOME と TMPDIR は launcher が固定する）。

```bash
mkdir -p "$HOME/.local/state/codex-services-test"
TMPDIR="$HOME/.local/state/codex-services-test" \
  CODEX_ISOLATION_REAL_MCP=1 \
  CODEX_ISOLATION_CA_BUNDLE=/nix/store/SELECTED-cacert/etc/ssl/certs/ca-bundle.crt \
  bats --filter 'uses real managed' tests/raw-codex-services.bats

CODEX_ISOLATION_REAL_GITHUB=1 \
  CODEX_ISOLATION_CA_BUNDLE=/nix/store/SELECTED-cacert/etc/ssl/certs/ca-bundle.crt \
  bats --filter 'uses host gh' tests/raw-codex-services.bats
```

## 未確認と後続検証

実 GitHub topic push・PR の書込み、通常 Linux の今回の連携、全 suite と review の最終結果は作業中。外部連携が実シークレットを使用するかはユーザー確認待ち。上記 fixture・公開 GET だけでこれらが完成したとは扱わない。
