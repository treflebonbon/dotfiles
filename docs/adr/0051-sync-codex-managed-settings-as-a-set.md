---
type: decision
title: Codex 管理設定をまとめて同期する
description: 種類別の配備入口を統合し、設定変更時に管理設定全体を同期する設計
tags: [adr, codex, chezmoi, deployment]
timestamp: 2026-09-07
status: accepted
---

# Codex 管理設定をまとめて同期する

同期 module は既に配備先の選択、設定のマージ、ファイルの置換を所有している。一方、chezmoi の5本の入口が設定種別ごとの変更検知と同期対象の選択を担う。入口を1本に統合し、AGENTS・config・environment・hooks・rules のいずれか、または同期処理の変更時に Codex 管理設定全体を同期する。

この interface により、呼出し側が同期対象を選ぶ知識を減らし、変更検知の locality を高める。AGENTS だけの変更でも config の再マージと他の管理ファイルの置換が発生する更新粒度を受け入れる。config の managed 値を優先するマージ、利用環境固有の信頼設定・状態の保持、他4種類の管理ファイルの置換は既存の扱いを引き継ぐ。

## 反映と復旧

全配備先の出力を先に生成・検証し、すべて成功してから既存ファイルを置換する。管理ソースの欠落・読取り失敗、既存 config の不正な TOML、マージや出力生成の失敗では、既存の管理ファイルを置換しない。これにより、後段の配備先の設定不正を検出する前に前段だけが更新されるケースを防ぐ。

反映は既存どおりファイルごとに原子的に行う。反映中の障害では非ゼロで停止し、成功済みの更新は残す。エラーは失敗した配備先・ファイルと処理段階を特定できるものとし、原因修正後に全体同期を再実行して揃える。全配備先を旧状態へ戻す rollback は保証しない。

## 同期の契機

chezmoi の `run_onchange` を維持する。管理ソースまたは同期処理の変更時に実行し、失敗した同期は次回 apply で再試行する。配備先の手編集や `CODEX_HOME` の変更だけでは自動再同期せず、修復・新しい配備先への同期が必要な場合は同期コマンドを明示実行する。

### 2026-11-23 の追記 — WSL の CLI と Desktop で標準ホームを使う

当初は Windows Desktop の WSL 起動を検出するログインシェルが `CODEX_HOME=~/.codex-app` を設定し、初回ログイン時に同期した。Windows 版 26.1117.4957.0 が起動した WSL の app-server では `CODEX_HOME` の上書きがなく、`~/.codex` のデータベースを開いていた。2026-11-21 の Desktop セッションも `~/.codex/sessions` に保存された。[Codex の設定と状態の保存先](https://learn.chatgpt.com/docs/config-file/config-advanced#config-and-state-locations)

WSL の CLI と Desktop は標準の `~/.codex` を使う。ログインシェルの Desktop 専用振り分けと初回同期、専用の同期済みマーカーを廃止する。管理設定・スキルの同期と旧スキルの撤去は、標準ホームと、利用者が明示した `CODEX_HOME` を対象とする。旧 `~/.codex-app` はディレクトリがあるだけでは対象に加えない。Windows ネイティブの Desktop は [Windows 側の標準ホーム](https://learn.chatgpt.com/docs/windows/windows-app#share-config-auth-and-sessions-with-wsl) を使う。

旧ホームの既存ファイルは保持する。旧 `auth.json` は残っているため、日常用プロファイルでの読み取り拒否を維持する。旧ホームの自動利用廃止は、日常用の権限プロファイルを既定に切り替える PR #620 から独立して公開する。

## 検証方針

検証は同期 module の interface と、隔離した chezmoi source・HOME・persistent state を通す。種類別の入口に結び付いたテストは、新しい入口へ移して既存の保持・移行契約を検証する。

| 確認する契約 | 検証方法 |
| --- | --- |
| 1つの入口から5種類を同期する | 各管理ソースと同期処理の変更を個別に与え、1回の同期で全対象が揃うことを確認する |
| 配備先と保持対象 | 標準ホームと明示 `CODEX_HOME` への反映を確認する。明示指定がない状態で旧 `~/.codex-app` が存在しても、管理同期・スキル同期・旧スキルの撤去で既存ファイルが変化しないことを確認する。信頼設定・実行状態の保持と既存の managed 設定移行も検証する |
| 事前検証の失敗 | 後段の配備先に不正な config、または管理ソースの欠落を与え、どの既存管理ファイルも置換されないことを確認する |
| 反映中の失敗と復旧 | 書込み失敗を与え、非ゼロ終了・ファイル単位の保全・失敗箇所の診断・修復後の全体同期を確認する |
| 変更時同期 | 成功後の同じ apply は再同期せず、失敗後の apply は再試行する。配備先だけの変更は残り、明示同期で揃うことを確認する |
| Desktop 起動 | WSL の新規 Desktop セッションと CLI セッションで、標準ホームの管理設定が適用されることを確認する。旧 Desktop の識別値が渡されたログインでも、専用ホームの作成や初回同期が起きないことを確認する |

隔離した WSL HOME に異なる設定を持つ2つのホームを置き、Codex 0.170.0 の CLI と、旧 Desktop の識別値を渡して候補のログイン設定を読み込んだ app-server の両方が `~/.codex` の設定を使うことを確認した。候補配備後の Windows Desktop の新規セッションは受入時に確認する。

## Interface

`sync-codex-managed-config` は引数なしで全体を同期する。chezmoi の変更時同期と手動修復は同じ入口で、事前検証と復旧の処理を共有する。

種類別引数と `all` 引数は受け付けず、使用方法を示して設定を変更せずに終了する。

関連: [CONTEXT.md](https://github.com/treflebonbon/dotfiles/blob/8ffc5653a35f345ed0f0c754ca66276b89987c42/CONTEXT.md) / [ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md)
