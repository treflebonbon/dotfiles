---
type: decision
title: MVP スキルを UI の裁定に限定し Effect の実行モデルと協調させる
description: VSA・ヘキサゴナル・ROP と併用するための適用範囲、階層的な Mediator、View の局所状態、Effect の責務を定める
tags: [adr, skills, mvp, mediator, effect, architecture]
timestamp: 2026-09-20
status: accepted
---

# MVP スキルを UI の裁定に限定し Effect の実行モデルと協調させる

## 2026-09-24 配布終了

[スキル有無の比較と共同判断](../evaluations/mvp-mediator-ab-20260924/decision.md)に基づき、現行スキルの配布を終了する。以下の設計原則は判断履歴として保持し、本文・参照例は評価資料に固定保存する。新しい短縮スキルは今回は作成しない。配布の撤去は既存のlocalSkills.retired経路を使い、main側の別の最小差分が受入・mergeされた後にlive sourceから反映する。

保存リンクは配布終了時点のv17を指す。以下のContextはADR決定前の版についての歴史説明であり、v17のdescriptionがReact全般への適用を要求するという意味ではない。

mainには同番号の別ADRが存在するため、本prototype branch全体をmainへmergeしない。mainの旧配布版への撤去は、2ソース・retired登録・番号衝突のない判断文書という別の最小差分で統合する。

## Context

設計検討時の [MVP スキル](../evaluations/mvp-mediator-ab-20260924/original/skill/SKILL.md) は React 開発全般に強く適用され、単一 Root、親経由のイベント転送、単一 connector を要求する。[実装例](../evaluations/mvp-mediator-ab-20260924/original/skill/references/tanstack-effect.md) には業務規則の所有者と購読箇所について食い違う説明があり、コンポーネント構成の範囲を超えて Atom の採用も指定している。他の設計規約と併用すると、UI の裁定、業務規則、非同期処理の責務が混ざる。

