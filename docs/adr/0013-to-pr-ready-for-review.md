---
type: decision
title: to-pr の draft PR 作成を廃止し ready-for-review に変更する（ADR-0004 を amend）
description: to-pr が作成する PR を、ブラウザ検証結果に関わらず常に ready-for-review にする。draft PR は人間のレビュー開始を遅らせるため
tags: [adr, skills, to-pr, chezmoi]
timestamp: 2026-07-07
---

# to-pr の draft PR 作成を廃止し ready-for-review に変更する（ADR-0004 を amend）

## Status

Accepted (2026-07-07)

## Context

[ADR-0004](0004-fill-mattpocock-gaps.md) は `to-pr` の決定事項として「非UI なら検証を skip して draft PR を開く」を定めた。しかし draft PR は GitHub 上で「レビュー可能」というシグナルを発しない。`to-pr` は実装完了後の公開ステップとして呼ばれるにもかかわらず、生成された PR が draft のままだと、人間のレビュアーは毎回手動で Ready for review に切り替えるという一手間を強いられ、レビュー開始が遅れる。

ブラウザ検証ラベル（確認済み/未確認/要人間確認/対象外(非UI)）はすでに PR 本文に記載され、レビュアーへ検証状況を正直に伝える手段として機能している。draft 状態という追加シグナルは、この伝達手段と役割が重複したうえでレビュー開始を遅らせるだけだった。

## Decision

- `to-pr` はブラウザ検証結果や AC の確認状況に関わらず、無条件で `gh pr create`（`--draft` フラグなし）を実行し、常に ready-for-review な PR を作成する。検証ラベルによる draft/ready の条件分岐は導入しない。
- ブラウザ検証ラベル（確認済み/未確認/要人間確認/対象外(非UI)）と `Fixes #N` による issue 自動クローズの参照は変更しない。
- `to-pr` の挙動を説明している周辺ドキュメント（CLAUDE.md / AGENTS.md / runtime/skill-harness.md）の「draft PR」表記も、実際の挙動に合わせて更新する。

## Consequences

- レビュアーは PR を確認する前に "Ready for review" へ手動で切り替える一手間が不要になる。
- ブラウザ検証の未完了/不確実性は、draft 状態ではなく PR 本文のラベルのみで伝達される。
- Claude Code 本体の background-agent が worktree 完了時に自動で開く draft PR（[ai-runtimes](../../runtime/ai-runtimes.md) 参照）とは別機能であり、本 ADR の対象外。二重 PR の懸念は引き続き該当するが、その対応は本 ADR の範囲外。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md)（本 ADR が amend）
