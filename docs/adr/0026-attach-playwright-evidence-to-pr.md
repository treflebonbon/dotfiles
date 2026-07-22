---
type: decision
title: to-pr の Playwright 証跡を GitHub の PR 添付として扱う
description: 代表画像を Git 履歴へ commit せず、PR の匿名化添付 URL と本文内レポートでレビュアーへ引き渡す
tags: [adr, skills, to-pr, playwright, github, evidence]
timestamp: 2026-07-22
status: accepted
---

# to-pr の Playwright 証跡を GitHub の PR 添付として扱う

## Context

`to-pr` は UI Acceptance Criteria を `playwright-cli` で検証し、Verification Matrix を PR 本文へ記録する。従来はスクリーンショットを残す場合、ユーザー確認後に画像を Git 履歴へ commit し、SHA 固定 URL を本文へ載せていた。しかし画像は実装成果物ではなくレビュー用の一時証跡であり、リポジトリ履歴へ永続化する必要がない。

GitHub の PR 編集欄へ画像を添付すると、アップロード時に匿名化 URL が生成される。この URL を PR 本文へ埋め込めば、画像を Git 管理せずレビューに利用できる。GitHub Artifacts はローカルで生成した証跡の直接アップロード経路ではなく、保持期間も限定されるため採用しない。

一方、すべての agent runtime が GitHub 認証済みブラウザを操作できるとは限らない。特に WSL2 から Windows Chrome のログイン状態を暗黙に流用すると、実行環境と認証境界が不明瞭になる。

## Decision

1. `to-pr` は UI AC 検証前に fresh な一時ディレクトリを作り、実行できた各 UI AC の代表画像を1枚ずつと `playwright-report.md` を生成する。実行できない UI AC は画像を捏造せず理由をレポートへ残す。レポートには操作、観測結果、URL、console/network エラー要約を記録し、認証情報や raw request は含めない。
2. PR 本文へ `## Playwright Evidence` を追加し、レポートのテキストと代表画像を AC ごとに対応づける。Verification Matrix は引き続き全 AC の検証状態を表す正本とする。
3. push、PR 作成、画像アップロードは、実行前に一度の確認でまとめて承認を得る。PR 作成後、現在の runtime が既存の GitHub 認証済みブラウザを操作できる場合だけ画像を編集欄へ添付し、得られた匿名化 URL を `gh pr edit --body-file` で本文へ反映する。
4. WSL2 では Windows Chrome の認証を利用可能と仮定しない。WSL2 内で動作する Chrome が既に GitHub 認証済みの場合だけ自動添付する。
5. ブラウザ未認証、操作不能、またはアップロード失敗時はログインを要求せず、PR 本文へ `手動添付待ち` と記録する。完了報告には証跡ディレクトリの絶対パスとファイル一覧を載せる。画像を Git commit する方式へはフォールバックしない。
6. GitHub Actions workflow は追加しない。Bats は skill の公開契約を静的に検証し、PR 作成、画像アップロード、ブラウザ認証を実行しない。
7. 本 ADR は ADR-0004 の画像 commit 方針を置き換える。ADR-0004 が定めた軽量方針、すなわち evidence JSON schema、verdict gate、必須 trace/video を持ち込まない判断は維持する。

## Consequences

- レビュアーは PR 本文だけで UI AC の観測内容と代表画像を確認でき、画像は Git 履歴を増やさない。
- 自動添付の成否は runtime の既存認証状態に依存するが、失敗時もローカル証跡の明示的な手動引き継ぎが残る。
- `to-pr` は認証を確立・保存せず、Windows と WSL2 のブラウザ境界も越えない。
- GitHub 側の添付 URL はリポジトリ内の SHA 固定 asset ではないため、証跡の可用性は GitHub の PR 添付機能に依存する。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [ADR-0016](0016-to-pr-shared-contract-vocabulary.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #97](https://github.com/treflebonbon/dotfiles/issues/97)
