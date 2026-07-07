---
type: decision
title: 要素指差しフィードバックを to-pr ではなく tdd の実装ループに位置づける
description: issue #31 の「to-prのブラウザ選択」提起を受け、Codex Annotation Mode / Orca Design Mode / Claude Code claude-in-chrome を「要素指差しフィードバック」として命名し、playwright-cli による to-pr の自律検証とは別に tdd の実装フェーズの対話チャネルとして位置づける
tags: [adr, tdd, to-pr, browser, context]
timestamp: 2026-07-07
---

# 要素指差しフィードバックを to-pr ではなく tdd の実装ループに位置づける

## Status

Accepted (2026-07-07)

## Context

[issue #31](https://github.com/treflebonbon/dotfiles/issues/31) は「実行環境により playwright-cli より内蔵機能を利用したい」として、Orca IDE / Claude for Chrome / Codex app / Antigravity 2.0 のブラウザドキュメントを挙げ、`to-pr` のブラウザ選択の見直しを提起した。

grilling セッションで動機を掘り下げたところ、実際に指しているのは Codex CLI の Annotation Mode（要素/範囲を選択してコメントを送信し、Codex が precise visual change を実装する）と Orca IDE の Design Mode（要素クリックで HTML/CSS/screenshot をエージェントへ送り、指示を受けて実装しホットリロードする）だった。これらは**人間主導**で**実装中**に UI へフィードバックを与える対話チャネルであり、`to-pr` の「UI verification procedure」（実装完了後に**エージェントが自律的に** `playwright-cli` で AC を検証する post-hoc の作業）とは主体・タイミングの両方が異なる。`codex:codex-rescue` 経由で相談した Codex エージェント自身も同じ切り分けを支持した。

Claude Code にも同種の対話チャネルとして `claude-in-chrome`（Claude for Chrome）がある。Antigravity 2.0 は公式ドキュメントの内容が確認できず（JS レンダリングで取得不可）、今回のスコープ外とした。

## Decision

- issue #31 が提起した「to-prのブラウザ選択」ではなく、**`tdd` の実装ループにおけるブラウザ選択**として扱う。`to-pr` の UI verification procedure（`playwright-cli` によるエージェント自律検証）は変更しない。
- この対話チャネルを [CONTEXT.md](../../CONTEXT.md) に「要素指差しフィードバック」として命名し、`Verification Matrix` と混同されないよう `_Avoid_: UI verification, ブラウザ検証` を明記した。
- CLAUDE.md の「## ブラウザ操作ツール」節に、実行ランタイムごとの対応（Codex CLI: Annotation Mode / Orca IDE: Design Mode / Claude Code: `claude-in-chrome`）を追記する。ランタイム検出ロジックは導入しない — 実行中のエージェントは自身のランタイムの機能を把握しているため、`to-worktree` の Orca 分岐（ADR-0011）のような明示的な検出手順は不要と判断した。
- Antigravity 2.0 の対応は今回確認できなかったため明記せず、判明次第追記する。

## Consequences

- `to-pr` の SKILL.md・verification matrix の設計は変更不要。issue の原提起とはスコープが異なる形で閉じる。
- 将来 Antigravity 2.0 の同等機能が判明した場合、CLAUDE.md / CONTEXT.md の該当箇所に追記が必要。
- 「要素指差しフィードバック」という語は、今後 `tdd` 実装時の会話で `playwright-cli` や `claude-in-chrome`（`to-pr` 文脈）と混同せず使う。

関連: [issue #31](https://github.com/treflebonbon/dotfiles/issues/31) / [CONTEXT.md](../../CONTEXT.md) / [ADR-0011](0011-orca-skills-via-apm.md)
