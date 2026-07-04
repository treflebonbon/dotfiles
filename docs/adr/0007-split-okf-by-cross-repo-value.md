---
type: decision
title: okf/ を cross-repo 価値で分割し runtime/ へ改名
description: home-wide 配備に本当に価値がある concept 文書だけを残し、dotfiles repo 自身にしか関係しない文書は docs/ へ移す。ディレクトリ名も OKF という書式名から内容を表す runtime/ へ改める
tags: [adr, okf, runtime, chezmoi]
timestamp: 2026-07-04
---

# okf/ を cross-repo 価値で分割し runtime/ へ改名

## Status

Accepted (2026-07-04)

## Context

[ADR-0006](0006-consolidate-decisions-into-docs-adr.md) は決定記録の置き場だけを扱い、`okf/` 配下の concept 文書（`architecture.md` / `shell-environment.md` / `skill-harness.md` / `ai-runtimes.md` / `conventions.md`）の扱いは未解決のまま残していた。この点についてセカンドオピニオンとして Codex に相談したところ「`okf/` は `~/okf/` に実配備され home-wide で参照されるため現状維持が妥当」という回答を得たが、これは 5 ファイルを一枚岩として扱っており、精査すると前提が誤りだった。

実際に内容を確認すると:

- `shell-environment.md` / `skill-harness.md` / `ai-runtimes.md` は、どの repo で作業していても同じ意味を持つ **ambient な環境情報**（シェル環境・skill 配備の仕組み・AI ランタイム設定）であり、home-wide 配備の恩恵が実際にある。
- `architecture.md`（chezmoi source レイアウト、2種の flake devShell）と `conventions.md`（この repo 自身の commit/lint 規約）は **dotfiles repo 自身の内部情報**であり、他の無関係な repo で作業中の agent が読んでも何の価値も生まない。

さらに、ディレクトリ名 `okf/` そのものにも問題があった。OKF (Open Knowledge Format) は markdown + YAML frontmatter で知識を表現する*書式の名前*であり、中身が何であるかを説明しない。書式名をディレクトリ名に転用すると、後から見た人に「このディレクトリは何のためのものか」が伝わらない。

副次的に、今回の一連の再編（`docs/adr/` / `docs/agents/` の新設）で `docs/**` が `.chezmoiignore` から漏れており、`chezmoi apply` すると意図せず `~/docs/` へ配備される状態になっていたことも発覆した。

## Decision

- `okf/` を `runtime/` へ改名する。中身は `shell-environment.md` / `skill-harness.md` / `ai-runtimes.md` / `index.md` の4ファイルのみとし、chezmoi による `~/runtime/` への home-wide 配備を維持する。
- `architecture.md` と `conventions.md` は `docs/architecture.md` / `docs/conventions.md` へ移動する。`docs/` は `.chezmoiignore` に追加し、home へは配備しない（repo ローカル専用）。
- OKF の frontmatter 形式（`type` / `description` / `tags`）自体はそのまま使い続ける。書式として有用であることと、ディレクトリ名として不適切であることは別の話。
- `.chezmoiignore` に `docs`/`docs/**` を追加し、`docs/adr/` と `docs/agents/` が意図せず `~/docs/` へ配備される問題を修正する。

## Consequences

- `runtime/` は「home 配下のどの repo でも同じ意味を持つ知識だけを置く」という基準が明確になり、今後ファイルを追加する際の判断軸になる。
- `docs/architecture.md` / `docs/conventions.md` は repo ローカルとなり、`CLAUDE.md` / `AGENTS.md` / `README.md` からの参照もそちらへ更新した。
- `runtime/` という名前は汎用的すぎて将来別の意味と衝突する可能性はあるが、`okf/` のような書式名よりは内容を表しており改善である。
- Codex へのセカンドオピニオンは「配備先が home-wide である」という事実だけを根拠に現状維持を推奨したが、個々のファイルの内容価値までは踏み込んで検証していなかった。今後この種の相談をする際は、ファイル単位の実質的な価値の検証を求めること。

関連: [ADR-0003](0003-okf-knowledge-bundle.md) / [ADR-0006](0006-consolidate-decisions-into-docs-adr.md) / [runtime/index](../../runtime/index.md)
