---
type: decision
title: PR review 対応を Review Round として自動完結する
description: 選択した review thread 群を gh CLI で修正・公開・日本語返信・resolve まで処理し、安全境界を専用 CLI と公開済み commit の検証で保つ
tags: [adr, github, review, skills, automation]
timestamp: 2026-07-31
status: accepted
---

# PR review 対応を Review Round として自動完結する

## Context

外部 `gh-address-comments` skill は GitHub plugin で PR metadata と patch を読み、thread state だけを `gh api graphql` で取得する一方、明示依頼がなければ返信も resolve もしない。このため「review コメントを修正する」という依頼を完了しても、返信と resolve を行わず open thread が残っていた。plugin の flat な comment surface は thread ID、返信関係、`isResolved` を保持しないため、書込みまで自動化すると read/write の正本も分かれる。

## Decision

1. 選択した unresolved review thread 群を **Review Round** と呼び、review 対応依頼は修正・検証・1つの Conventional Commit・`git-push-topic`・日本語返信・resolve までの承認を含む。説明のみの round は空 commit を作らない。
2. `gh-address-comments` では GitHub plugin を使わず、thread-aware な read/write を専用 CLI `gh-review-thread` に統一する。GitHub plugin 自体は他用途のため有効のまま残す。
3. コード修正を含む thread は、修正 commit が現在の PR commit 履歴に含まれることを確認してから返信・resolve する。PR head が先へ進んでいても履歴に含まれていれば公開済みとする。
4. 返信には修正または回答の要約と検証結果を日本語で記載する。同一本文を認証ユーザーが既に投稿済みなら再投稿せず、未完了の resolve から冪等に再開する。
5. 返信成功後だけ resolve する。thread 単位の失敗は残りを止めず、曖昧・見送り・検証失敗・未公開・権限/API 失敗の thread は open のまま理由を報告する。
6. Codex は汎用 `gh api graphql` を無確認で許可せず、引数と GraphQL operation を固定した `gh-review-thread` だけを execpolicy で許可する。

## Consequences

- review 対応は修正の公開と thread state の整合まで一度の依頼で完結する。
- thread-aware な GitHub 操作の経路が1つになり、plugin と GraphQL の表現差を扱わなくてよい。
- resolve の自動化範囲は対応済み thread に限定され、PR merge/close や汎用 GraphQL mutation の承認境界は変わらない。

関連: [ADR-0023](0023-resolve-external-skill-contracts-locally.md) / [ADR-0030](0030-preauthorize-routine-github-writes.md) / [skill-harness](../../runtime/skill-harness.md)
