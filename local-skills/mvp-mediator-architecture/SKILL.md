---
name: mvp-mediator-architecture
description: "Design or review UI responsibility boundaries with Passive View and hierarchical Mediators. Use for new frontend architecture, MVP-based UI changes, or competing UI flows such as submission, cancellation, and cross-screen coordination. Preserve existing project architecture; routine React edits do not require migration. Library-independent principles, with Effect-oriented guidance when Effect is already adopted. Delegate Result/error composition to rop."
allowed-tools: Read, Edit, Write
metadata:
  depends_on: []
  topics:
    [
      react,
      tanstack,
      effect-ts,
      mvp,
      passive-view,
      mediator,
      chain-of-responsibility,
      state-machine,
      frontend-architecture,
    ]
  source: human
---

# MVP + Mediator Architecture

## 適用範囲

新規開発の UI 設計の既定として使う。既存プロジェクトでは、その設計規約と今回の変更範囲を確認してから適用する。小修正を理由に MVP への移行や依存ライブラリの変更を要求しない。

このスキルが定めるのは UI の責務とイベントの裁定。構造の原則はライブラリ非依存とし、単純な UI に形式的な Mediator や reducer を追加しない。

## 責務の所有者

| 役割 | 所有する責務 |
| --- | --- |
| Model／ユースケース | 業務規則と実行時の検証。UI 技術に依存しない処理。 |
| Mediator | 担当 UI フローの操作許可、状態遷移、取消・再試行の方針、結果採用。Model の判定や結果を表示へ変換する。 |
| 実行層 | 裁定された処理の実行、通信中断、購読解除、リソース解放。 |
| Passive View | 表示と利用者操作の通知。他の操作の許可・取消・進行に影響しない局所状態。 |

業務上の可否と UI の操作許可を分ける。例えば発送済み注文のキャンセル可否は Model が決め、実行時にも検証する。Mediator はその判定と進行中の UI 状態から表示を作る。disabled のために業務規則を再実装しない。

## Root と階層的な裁定

独立した UI フローごとに Mediator を置き、複数フローの競合には共通の親を設ける。各 Mediator は担当範囲のイベントを処理し、範囲を超える要求を親へ委ねる。これが Chain of Responsibility の境界であり、すべての中間層を転送だけに限定する意味ではない。

Root は全体の構成を組み立て、必要なら全体に関係する UI 操作を裁定する。Root の単一性と判断の所有単位を区別する。「唯一の裁定者」は同じ判断に所有者が1つあるという意味で、全イベントをアプリ全体の1つの Mediator に集めるという意味ではない。

View は担当 Mediator に操作を通知する。兄弟の View を直接操作せず、フロー間の連携は責任を持つ親へ要求する。注文一覧とプロフィール編集は独立してよいが、同時実行不可の音声入力と範囲選択は共通の親が切替を決める。

## View と接続方法

props、Context、compound components はプロジェクトに合わせて選ぶ。複数の View が表示状態を購読したり同じイベント送信口を使ったりしてよい。購読箇所や connector の個数ではなく、裁定が同じ所有者へ届くかを確認する。転送だけのコンポーネントをこの規則のために追加しない。

純粋な表示整形、表示条件の分岐、ツールチップの開閉などは View に置ける。入力値と形式チェックはフォームに保持できる。ただし、その状態が他の操作の許可・取消・進行を左右する場合は Mediator が裁定する。閉じると送信が取り消されるダイアログは、単なる表示用の開閉状態ではない。

## 状態遷移と非同期処理

状態間の制約がある UI フローでは、状態・イベント・許可される遷移を明示する。reduce を使う場合は同期・純粋に保ち、I/O の結果をイベントとして戻す。裁定された遷移から処理を実行し、呼出側に同じ許可条件を重複させない。

イベントの受理・無視条件は状態ごとに記述し、説明・遷移表・検証ケースで同じ条件を使う。同じイベントでも実行中と終了待ちで扱いが変わる場合、状態を省略した一律の規則にまとめない。

再送信・取消・結果採用の方針は Mediator が所有する。方針に従う通信中断や購読解除は実行層へ委譲できる。ライフサイクルの cleanup を独立した業務判断と混同しない。中断は外部処理の巻き戻しを保証しないので、業務上の取消と区別する。

古い成功・失敗やキャッシュ再検証の通知で進行中の操作を上書きさせない。同じ対象への再試行を区別する必要があれば、操作単位の識別子を使う。単なるデータ再描画は購読機構に任せ、操作の許可・進行を変える通知を Mediator の裁定へ戻す。結果の除外を reduce 内だけに限定せず、実行層の仕組みが採用方針を満たすかを確認する。

新しい利用者要求と、継続中の実行の識別を区別する。反復要求で待機先だけを変える場合、実行中の停止・解放とその完了通知を照合する識別は維持する。表示結果を採用しない場合でも、所有資源の解放や次操作の開始に必要な終了通知は処理する。要求の更新だけで継続中の実行まで無効化すると、必要な完了通知を失って遷移が止まる。

## 他の設計規約・Effect との分担

- **VSA**: 機能・ユースケース単位の slice 内に UI の裁定を置く。Root のために業務処理を横断集約しない。
- **ヘキサゴナル**: Model／ユースケースは React・Atom から独立させ、UI との接続を外側に置く。
- **ROP**: 成功・失敗の合成には `rop` スキルを明示的に読み、その言語別 reference を使う。ここに規則を重複定義しない。
- **Effect 採用時**: 型付きエラー、明示した依存関係、Effect の合成、Fiber／Scope による実行と寿命管理を優先する。想定内エラー・defect・中断を区別し、Mediator のために同等の非同期制御を自作しない。

既存の取得状態だけでフローを表せるなら、それを使う。追加の排他や取消制約がある場合だけ、その制約を Mediator の状態として表す。Atom を使うこと自体は、フローの裁定が成立する保証ではない。

React／TanStack／Effect を採用したプロジェクトに適用するときは [実装例](references/tanstack-effect.md) を読む。Effect 自体の導入や TanStack Query からの置換はこのスキルの責務に含めない。

## 適用後の確認

- 既存設計と変更範囲に合い、表示だけの修正に新たな裁定層を持ち込んでいないか。
- 業務規則、UI の遷移、実行と寿命管理の所有者を特定できるか。
- props／Context のどちらでも、同じ判断が複数箇所へ分散していないか。
- 局所状態が他の操作を変えないか。フロー間の競合は共通の親が扱うか。
- 連打、取消、同じ対象への再試行、遅延した成功・失敗、再検証通知で操作の制約を破らないか。
- Effect や既存ライブラリが担う状態・非同期制御を二重に実装していないか。
