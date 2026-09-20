# Search UI の責務・イベント・検証メモ

## Actual Deliverable と検証

`search.mjs` は、検索結果の採用を裁定する `SearchMediator` と、Node で実行する自己検証を含む最小の純粋モデルである。既存の React/Query バインディングが要求実行と通常の pending/result を引き続き担い、この Mediator は開始ごとに発行する要求 ID で、完了結果を画面へ採用するかだけを決める。文字列の同一性は判定に使わない。

検証は `node docs/evaluations/mvp-mediator-executable/search.mjs` で実行する。自己検証は、同じ `cat` を再入力した場合を含め、古い成功と失敗が最新要求の pending/result/error を変えないこと、最新要求の失敗と成功は適用されることを確認する。

## 責務とイベント

| 所有者 | 責務 |
| --- | --- |
| 既存の Query バインディング／実行層 | 検索の実行、通常の pending/result の提供、既存の取消要求。取消はベストエフォートであり、サーバー処理が止まった証明にはしない。 |
| `SearchMediator` | `beginSearch` で単調増加の要求 ID を最新として記録し、`completeSuccess`／`completeFailure` をその ID と照合して表示への採用を裁定する。 |
| Passive View | 入力を `beginSearch` へ通知し、Mediator が採用した表示状態を描画する。ヘルプツールチップの開閉は局所状態として扱い、検索要求や結果採用には通知しない。 |

| 前状態 | イベント | 後状態 | 採用 |
| --- | --- | --- | --- |
| 任意 | `beginSearch(text)` | 新しい要求 ID を最新にして pending | 該当しない |
| 最新 ID の pending | `completeSuccess(id, results)` | pending を解除し results を更新 | 採用 |
| 最新 ID の pending | `completeFailure(id, error)` | pending を解除し error を更新 | 採用 |
| 新しい ID が最新 | 古い ID の成功／失敗 | 変更なし | 除外 |

## 6 基準の達成

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 要求 ID を開始ごとに増やして照合するため、同じ文字列の再入力でも別要求として扱う。 |
| 2 | ○ | 自己検証で古い成功・失敗が新しい pending/result/error を変えず、最新の失敗・成功は適用されることを assert する。 |
| 3 | ○ | 実行と通常の Query 状態は既存バインディングへ残し、追加するのは結果採用の照合だけである。 |
| 4 | ○ | Effect、Atom、独自 scheduler、取消でサーバー処理を巻き戻すという前提を追加していない。 |
| 5 | ○ | 結果採用の所有者を `SearchMediator` と明記し、ツールチップは局所表示状態に留める。 |
| 6 | ○ | メモの遷移とモデルの分岐は同じ ID 照合であり、自己検証を実行する。ブラウザー／実行時統合を検証したとは主張しない。 |

## Trace

| 区分 | 状態 | 内容 |
| --- | --- | --- |
| Understanding | OK | 重複検索と同一文字列の再入力では、文字列でなく要求単位を区別する。 |
| Planning | OK | 既存 Query を実行層として維持し、採用方針のみを純粋な Mediator に置く。 |
| Execution | OK | 最小モデル、自己検証、責務・遷移メモを作成した。 |
| Formatting | OK | Node 構文確認、実行、対象2ファイルの diff whitespace 確認を行う。 |

## Unclear Issue / Cause / General Fix Rule

| 項目 | 内容 |
| --- | --- |
| Unclear Issue | 既存バインディングの正確な callback 接続形と、結果を Mediator が保持するか Query の値を選択して表示するかは与えられていない。 |
| Cause | シナリオは既存画面の抽象的な責務境界だけを指定している。 |
| General Fix Rule | 完了通知に開始時の要求 ID を戻し、現在の最新 ID と一致するときだけ表示状態へ反映する。既存 Query の実行・取消機構は置換しない。 |

## 裁量判断と再試行回数

- 裁量: 失敗時は直前の results を保持し、error のみ更新する形にした。これは pending と結果の既存表示を保ちつつ、現在の失敗を表示できる最小状態である。
- 裁量: `latestRequestId` を完了後も保持し、遅延完了を常に照合できるようにした。
- 再試行回数: 0 回。

## 限界

このモデルは純粋な結果採用規則だけを検証する。React、TanStack Query、実ネットワーク、取消、ブラウザー描画の統合は検証対象外である。

## 提出後の整形補足

この節は提出後の formatting 補足であり、上記の元自己評価表を改変しない。`SearchMediator` の `pending`、`results`、`error` は純粋モデル内で結果採用規則を assert するための状態である。一方で実装例として既存 Query binding の pending/result を再利用する接続をモデル化していないため、本文の「既存 binding が通常の pending/result を担う」という記述と、モデルの表示状態の所有境界は曖昧である。

この曖昧さを実装評価へ適用すると、S-3 は ○ ではなく partial となる。Issue は既存 binding の状態と Mediator の採用方針の接続が示されていないこと、Cause は自己検証用の表示状態を実装上の所有状態と区別する表現がなかったことである。General Fix Rule は、実アダプターでは既存 binding の pending/result をそのまま利用し、Mediator は最新要求 ID と完了採用可否だけを所有することとする。本モデルのアルゴリズムは変更していない。
