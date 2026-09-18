---
type: decision
title: アーキテクチャ層の生成範囲を業務フロー近傍1ホップに限定する
description: リポジトリ全体走査ではなく、選んだ業務フローが触れるモジュールと依存先1ホップだけを対象にアーキテクチャ層を生成する
tags: [adr, skills, domain-modeling-studio, architecture-layer]
timestamp: 2026-09-18
status: accepted
---

# アーキテクチャ層の生成範囲を業務フロー近傍1ホップに限定する

## Context

[Issue #331](https://github.com/treflebonbon/dotfiles/issues/331) はUncle Bob氏の「俯瞰してコードへドリルダウンできるビューアが不可欠」という指摘を踏まえ、`domain-modeling-studio`にアーキテクチャ層(モジュール依存DAG)を追加する。ドメインモデリングセッションは常に1つの具体的な業務フローを対象にしており、対象リポジトリはそのフローに無関係な大量のモジュールを含みうる。アーキテクチャ層をリポジトリ全体走査で生成すると、大きなリポジトリでは生成コストが増え、レビュー対象の業務フローと無関係なノードでキャンバスが埋まり、静かな根拠机という視覚方針([references/DESIGN.md](../../local-skills/domain-modeling-studio/references/DESIGN.md))とも相容れない。

## Decision

- 生成器([scripts/generate-architecture.mjs](../../local-skills/domain-modeling-studio/scripts/generate-architecture.mjs))への入力は、選んだ業務フローが既に触れているモジュールのファイルパス一覧(seed)である。どの業務フローを対象にするか自体は既存の`Establish the evidence`工程(`SKILL.md`)の範囲であり、生成器はそれを判断しない。この生成器を業務フローの証拠(evidenceのpath)からseedを組み立てて呼び出す手順、および結果をアーキテクチャ層としてモデルへ統合する操作は、まだ`SKILL.md`のワークフローに組み込まれていない。統合はレイヤー選択UI・ドリルダウンを扱う後続チケット(Issue #331配下の#336/#337)の責務とする。
- 生成器はseedファイルだけを読み、その中のimport/require文などのテキストベース軽量解析(言語非依存の正規表現群)で1ホップ分の隣接ノードを追加する。相対パスとして解決できた依存は`MODULE`、それ以外は`EXTERNAL`になる。隣接ノード自身のソースは走査しない(推移的閉包を取らない、固定点計算をしない)。
- 生成したノード・エッジの`origin`は既定で`inference`にする。人間が事実として確認した場合は既存のレビューフロー(コメント→再調査→`code`または`agreement`への確度変更)を通す。この生成器自身は確度を昇格させない。

## Trade-offs

- 実際の依存グラフは1ホップより深いことが多い。より広い近傍が必要なレビュー者は、ドリルダウン等で得た追加のモジュールをseedに加えて生成器を再実行する。自動的な多ホップ探索は提供しない。
- テキストベースの軽量解析は構文正確さを保証しない。複数行にまたがるimportブロック(Goの`import (...)`等)、ビルドツールのパスエイリアス、Goのモジュールパス解決、Rustの完全なクレート木解決は対象外。解決できない指定子は安全側に倒して`EXTERNAL`として記録する(誤った内部エッジを捏造するより、過少に連携を示す方を選ぶ)。これは[Issue #331](https://github.com/treflebonbon/dotfiles/issues/331)のOut of Scope「型解析・参照解決の網羅的な正しさ」と整合する。

## Verification

- [tests/architecture.test.mjs](../../local-skills/domain-modeling-studio/tests/architecture.test.mjs): JS/Python/Rustのフィクスチャリポジトリで、seed + 1ホップの隣接(`MODULE`/`EXTERNAL`)だけが生成されること、2ホップ先のモジュールが含まれないこと、`origin: inference`が既定になること、生成結果が既存のモデルバリデータ(`validateDocument`)を通ることを確認する。不正な`revision`・リポジトリ外へ出る`seed`パスを拒否することも検証する。
