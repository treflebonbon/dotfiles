# Scenario A: 在庫引当ダイアログの責務メモ

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| 在庫引当ユースケース（Model） | itemId と数量を受け、利用可能在庫の業務ポリシーを判定し、実行直前にも再検証して引当を実行する。React や UI 状態には依存しない。 |
| 在庫画面の引当 Mediator | ダイアログの submit／close、取消、試行結果の採用を裁定する。`activeAttemptId` と取消待ちを所有し、表示用の操作可否・メッセージを Context に供給する。 |
| 既存 UI binding と Effect 実行境界 | Mediator が受理した試行を既存 binding 経由で実行する。Effect の Fiber 中断、Scope による資源解放、終了通知を担当し、成功・想定内エラー・defect・中断を区別して返す。中断はサーバー側引当のロールバックを意味しない。 |
| ダイアログ View | 数量入力と数値形式チェック、局所的な表示を保持する。検証済みの submit 要求と close 要求を Mediator に通知する。在庫可否の業務規則は再実装しない。 |
| 2 つの Context consumer | Context の同じ表示状態とイベント送信口を読む。相互に直接操作せず、forwarding 専用コンポーネントも置かない。 |
| 在庫の背景更新 | 既存の取得・キャッシュ更新機構で在庫表示を更新する。進行中の引当フローの状態は変更しない。 |

既存 binding の pending/outcome が引当試行の表示に足りる部分はそのまま使う。追加するのは、同じ item の取消後再送信と遅延結果を区別する `activeAttemptId`、および取消を開始して次の送信を受け付けない `cancelling` 協調状態だけである。

### イベントと遷移

| 現在状態 | イベント | Mediator の裁定 | 次状態 |
| --- | --- | --- | --- |
| `editing` | `submit(itemId, quantity)` | 形式チェック済みなら新しい `attemptId` を発行し、既存 binding に実行を依頼する。 | `submitting(attemptId)` |
| `submitting(A)` | `close` | A の中断と資源解放を実行境界へ依頼し、ダイアログを閉じる。終了通知を待つ間は新規 submit を受理しない。 | `cancelling(A)` |
| `cancelling(A)` | `executionFinished(A, *)` | 終了通知を消費して資源を解放済みにし、結果は表示に採用しない。 | `closed` |
| `submitting(A)` | `executionFinished(A, success)` | A が `activeAttemptId` と一致するときだけ成功を採用する。 | `succeeded(A)` |
| `submitting(A)` | `executionFinished(A, expectedError)` | A が一致するときだけ想定内エラーを表示する。 | `editing` |
| `submitting(A)` | `executionFinished(A, defect)` または `interrupted` | A が一致するときだけ、それぞれを区別した UI 通知へ変換する。 | `editing` または `closed` |
| `editing`／`succeeded` | 同じ item の新しい `submit` | 新しい `attemptId` を active にして実行する。 | `submitting(B)` |
| `submitting(B)` | `executionFinished(A, success/error/defect/interrupted)` | A は active でないため、B の表示・状態を変更しない。必要な A の終了・解放通知だけを処理する。 | `submitting(B)` |
| 任意 | `stockRefreshed` | 在庫表示を更新するが、active attempt とダイアログ遷移は変更しない。 | 現在状態を維持 |

`close` 後に同じ item を再度開いて送信する場合は、A の終了通知を照合できる識別を実行境界に保持したまま B を開始する。待機先の View が閉じても、A の終了通知そのものを捨てない。

### 確認項目

1. 利用可能在庫を超える数量を送っても、UI の disabled 判定とは独立にユースケースが実行時に拒否する。
2. A を送信、close で取消、同じ item で B を送信した後に A の成功と失敗をそれぞれ到着させても、B の pending／outcome と表示は変わらない。
3. close 後、実行境界が A の中断と Scope の解放を完了して `executionFinished(A, interrupted)` を返す。UI は中断をサーバー側引当の取消成功として表示しない。
4. 2 つの Context consumer が同じ submit／close 送信口を使っても、数量・形式チェックはダイアログ内に残り、在庫ポリシーはどちらの View にもない。
5. binding の pending/outcome を表示に使い、追加状態が `activeAttemptId` と `cancelling` に限られることを確認する。
6. B の `submitting` 中に `stockRefreshed` を発生させても、B が `submitting` のままで active attempt と取消可否が変わらない。

## Requirement achievement

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | ユースケースが在庫ポリシーと実行時再検証を所有し、View は表示・通知だけとした。 |
| 2 | ○ | 引当 Mediator を UI 所有者として明記し、attemptId 照合で先行試行の成功・失敗とも新試行へ採用しない。 |
| 3 | ○ | Effect 実行境界へ中断・寿命管理を委譲し、想定内エラー、defect、中断を分け、中断とサーバーロールバックを区別した。 |
| 4 | ○ | 複数 Context consumer とダイアログ内の数量／形式チェックを維持し、forwarding コンポーネントを要求していない。 |
| 5 | ○ | 既存 binding の pending/outcome を再利用し、取消・試行照合に必要な追加状態だけを特定した。 |
| 6 | ○ | 背景更新を含むイベント遷移と、実行中の状態を維持する具体的な確認を示した。 |

## Trace

Understanding／Planning／Execution／Formatting: **OK**。Scenario の Effect、既存 binding、共有 Context、close=cancel、同一 item の再送信、遅延結果、背景更新を責務・遷移・確認へ反映した。

## Unclear points

なし。`attemptId` の具体的な生成方式、Effect 実行境界と既存 binding の接続 API は通常の実装選択であり、指示の曖昧さではない。

## Discretionary fill-ins

- `attemptId` は submit ごとの単調増加値または UUID とし、itemId 単独では照合しない。
- `cancelling` 中は二重 submit を拒否し、終了・解放通知を受けた後に次の要求を受ける。
- defect の観測・通知先は既存アプリケーション境界の方針に従う。

## Retries

0（再試行なし）。
