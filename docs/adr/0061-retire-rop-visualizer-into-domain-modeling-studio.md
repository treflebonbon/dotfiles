---
type: decision
title: rop-visualizerを退役しdomain-modeling-studioへ資産を統合する
description: 二重のレンダラを持たず、ROP意味論とTypeScript抽出ヘルパーだけをdomain-modeling-studioへ移設する
tags: [adr, skills, domain-modeling-studio, rop-visualizer]
timestamp: 2026-09-18
status: accepted
---

# rop-visualizerを退役しdomain-modeling-studioへ資産を統合する

## Context

`domain-modeling-studio`（PR #329）に、Uncle Bob氏の「俯瞰してコードへドリルダウンできるビューアが不可欠」という指摘([Issue #331](https://github.com/treflebonbon/dotfiles/issues/331))を踏まえたアーキテクチャ層・関数フロー層を追加する。関数フロー層のROP(成功/失敗/回復)モデリングは`local-skills/rop-visualizer`が既に確立していたが、そのレンダラはMermaid `flowchart TB` をPlaywright CLIセッションでSVG化する経路であり、domain-modeling-studioはReact Flow + JSONを採用し生成にブラウザを要しない。両者は技術的に別物で、レンダラの移植は高コストになる。

常時読み込まれるskill一覧に別skillとして載ることはコンテキストを消費し、`grill-with-docs`セッションでユーザーは「コンテキストを考えてスキルは最小限にしたい」という理由でrop-visualizerの統合退役を選んだ。

## Decision

- `local-skills/rop-visualizer`を独立skillとして完全に退役する。`.chezmoidata/local-skills.yaml`の`localSkills.retired`に追加し、`runtime/skill-harness.md`のカタログから除く。
- Mermaid+Playwrightのレンダラ(`scripts/render.py`、`assets/report.*`、`references/report-format.md`)、および評価用フィクスチャ(`evals/`)は移植せず削除する。新しいレンダラは作らず、既存のdomain-modeling-studioの単一レンダラ(React Flow + JSON、`scripts/render.mjs`系)に一本化する。
- 再利用するのは次の2点のみ: (1) ROPの意味論モデリング規則(`references/rop-semantics.md`として移設。bind/map error/recovery/bypass/termination/型外の異常の扱い)、(2) TypeScript Effect用のast-grep抽出ヘルパー(`scripts/extract-typescript.py`、`references/typescript-evidence.md`、`references/effect-ts.md`、`references/rust.md`として移設)。いずれも`domain-modeling-studio`配下に配置し、動作(入出力contract)は変更しない。
- 「クイックモード」のような別コード経路は作らない。関数フロー層だけを埋めたモデルを渡せば同等の使い方ができる(1 CLI・1 skill)。
- `docs/research/`・`docs/evaluations/`配下のrop-visualizer関連ドキュメントは削除しない。過去の設計判断の経緯は履歴として残す([ADR-0057](0057-retire-to-worktree-for-native-entry.md)の`to-worktree`退役と同じ扱い)。

## Trade-offs

動くMermaidレンダラを書き直すコストを避けることを優先したため、TypeScript Effect以外の言語(Rust等)向けの関数フロー層は当面ソース読解のみで、rop-visualizerが持っていた構文抽出の恩恵を受けない。将来的にRust側の構文抽出が必要になった場合は、この決定を見直す。

skill数を1つ減らす一方、`domain-modeling-studio`の責務は業務フロー・アーキテクチャ層・関数フロー層の3層に広がる。これは意図した統合であり、責務分割よりコンテキスト消費の削減を優先した判断である。

## Verification

- `tests/domain-modeling-studio.bats`: 移設したTypeScript抽出ヘルパーの契約テスト、domain-modeling-studioの配備に新しい参照・スクリプトが同梱されることの検証、rop-visualizerがソースから削除され`localSkills.retired`に含まれることの検証。
- 既存の`tests/local-skills.bats`の撤去メカニズム契約(汎用フィクスチャ)は変更なく成功する。
