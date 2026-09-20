# Scenario B: 最小変更メモ

## Deliverable

対象画面の合計表示を、すでに画面で利用している formatter に通して描画する。ヘルプ tooltip は、その表示コンポーネント内の局所的な開閉状態で制御し、開く・閉じる操作は表示だけを変える。

TanStack Query、共有 Context、複数の compound component による購読は現状のままにする。Mediator、reducer、Atom、Effect、グローバル UI state は追加しない。送信・業務規則・既存の Query 処理は移動も書換えもしない。

確認は次の振る舞いに絞る。

- 代表的な合計値が既存 formatter と同じ表示になる。
- ヘルプ操作で tooltip が表示され、閉じる操作で非表示になる。
- tooltip の開閉では送信、Query の変更・再取得、Context の値、他の操作状態が変わらない。

## Requirement achievement

| # | 結果 | 理由 |
| --- | --- | --- |
| 1 | ○ | 現行の TanStack Query とプロジェクト構成を維持し、Effect／Atom／MVP 移行を要求していない。 |
| 2 | ○ | 表示だけの変更を表示コンポーネントへ閉じ、Mediator、reducer、グローバル state を足していない。 |
| 3 | ○ | 複数 Context consumer と compound component の構成を維持し、単一 connector や中継階層を求めていない。 |
| 4 | ○ | 既存 formatter を再利用し、tooltip state は当該コンポーネントの局所状態にした。 |
| 5 | ○ | 業務・送信ロジックには変更対象を広げていない。 |
| 6 | ○ | 整形結果、tooltip の表示・非表示、開閉時に他の操作へ副作用がないことを確認項目にした。 |

## Trace

| Phase | 状態 | 内容 |
| --- | --- | --- |
| Understanding | OK | 表示整形と tooltip 開閉は送信や他操作に影響しない局所 UI 変更と判断した。 |
| Planning | OK | 既存 formatter と局所状態を使い、既存の Query／Context 境界を残す最小変更にした。 |
| Execution | OK | アプリケーションコードは変更せず、変更内容・責務・確認方法をメモ化した。 |
| Formatting | OK | 指定の日本語報告形式で、要件ごとの達成状況を記載した。 |

## Unclear points

なし。既存 formatter の具体的な識別子や tooltip コンポーネントの API は実装時の適用先選択であり、方針自体の曖昧さではない。

## Discretionary fill-ins

- tooltip は、既存 UI 部品が制御可能な開閉 API を持つ場合はそれを使う。なければ当該表示コンポーネントの boolean state だけを追加する。
- 確認は既存の画面テストがあればそこへ最小のケースを加え、なければブラウザで代表値と開閉時の副作用なしを確認する。

## Retries

0 回。再試行なし。
