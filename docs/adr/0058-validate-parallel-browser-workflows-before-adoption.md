---
type: decision
title: ブラウザ検証と PR 添付の並列化を実機検証してから採用する
description: Windows の worktree 別ブラウザと共有添付を第一候補とし、portless を検証用アプリで評価する
tags: [adr, wsl2, browser, worktree, playwright, portless]
timestamp: 2026-09-11
status: accepted
---

# ブラウザ検証と PR 添付の並列化を実機検証してから採用する

[#301](https://github.com/treflebonbon/dotfiles/issues/301) は、複数 worktree の UI 検証と異なる PR への画像添付を並列に進めるため、現行の単一所有者による排他利用を見直す。共有ブラウザでの添付並列化は当初未検証だったため、本実装の仕様確定に先行して実機検証を行った。独立 profile の分離・再起動後の保持と共有添付の並列動作は確認できたが、新構成の共存試験は残っている。この ADR が採用するのは調査方針であり、現行のブラウザ利用規則の変更ではない。

## Decision

- Worktree 検証ブラウザは Windows 側で分離する案を第一候補とする。WSL2 の browser-free 境界を維持し、profile・port・所有権・終了処理の分離を検証する。通常の UI 検証では worktree ごとにログイン状態を保持し、明示リセット時だけ初期化する。Dogfood の既存の一時 profile とは分ける。
- 共有添付ブラウザは、専用ブラウザで手動確立済みの GitHub 認証を利用する。PR ごとのタブ操作と同一 PR の本文更新競合を検証し、異なる PR の添付を全体の待ち行列で直列化しない。通常閲覧用 profile の流用や認証情報のコピーは行わない。
- 共有添付の成立を確認してから本実装の仕様を確定する。不成立または必要な実機条件が不足する場合は、結果と未確認項目を残して設計へ戻す。
- バックグラウンドの検証・添付は、人間が操作中のウィンドウのフォーカスとカーソルを奪わないことを受入条件にする。headless と CDP を基本にし、OS の入力操作やウィンドウ・タブの前面化を行わない。手動認証や Dashboard のための headed 表示をバックグラウンド処理から自動で開始しない。実機では起動・接続・操作・撮影・終了時の前面ウィンドウとカーソル位置を観測し、人間の操作による変化と識別できない結果は未確認として扱う。
- portless は今回の適合性調査に含め、まず検証用アプリで PORT・proxy・HMR・Windows ブラウザからの到達性を評価する。実アプリの OAuth 動作は今回の必須検証に含めず、callback allowlist・公開 URL・名前解決・TLS の整合を各アプリの導入条件として記録する。検証用 callback の成功を外部 provider への適合の証明にはしない。

## 共存範囲の合意（Q6）

異なる browser identity の worktree 検証・共有添付・Dogfood は並列利用を目指す。Dashboard は対象の検証ブラウザに属し、同じ browser identity への headless / headed の競合要求は既存 consumer を保持して拒否する。同じ worktree に Dashboard 専用の追加 browser identity は導入しない。異なる worktree の Dashboard と headless 検証は並列利用の対象とする。背景処理からの headed 自動起動は引き続き行わない。

現行の全体排他では新構成の共存は試験できない。Q8 の合意により、共存は本実装の必須受入試験へ移す。先行検証で成立した独立 profile と共有添付を根拠に実装契約を確定するが、共存試験が通るまで実装完了とはしない。

## portless の今回の採否

標準配布・必須依存への採用は今回行わない。検証用アプリで HTTP の PORT・URL・HMR・proxy は成立したが、名称衝突と Windows TLS の準備が残る。任意導入の候補は維持し、アプリごとの公開 URL・callback・名前解決・TLS の条件を引き継ぐ。

## Consequences

Windows 側の分離を第一候補とすることで、WSL2 内ブラウザの再導入を前提にせず並列化を検討できる。ログイン状態の保持に伴い、worktree の識別と明示リセットの対象を曖昧にしないことが必要になる。共有添付のタブ所有権は共有 context の認証・storage を分離しない。

portless は dev server の URL とポートの整合を担う候補であり、ブラウザ所有権や GitHub 添付認証の解決とは分けて採否を記録する。初回認証と期限切れ対応は引き続き to-pr 外のセットアップとして扱う。

現行の [ADR-0031](0031-managed-playwright-chrome-on-wsl2.md)、[ADR-0038](0038-keep-wsl2-browser-free.md)、[ADR-0047](0047-centralize-managed-chrome-ownership.md) は、この調査方針だけでは置き換えない。検証結果を受けた本実装の設計で、変更する同時利用・所有権・Dashboard の契約を明示する。
