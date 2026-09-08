---
type: research
title: Herdr の Nix 導入
description: Issue #233・#238 の llm-agents 経由の Herdr 導入方針と検証記録。
tags: [research, herdr, nix, llm-agents]
timestamp: 2026-09-08
---

# Herdr の Nix 導入

仕様の正本は [親 Issue #233](https://github.com/treflebonbon/dotfiles/issues/233)、実装 ticket は [#238](https://github.com/treflebonbon/dotfiles/issues/238)、成果物は [PR #239](https://github.com/treflebonbon/dotfiles/pull/239)。Herdr 0.8.2 を既定設定で手動起動し、pane 内の処理を保持して detach / reattach できる状態までを扱う。

2026-09-08 の Q1・Q3 で合意した利用範囲と受入条件を維持する。Q2 では当初、公式 source flake の直接導入を選んだが、既存 `llm-agents` snapshot に同版が収録済みという比較が不足していた。再確認後のユーザーの「Issue、コード、PR修正」に基づき、配布方式を既存 `llm-agents` の direct package へ変更し、親子 Issue の仕様も更新した。

## 採用する配布・更新方式

- 初回採用版は `v0.8.2`。既存の `llm-agents.nix` snapshot `896d09ccef580902e01e716e6f4646421087c252` と lock をそのまま利用する。[収録済み package 定義](https://github.com/numtide/llm-agents.nix/blob/896d09ccef580902e01e716e6f4646421087c252/packages/herdr/package.nix)は Herdr 公式 tag と source hash、Cargo / Zig の依存 hash を固定している。
- `modules/ai.nix` で `inputs.llm-agents.packages.${system}.herdr` を直接参照する。同じ snapshot の Numtide cache と derivation を揃えるため、共通 nixpkgs 上で再評価する shared overlay の経路は使わない。
- Herdr 専用 input と、その nixpkgs・rust-overlay は不要。ユーザー環境用 `flake.nix` / `flake.lock` は導入前の base `6e91e3f` と一致し、共通 nixpkgs、既存 AI ツールの snapshot、APM pin は更新しない。
- `default` / `wsl` の両方、既存3 system へ供給する。設定ファイル・復元用 integration・追加 skill・自動起動を dotfiles から追加しない。package 内の integration 素材の同梱は有効化を意味しない。
- 将来の更新は `llm-agents` の採用 revision と lock を変更し、同じ snapshot の他 AI ツールの変更も既存の採用手順で検証する。revision 固定のため、lock 更新だけでは別 snapshot の release へ進まない。Herdr の採用版を変える場合はテストの期待版も更新する。

この方式は既存の配布・cache 経路を使い、追加 input と独自 packaging の保守を省ける。一方、package 定義と更新時期は `llm-agents` に従い、cache が利用できない場合は Rust / Zig のソースビルドが必要になる。手動起動・更新・作業終了後の server 再起動は [利用案内](../../runtime/ai-runtimes.md#herdr-の手動利用)にまとめる。

## 検証記録（llm-agents への切り替え後）

検証日は 2026-09-08。以下は採用する direct package を使った結果であり、旧方式の起動検証を流用していない。host は x86_64-linux。`nix build` は Numtide cache から Herdr と必要な依存を取得して成功し、Herdr のローカルソースビルドは行っていない。

| AC                    | 方法・結果                                                                                                                                                                                                                            | 証跡・未確認理由                                                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| AC1 再現可能な配布    | 既存 snapshot の direct package を追加。ユーザー flake / lock が導入前 base と一致し、共通 nixpkgs・既存 AI ツール・APM pin が不変であることを確認                                                                                    | source 差分と固定 snapshot の package 定義                                                                                                   |
| AC2 対応環境          | `tests/herdr.bats` で全6出力の version / store path を評価し、各 shell が同じ snapshot の direct package 0.8.2 を返すことを確認。切り替え前に red、切り替え後に green。全 system の `nix flake check --no-build --all-systems` も成功 | `/tmp/h238-llm.x550bn/tdd-red.log`、`tdd-green.log`、`flake-check.log`                                                                       |
| AC3 host での利用開始 | cache から package を実体化し、default / wsl の各 `nix develop` から version/help 成功。両方が `/nix/store/3p3h77wn2igs4xhvp49ki3w72mpis4q8-herdr-0.8.2/bin/herdr` を解決                                                             | 同一検証ディレクトリの `build.log`、`build.out`、`default-cli.log`、`smoke.log`。ソースビルドは未実施                                        |
| AC4 対話利用と再接続  | 隔離 TUI の pane `w1:p1` で `sleep 300` を開始。`Ctrl-b` → `q` で detach 後も server が稼働し、reattach 後の同じ pane で PID `3483899` に対する `kill -0` が成功                                                                      | `probe/result.json`、`probe/server-detached.json`、`probe/pane-after.txt`、画面 capture                                                      |
| AC5 手動利用の範囲    | 管理設定・integration・skill・自動起動の追加なし。HOME / XDG の設定・状態・data・cache・runtime と socket を一時領域へ分離し、検証用 server と端末を停止                                                                              | `nix develop` の shellHook も一時 HOME。通常セッションは利用していない                                                                       |
| AC6 利用・更新案内    | `runtime/ai-runtimes.md` に起動・再接続・snapshot revision と lock の更新・他 AI ツールの確認・package 取得またはビルド・作業終了後の server 再起動を記載                                                                             | Nix で更新し、lock のみでは別 snapshot の release にならないことも明記                                                                       |
| AC7 検証記録          | Herdr 評価テスト、全 system の flake check、Nix format、ShellCheck / shfmt、TypeScript typecheck が成功                                                                                                                               | `env -u FORCE_COLOR bun run test` は全517件成功（`/tmp/h238-llm.x550bn/full-suite.log`）。関連する既存 devShell / quality floor の35件も含む |
| AC8 配備境界          | linked task worktree `herdr-2` の source で編集・検証。task worktree からの live HOME への apply は未実施                                                                                                                             | 受入後の live source からの配備は既存運用に委ねる                                                                                            |

| system         | devShell | package 評価                                      | native 実体化・起動                                               |
| -------------- | -------- | ------------------------------------------------- | ----------------------------------------------------------------- |
| x86_64-linux   | default  | 0.8.2、同 system の wsl と同じ direct package     | cache 取得・version/help 成功。TUI は wsl 側で同一 package を検証 |
| x86_64-linux   | wsl      | 0.8.2、同 system の default と同じ direct package | cache 取得・version/help・TUI・detach / reattach 成功             |
| aarch64-linux  | default  | 0.8.2、同 system の wsl と同じ direct package     | 未確認（実機なし）                                                |
| aarch64-linux  | wsl      | 0.8.2、同 system の default と同じ direct package | 未確認（実機なし）                                                |
| aarch64-darwin | default  | 0.8.2、同 system の wsl と同じ direct package     | 未確認（実機なし）                                                |
| aarch64-darwin | wsl      | 0.8.2、同 system の default と同じ direct package | 未確認（実機なし）                                                |

3 system の direct package は `nix path-info --store https://cache.numtide.com` で cache に存在することも確認した。ARM の cache 確認は実機での利用検証を代替しない。一時領域のログはローカル証跡であり、恒久的な成果物ではない。

## 関連ファイル

- [AI module](../../private_dot_config/nix-devshell/modules/ai.nix)：direct package の供給。
- [Herdr の Bats テスト](../../tests/herdr.bats)：全6出力で採用版と供給元を確認。
- [Architecture](../architecture.md)：shared overlay と direct package の使い分け。
- [公式 Quick start](https://herdr.dev/docs/quick-start/)：手動起動と再接続の操作。
