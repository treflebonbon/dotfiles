---
type: decision
title: 決定記録（ADR）の置き場を okf/decisions/ から docs/adr/ へ統合
description: mattpocock skills の標準（docs/adr/、軽量 ADR-FORMAT）に寄せつつ、既存の frontmatter（type/description/tags/timestamp）は維持する
tags: [adr, okf, mattpocock, domain-modeling]
timestamp: 2026-07-04
---

# 決定記録（ADR）の置き場を okf/decisions/ から docs/adr/ へ統合

## Status

Accepted (2026-07-04)

## Context

[ADR-0003](0003-okf-knowledge-bundle.md) は「OKF は dotfiles repo 専用の知識に限定し、mattpocock ワークフローが使う `CONTEXT.md`/`docs/adr` とは混ぜない」という前提で `okf/decisions/` を ADR置き場に採用した。しかし OKF 独自の frontmatter/type 分類/cross-link 構造は、そもそも upstream の CEG frontmatter・wiki-sync（旧 knowledge-graph 系 skill）との整合を取るために採用したもので、その旧 skill 依存は [ADR-0002](0002-mattpocock-over-superpowers.md) で既に解消済みだった。ADR 部分に限れば、OKF 固有の置き場を維持する理由はもう無い。

一方 mattpocock の `docs/adr/` は ADR-FORMAT.md により「1〜3文の単一段落でもよい」軽量な標準であり、frontmatter は要求しない。frontmatter（`type`/`description`/`tags`/`timestamp`）自体は実用上便利であり、mattpocock 側の domain-modeling skill もこれを禁止していない。

## Decision

- `okf/decisions/*.md`（5件）を `docs/adr/0001-....md` 〜 `0005-....md` として `docs/adr/` へ移設し、`okf/decisions/` ディレクトリと `okf/decisions/index.md` は削除する。
- 既存の frontmatter（`type: decision` / `title` / `description` / `tags` / `timestamp`）は維持したまま、mattpocock の連番ファイル名規則（`000N-slug.md`）に合わせる。本文の Status/Context/Decision/Consequences 構成もそのまま流用する（ADR-FORMAT.md は「価値がある時だけ含める」としており、既存内容はいずれも実質を伴うため削らない）。
- 以後、この repo で発生する決定記録（system/infra レベル・機能レベルを問わず）はすべて `docs/adr/` に一本化する。`docs/agents/domain.md` が定義していた「system は okf/decisions/、機能は docs/adr/」という二層分割は廃止する。
- `okf/` 配下の concept 文書（`architecture.md` / `shell-environment.md` / `skill-harness.md` / `ai-runtimes.md` / `conventions.md`）の扱いは本 ADR の対象外。これらは ADR でも `CONTEXT.md` の用語集でもない性質の文書であり、置き場は別途検討する。

## Consequences

- ADR の置き場が1箇所になり、`docs/agents/domain.md` の「okf/ との併存は暫定」という注記が解消される。
- `okf/decisions/index.md` のような一覧ページは持たない（mattpocock は連番ファイル名のみで十分としており、追加のインデックスは今回作らない）。
- [ADR-0003](0003-okf-knowledge-bundle.md) は本 ADR により一部 superseded（決定記録の置き場についてのみ）。concept 文書についての言及は有効なまま残る。
- concept 文書の置き場（`okf/` に残すか、`docs/` へフラット化するか等）は未解決だったが、[ADR-0007](0007-split-okf-by-cross-repo-value.md) で解決した（cross-repo 価値の有無で分割、ディレクトリ名も `runtime/` へ改名）。

関連: [ADR-0003](0003-okf-knowledge-bundle.md) / [ADR-0007](0007-split-okf-by-cross-repo-value.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
