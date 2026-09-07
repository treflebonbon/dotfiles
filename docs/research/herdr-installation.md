---
type: research
title: Herdr の Nix 導入
description: Issue #233 で合意した Herdr の導入範囲、公式 source flake による配布方式、受入条件。
tags: [research, herdr, nix]
timestamp: 2026-09-08
---

# Herdr の Nix 導入

[Issue #233](https://github.com/treflebonbon/dotfiles/issues/233) の確定済み設計と実装検証の記録。2026-09-08 に導入範囲（Q1）、配布方式（Q2）、受入条件を含む設計全体（Q3）についてユーザーの合意を得た。未決定の設計事項はなく、`grill-with-docs` は完了。

同日の `to-spec` で、合意内容を20件の User Stories と8項目の Acceptance Criteria に整理して Issue #233 の本文へ公開し、`ready-for-agent` を付与した。実装の Contract は Issue 本文を正本とし、このメモは調査根拠と設計時の判断を記録する。

続く `to-tickets` では、導入・対話利用・再接続検証・利用案内を1件で完結させる粒度について承認を得て、[実装 ticket #238](https://github.com/treflebonbon/dotfiles/issues/238) を `ready-for-agent` 付きで公開した。親 #233 の AC1〜AC8 をすべて担当し、blocker はない。GitHub native sub-issue 関係を親子の両側から確認済みで、親の本文・タイトル・ラベル・open 状態は維持した。

## 合意済みの範囲

日常のシェルから `herdr` を手動起動して使い始められる状態を完了範囲とする。ユーザー環境用 devShell への追加、起動確認、最小限の利用案内を含める（Q1: ユーザーが推奨案を選択）。

Codex / Claude の復元用 integration、Herdr 操作用 Agent Skill、ログイン時の自動起動は今回の対象に含めない。Herdr 自身が手動起動時に作る background session は通常動作として扱う。

## 確認済みの前提

- 公式の [`herdr` 起動手順](https://herdr.dev/docs/quick-start/) は default background session を起動または attach する。detach 後も pane のプロセスは動作を続ける。
- 2026-09-08 に GitHub API で確認した最新 stable は [`v0.8.2`](https://github.com/herdrdev/herdr/releases/tag/v0.8.2)（2026-08-19 公開）。初回採用版として合意し、下記の host ビルド・起動検証もこの版で行った。
- [公式 Nix 手順](https://herdr.dev/docs/install/#install-with-nix) は source flake を提供し、通常利用には release tag の固定を推奨する。Nix 管理の導入は Nix 経由で更新する。
- [`v0.8.2` の flake](https://github.com/herdrdev/herdr/blob/v0.8.2/flake.nix) は `packages.<system>.herdr` を公開し、この repo の既存対象である `x86_64-linux`、`aarch64-linux`、`aarch64-darwin` を含む。
- [上流の Nix package](https://github.com/herdrdev/herdr/blob/v0.8.2/nix/package.nix) は Rust / Zig と vendored libghostty-vt を使ってビルドする。上流の Nix check は build-only のため、手動利用の受入確認には別途起動検証が必要。
- [任意の integration](https://herdr.dev/docs/integrations/) は agent の復元用 hook を設定する。Codex / Claude の既存管理設定に関わるため、本体導入とは別の設計対象となる。
- この repo の導入先は [ユーザー環境用 flake](../../private_dot_config/nix-devshell/flake.nix)。配備と更新は [Architecture](../architecture.md) の task worktree / live source の境界に従う。

## 採用する導入・更新方式

公式 source flake の安定版タグと lock を固定する（Q2: ユーザーが推奨案を選択）。上流のビルド定義を利用し、初回・更新時のソースビルドと依存取得の負担を受け入れる。

- 初回採用版は調査済みの `v0.8.2`。ユーザー環境用 `flake.nix` に `herdr.url = "github:herdrdev/herdr/v0.8.2"` を追加し、対応する `flake.lock` で revision と依存を固定する。
- `modules/ai.nix` の package 集合に `inputs.herdr.packages.${system}.herdr` を追加する。Herdr は上流自身の依存定義で評価し、ユーザー環境の nixpkgs へ強制的に合わせない。
- `default` / `wsl` の両方へ供給し、既存対象の3 system を維持する。設定ファイルは追加せず、まず上流の既定設定で手動利用する。
- 更新時は新しい stable tag へ input を変更し、Herdr の lock と環境を更新・検証する。タグ固定のため、lock の更新だけでは別 release へ進まない。running session の再起動は、利用者が作業を終えたタイミングで行う（[公式更新手順](https://herdr.dev/docs/install/#update)）。

比較した公式 release binary の自前 packaging は、ソースビルドを省ける一方で各 system の配布物・ハッシュ・実行時依存を repo 側で管理する方式であり、今回は採用しない。

## 受入条件

以下は Q3 で合意した受入条件。実施結果は末尾の Verification Matrix に記録する。

- 既存の3 system と `default` / `wsl` の devShell で Nix 定義が評価できる。
- 実行可能な host で package をビルドし、`herdr` の version/help、対話起動、detach / reattach を確認する。他 system の評価と実機検証は区別して記録する。
- 起動確認は隔離した設定・状態で行い、普段の session に影響させない。
- 利用案内に、手動起動、detach / reattach、Nix 経由の更新と running session の再起動方法を含める。
- 関連する既存チェックを通し、source の変更を検証する。home への反映は受入後に live source から行う。

## 実装時の入口

- [ユーザー環境用 flake](../../private_dot_config/nix-devshell/flake.nix) と [lock](../../private_dot_config/nix-devshell/flake.lock): Herdr input と依存の固定。
- [AI module](../../private_dot_config/nix-devshell/modules/ai.nix): `herdr` の供給。
- [AI runtimes](../../runtime/ai-runtimes.md): 導入後の最小利用案内と更新方法。
- [nix-devshell tests](../../tests/nix-devshell.bats): 既存構成との整合確認。Nix 評価と host 上の起動検証を併用し、package 名の文字列検査だけで利用可能とは判定しない。

## 実装・検証記録（2026-09-08）

Herdr input は `v0.8.2` / revision `9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c` に固定した。既存の lock node 名は Nix により採番し直されたが、追加した Herdr・その nixpkgs・rust-overlay 以外の全 locked source は実装前と一致する。共通 nixpkgs、llm-agents、APM の pin は維持した。

### Verification Matrix

| AC                    | 方法・結果                                                                                                                                                                                        | 制約・証跡                                                                                         |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| AC1 再現可能な配布    | 公式 tag / revision / narHash と system 別 package の追加を確認。既存 lock source の不変性を比較して確認                                                                                          | ユーザー環境用 flake / lock と `modules/ai.nix`                                                    |
| AC2 対応環境          | `tests/herdr.bats` で全6出力の実 package の version と store path を評価。同一 system の default / wsl が同じ Herdr 0.8.2 を返すことを確認                                                        | `nix flake check --no-build --all-systems ./private_dot_config/nix-devshell` も成功                |
| AC3 host での利用開始 | x86_64-linux の package をビルドし、default / wsl の各 `nix develop` 内で `--version` / `--help` 成功。同じ `/nix/store/n4fsjxkynb3r11yypfmz5hwnrhfqgrf2-herdr-0.8.2/bin/herdr` を解決            | `/tmp/herdr-238-build-final.log`、`/tmp/herdr-238-default-cli.log`、下記 TUI 証跡                  |
| AC4 対話利用と再接続  | 設定ファイルを用意せずに TUI 起動。pane `w1:p1` で `sleep 300` を開始し、`Ctrl-b` → `q` で detach。server の稼働を確認し、再起動した client で同じ pane と PID に戻り、`kill -0` で処理継続を確認 | `/tmp/h238.oQTvts/probe2/` の画面 capture、`server-detached.json`、`pane-after.txt`、`result.json` |
| AC5 手動利用の範囲    | 管理設定・integration・skill・自動起動の追加なし。HOME / XDG の設定・状態・データ・cache・runtime と socket を一時領域へ隔離し、検証後はその server と端末を停止                                  | `nix develop` 自体の shellHook も一時 HOME で実行。通常セッションは利用していない                  |
| AC6 利用・更新案内    | `runtime/ai-runtimes.md` に起動・再接続・stable tag と lock の変更・再ビルドと検証・作業終了後の server 再起動を記載                                                                              | Nix 経由の更新と、lock 更新のみでは release が変わらないことを明記                                 |
| AC7 検証記録          | 関連 Bats 35件、新規 Herdr 評価テスト、Nix format、ShellCheck / shfmt、TypeScript typecheck が成功                                                                                                | `env -u FORCE_COLOR bun run test` は全517件成功（`/tmp/herdr-238-full-suite.log`）                 |
| AC8 配備境界          | linked task worktree `herdr-2` の source で編集・検証                                                                                                                                             | task worktree からの `chezmoi apply` は未実施。受入後の live source からの配備は既存運用に委ねる   |

| system         | default / wsl の評価           | native build・起動                                                         |
| -------------- | ------------------------------ | -------------------------------------------------------------------------- |
| x86_64-linux   | 両方成功、0.8.2 / 同一 package | build 成功、両 shell で CLI 成功、wsl shell で TUI・detach / reattach 成功 |
| aarch64-linux  | 両方成功、0.8.2 / 同一 package | 未確認（実行可能な実機なし）                                               |
| aarch64-darwin | 両方成功、0.8.2 / 同一 package | 未確認（実行可能な実機なし）                                               |

host build では crates.io API が `serial2 0.2.34`、`jsonc-parser 0.33.1` の取得に HTTP 403 を返した。同じ公式 CDN `static.crates.io` から、これらと未取得だった `wmi 0.18.4` を上流 derivation の既定ハッシュを指定した `nix store prefetch-file` で取得し、同じ fixed-output store path を満たした後にビルドが成功した。package 定義・lock・ハッシュの変更はしていない。空の cache から同じ API 経路だけで完走することは、この host では確認できていない。

一時領域のログはローカル検証証跡であり、恒久的な成果物ではない。Herdr の内部テストは再実装せず、dotfiles が供給する実 package の評価と利用開始の境界を検証した。
