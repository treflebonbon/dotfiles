---
type: decision
title: agent 知識を OKF バンドルで表現
description: upstream の知識グラフ (CEG frontmatter / wiki-sync) を廃し docs を OKF バンドルに再記述
tags: [adr, okf, knowledge, docs]
timestamp: 2026-07-02
---

# agent 知識を OKF バンドルで表現

## Status

Accepted (2026-07-02)

## Context

upstream は独自の知識グラフ（CEG frontmatter の depends_on/topics、`docs/wiki/` の ADR、knowledge-backfill、wiki-sync）で agent 知識を管理していた。これらを削除するにあたり、後継として Google Cloud の [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) (OKF v0.1) を採用する。OKF は markdown + YAML frontmatter のディレクトリで知識をグラフ表現する vendor-neutral な標準で、必須フィールドは `type` のみ。

## Decision

- `docs/agent_docs/` と `docs/wiki/` の陳腐化した内容は破棄し、新スタックのアーキテクチャを `okf/` バンドルに再記述
- 各 concept は 1 ファイルの markdown、`type` frontmatter 必須、markdown リンクで cross-link、`index.md` で progressive disclosure
- `okf/` は chezmoi が `~/okf/` へ配備し、`~/CLAUDE.md` がそれを指す（OKF の「agent が読むバンドル」モデル）
- OKF は dotfiles repo 専用の知識に限定し、mattpocock ワークフローが各 product repo で使う `CONTEXT.md`/`docs/adr` とは混ぜない

## Consequences

- 知識は現実のアーキと一致し、agent が follow-link で辿れる
- OKF は構造の標準であり意味論は与えない（producer が type 語彙を決める）

関連: [index](../index.md) / [skill-harness](../skill-harness.md)
