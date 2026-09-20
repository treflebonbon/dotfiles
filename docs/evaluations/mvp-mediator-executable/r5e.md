# r5e

## Deliverable

`r5e.mjs` は、録音と校正の排他を親 Mediator が裁定する純粋な抽象状態モデルである。`initial`、`transition`、`observe` を export し、Effect 実行層へ命令だけを返す。React、Effect runtime、I/O は含めない。

## 要件

| 要件 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 全待機 phase の `start` は `desired` のみを更新する。取得中に元の対象へ戻っても acquire を重複しない。 |
| 2 | ○ | 次の acquire は stop と release の成功後だけに発行する。stop/release の失敗は blocked にし、retry は失敗した段だけを新 ID で再実行する。 |
| 3 | ○ | 実行 ID は stage/retry ごとに増加する。待機中の intent 変更では保持し、異なる ID の完了・失敗は状態を変えない。 |
| 4 | ○ | 親 Mediator のモデルが排他・切替・結果採用を決める。実装では Effect が型付きエラー、defect、中断、Fiber/Scope の寿命を実行境界で扱い、モデルは command のみを出す。 |
| 5 | ○ | `profile` は状態も effect も変えない。子の局所 UI はこのモデルの外で独立する。 |
| 6 | ○ | 実装、ここに記した方針、自己確認を一致させた。実行済みは下記のみで、実アプリ統合確認は提案していない。 |

## 確認

実行済み: `node docs/evaluations/mvp-mediator-executable/r5e.mjs`。

確認項目は acquisition 中の最新 intent の往復、active から stop/release、release 失敗後の blocked と明示 retry、古い ID の無視、acquisition 失敗時の idle 復帰、profile の独立性である。

提案のみ: React の Passive View 接続、Effect の typed error / defect / interruption / Fiber / Scope の実行境界は、この抽象モデルの対象外であり実装していない。

## Trace

Understanding / Planning / Execution / Formatting: OK

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 停止中に元の owner が再度要求された場合の stop 取消 | 要件は停止済み I/O の取消手段を定義しない | 既に発行した stop/release は完了させ、release 成功後に最新 desired を acquire する。取消を要件化したときだけ実行層の明示的な cancel 結果を状態遷移へ加える。 |

## Discretionary fill-ins

state は凍結して入力の破壊を避け、未公開フィールドで retry stage と次 ID を保持する。owner は acquisition 成功まで null で、release 成功まで予約し続ける。

Retries: 0