参考記事は Presenter の階層と、担当範囲を超える判断を親に委ねる構造を説明している。これはすべての中間層を転送だけに限定する規則とは異なる。今回の対話ではこの階層性を採用し、Effect の思想を重視しながら既存プロジェクトの設計と共存させる方針を確定した。[参考記事](https://zenn.dev/nrs/articles/9ba91aea587bf5)

## Decision

1. **適用範囲**: 新規開発の UI 設計の既定とし、既存プロジェクトではその設計規約を優先する。小修正を契機に MVP への移行を要求しない。
2. **必須の原則**: 業務判断と UI 遷移の責務分離を守る。props／Context は選択可能とし、親経由の callback 転送や機能ごとにちょうど1つの connector を一律には要求しない。Context の利用でも判断の所有者は変えない。
3. **技術スタック**: 構造の原則はライブラリ非依存とする。React／TanStack／Effect／Atom の記述は採用済みスタック向けの実装例とし、Effect 自体の導入や TanStack Query からの置換は要求しない。
4. **裁定の単位**: UI の裁定が必要なフローごとに判断の所有者を定める。Mediator は役割であり、既存の関数や binding が満たすなら専用 class/store/reducer を追加しない。「唯一」は同じ判断を複数箇所で所有しないことを指し、アプリ全体に Mediator を1つだけ置く意味ではない。Root の組立てと裁定の単位を区別する。
5. **業務規則**: Model／ユースケースが所有し、実行時にもそこで検証する。Mediator はそこで定義された判定や結果を表示値へ変換し、UI を遷移させる。disabled 表示のために業務規則を再実装しない。
6. **状態機械**: 操作の許可、取消、再試行など、状態間の制約がある UI フローで明示する。単純な UI のために形式的な Mediator や reducer を追加しない。
7. **階層的な連携**: 各 Mediator は担当範囲を裁定し、範囲を超える要求は親へ委ねる。複数フローの競合には必要な共通の親を設け、兄弟の View 同士が相手を直接操作する構造を避ける。Root は必要なら全体の UI 操作も裁定する。
8. **局所状態**: 他の操作・フローの許可、取消、進行に影響しない表示状態は View や専用ライブラリに置ける。入力値・形式チェックはフォームが保持できるが、送信開始や取消の裁定は Mediator が所有する。純粋な表示整形と業務判断を区別する。
9. **非同期処理**: 再送信・取消・結果採用の方針は Mediator が所有する。方針に従う通信中断・購読解除は実行層へ委譲でき、古い応答の除外を reduce 内だけに限定しない。同じ対象への再試行を区別する必要があれば、ドメイン ID だけでなく操作単位の識別子を使う。
10. **Effect の優先**: Effect 採用時は型付きエラー、依存関係の明示、Effect の合成、Fiber／Scope による実行と寿命管理を優先する。Mediator のために同等の非同期制御を独自実装しない。取得処理の状態だけで UI フローを表せる場合は共用し、複数操作の排他など追加の制約がある場合はその制約を Mediator が所有する。

Effect の想定内エラー、defect、中断の区別を UI 接続で失わない。Fiber の中断と Scope によるリソース解放は別の責務として扱う。具体的な API は導入版のソース・ドキュメントで確認する。[Expected Errors](https://effect.website/docs/v4/error-management/expected-errors)、[Concurrency](https://effect.website/docs/v4/concurrency/basic-concurrency)、[Scope](https://effect.website/docs/v4/resource-management/scope)

## 他の設計規約との分担

| 規約 | 本スキルとの関係 |
| --- | --- |
| VSA | 機能・ユースケース単位の slice を維持し、その UI 側に必要な Mediator を置く。Root を理由に業務処理を横断集約しない。 |
| ヘキサゴナル | UI／Mediator と Model／ユースケースを分離し、業務規則を React・Atom に依存させない。 |
| ROP | 成功・失敗の処理合成は既存の rop スキルへ委譲し、MVP スキルに重複定義しない。 |
| React composition | Context／compound components を利用できる。受け渡し方法と裁定の所有権を分ける。 |
| codebase-design | 純粋な転送のためだけに層を追加せず、小さいインターフェースと変更の局所性を保つ。 |

## Trade-offs と具体例

一律の props 制約より適用時の判断は増えるが、既存設計や Effect の機構を重複させずに済む。境界は UI の見た目やコンポーネント数ではなく、操作間の制約で判定する。

- ツールチップの開閉は局所状態にできる。閉じると送信を取り消すダイアログは UI フローの遷移として裁定する。
- 注文一覧とプロフィール編集は独立して動ける。音声入力と範囲選択が同時実行不可なら、共通の親が切替を裁定する。
- 発送済み注文のキャンセル可否は Model が決める。UI はその判定を表示し、実行時の検証も Model に任せる。
- 取消後や再試行前の応答が到着しても、現在の操作を上書きさせない。通信中断はこの方針の実行手段であり、業務上の取消や外部処理の巻き戻しとは区別する。

## 反映範囲

2026-09-21追記: Effect を優先した推奨構成を採用し、合わないパターンは取り入れない。既存機構の保証を確認し、追加の制約だけを UI 裁定へ置く。CoR は担当外の要求を親へ委ねる必要がある場合に使う。DAG はモジュール・依存構築・派生状態の依存に適用し、再試行など時間上の循環を許す。専用の実行機構は導入しない。

この ADR の Passive View は、購読と局所表示状態を許す実用上の緩和を含む。厳密な定義を必要とする場合は、Atom 等を購読する接続部分と props・イベントだけを扱う表示部分を分ける。緩和しても業務規則の再実装や兄弟 View の直接操作は許さない。Effect の Service／Layer と Atom の Registry を必要な境界で利用し、全パターンを別々の層として設置しない。

本 ADR は設計合意を記録する。スキル本文と実装例の description、適用チェック、Context の購読規則、業務規則の所有者、非同期処理の制約にこの決定を反映した。一般的なアーキテクチャ用語は、この repo 固有の語彙を管理する CONTEXT.md に追加しない。
