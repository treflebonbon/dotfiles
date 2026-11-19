---
type: decision
title: Windows の Herdr App と WSL の Herdr TUI を併用する
description: TUI 本体を通常のシェルに供給し、作業を開始した側で task worktree を管理する
tags: [adr, herdr, runtime, worktree]
timestamp: 2026-11-19
status: accepted
---

# Windows の Herdr App と WSL の Herdr TUI を併用する

App 導入後も WSL の端末から作業を始められるように、Herdr TUI を併用する。ADR-0088 のうち、日常利用から TUI を外す判断を見直す。Windows の App と local core、WSL 側 core は公式配布・更新経路を使う。[ADR-0088](0088-migrate-herdr-tui-to-app.md)

- 現行の `llm-agents.nix` の固定 snapshot が供給する TUI 本体を、WSL の通常のシェルで `herdr` として利用できるようにする。復帰対象は本体と利用手順とする。
- App と TUI の双方から標準操作で task worktree を作成できるようにする。各タスクの Worktree Owner は作業を始めた側が担う。既存の checkout をもう一方で開いて作業を続ける場合は、その実行環境でエージェントを起動する。App と TUI はそれぞれのサーバーでエージェントを実行する。[Herdr 公式 FAQ](https://herdr.dev/#questions)
- 標準の端末・ペインと既存のエージェント起動手順を使う。新しい worktree で必要な環境変数は、どちらでも利用時に明示的に用意する。旧 `dotfiles.copy-env` の登録、`~/.herdr` の履歴と既存 worktree は保持する。2026-11-19 の確認では登録が有効で、参照先の manifest は存在しなかった。

## 受入条件

Windows と WSL2 で App と TUI を両方起動でき、WSL の新しい通常シェルから `herdr` が現行の固定版に解決することを確認する。ダミーのリポジトリを使って、両方の標準操作で新規 worktree を作成できることと、もう一方で既存の checkout を開けることを確認する。checkout の照合には作業ルート・branch・Git common dir を使う。既存の TUI データを保持した状態で、旧プラグイン登録の影響も確認する。
