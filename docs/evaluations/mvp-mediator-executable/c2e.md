# C2E: exclusive device

## 責務

親 Mediator が recording と calibration の排他、最新の開始意図、停止・解放・再試行を裁定する。子フローは開始要求だけを渡し、profile は独立した局所フローとしてこのモデルを変更しない。Effect 実行境界は返された command を実行し、型付きエラー、defect、中断、寿命管理を扱う。モデルは I/O、scheduler、runtime を持たない。

| 状態 | 所有者 | 分類 |
| --- | --- | --- |
| `phase`、`owner`、`desired`、`operationId` | 親 Mediator | 本実装で追加する裁定状態 |
| `pendingTarget`、`failedStage`、`nextId` | 親 Mediator | 検証専用の内部状態 |
| Effect の実行・結果通知 | 実行層 | 実行層の模擬 |

## 遷移と実行記録

| 検査 | 前状態 / event | 期待結果 | 実測結果 |
| --- | --- | --- | --- |
| 通常経路 | idle / start recording → ok → start calibration → ok → ok → ok | acquire(1)、stop(2)、release(3)、acquire(4)、active calibration | ○ `selfCheck()` |
| acquisition 中の反復 | acquiring recording / start calibration → start recording → ok(1) | command 追加なし、recording を active に採用 | ○ `selfCheck()` |
| stale と profile | stopping / ok(古い id)、profile | state/effects 不変 | ○ `selfCheck()` |
| stop/release 失敗 | stopping / fail(2)、retry、releasing / fail(4)、retry | blocked で旧 owner を保持し、retry のみ同一段階を新 ID で再実行 | ○ `selfCheck()` |
| acquisition 失敗 | acquiring / fail | idle、再試行 command なし | ○ `selfCheck()` |

実行済み: `node docs/evaluations/mvp-mediator-executable/c2e.mjs`。提案のみの検査はない。

## 固定チェックリスト

1. ○ acquiring / stopping / releasing / blocked で `desired` だけを更新し、進行中 command は重複しない。in-flight target へ戻る場合も acquisition 成功時に採用する。
2. ○ `stop` 成功後にだけ `release`、`release` 成功後にだけ次の `acquire` を出す。失敗は `blocked` にし、`retry` だけが失敗段階を再実行する。
3. ○ `nextId` は command ごとに増え、intent 更新で operationId を変えない。ID 不一致の結果は不変である。
4. ○ 純粋 model は command だけを返す。Effect 実行境界が実行、型付きエラー、defect、中断、寿命を所有する。
5. ○ `profile` は不変であり、子フローの局所状態を保持しない。
6. ○ モデル、上表、`selfCheck()` は同じ遷移を検証する。Node の `assert` で実行した。

## 追跡

| Trace         | 状態 |
| ------------- | ---- |
| Understanding | OK   |
| Planning      | OK   |
| Execution     | OK   |
| Formatting    | OK   |

## 不明点・判断

不明点はない。停止開始後に意図が旧 owner へ戻っても、停止済みの資源を復活させず release 完了後に最新意図を acquire する。理由は、停止・解放の成功を次の acquisition の前提とする方針である。一般則は「実行中の段階は同じ ID のまま完了させ、次段階でのみ最新意図を採用する」。

裁量判断: 状態は凍結した plain object、ID は state 内連番、`blocked` の `operationId` は null とした。再試行 command が新 ID を持つためである。再実行は不要だった。
