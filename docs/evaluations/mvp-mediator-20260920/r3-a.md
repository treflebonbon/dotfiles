# Scenario A 実行メモ

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| 予約ユースケース（Model） | 在庫可否を所有し、予約実行時に再検証する。成功または型付きの想定内業務エラーを返す。画面は在庫の二重ルールを持たない。 |
| `ReservationFlowMediator` | Submit、取消、結果採用を裁定する名前付き UI 所有者。現在の `attemptId`、`itemId`、`submitting`／`cancelling` を管理し、表示用の操作可否を作る。 |
| 既存 UI binding と Effect 実行境界 | 既存の operation の pending/outcome を再利用して実行する。Mediator の取消指示に従って Fiber の中断、Scope の解放、購読解除を行い、終了通知を返す。想定内エラー、defect、中断は別種として境界へ返す。 |
| 予約ダイアログ（Passive View） | quantity と数値形式チェックを局所状態として保持し、Submit／Close を Mediator へ通知する。Close は送信中なら取消要求であり、View 自身は通信や他パネルを操作しない。 |
| 在庫パネルと予約パネル | 同じ Context から表示状態と event sink を読む。転送専用コンポーネントは置かない。背景在庫更新は既存の取得状態で表示を更新する。 |

Root は Context と `ReservationFlowMediator` を組み立てる。この画面で別フローとの排他はないため、親 Mediator は追加しない。

### 状態・イベント・遷移

`attemptId` は Mediator が Submit のたびに新規発行する。結果は `itemId` だけでなく `attemptId === activeAttemptId` のときだけ採用する。

| 現在状態 | イベント | Mediator の遷移・処理 |
| --- | --- | --- |
| `ready` | `submit(validQuantity)` | 新しい `attemptId` を active にして `submitting` へ遷移し、ユースケース実行を実行境界へ依頼する。 |
| `ready` | `submit(invalidFormat)` | View の形式エラー表示だけを更新し、実行しない。 |
| `submitting(A)` | `close` / `cancel` | A を取消済みにし `cancelling(A)` へ遷移する。実行境界に A の中断と解放を依頼する。サーバーの予約が巻き戻ったとは扱わない。 |
| `submitting(A)` | `result(A, success \| expectedError \| defect \| interrupted)` | A が active なら結果種別を保って表示状態へ反映し `ready` へ遷移する。 |
| `submitting(A)` または `cancelling(A)` | `result(B)`（B ≠ A） | 無視する。 |
| `cancelling(A)` | `finished(A)` | A の終了と資源解放を確認して `ready` へ遷移する。ここから同一 item の新規 Submit を許可する。遅延した A の成功・失敗は active ではないため採用しない。 |
| すべて | `stockRefreshed` | 在庫表示を既存の取得状態から更新するだけで、active attempt と `submitting`／`cancelling` を変更しない。 |

既存 binding の pending/outcome がこの operation を表せる限り、それを表示に使う。追加するのは、取消と同一 item の試行を照合するための `activeAttemptId` と終了待ちだけであり、取得・在庫・送信状態一式を複製しない。

### 確認項目

| 確認 | 期待結果 |
| --- | --- |
| 在庫表示が十分でも、実行直前に在庫が尽きる | ユースケースが再検証して拒否し、UI はその型付き結果を表示する。 |
| A を送信中に Close | Mediator が A の取消を裁定し、実行境界が中断・解放を行う。中断だけからサーバー取消済みとは表示しない。 |
| A を取消・終了後に同じ item を B として送信し、A の成功が遅着 | B の表示と状態は変わらない。 |
| 同じ条件で A の失敗が遅着 | B の表示と状態は変わらない。 |
| 送信中に背景在庫更新 | 在庫表示は更新されるが active attempt、pending 表示、取消可否はリセットされない。 |
| 二つの Context consumer から Submit/Close | どちらの通知も同じ `ReservationFlowMediator` に届き、許可条件が分散しない。 |

## 要件達成

1. **○** ユースケースが在庫可否を所有し、実行時の再検証を明記した。表示側は二重の在庫規則を持たない。
2. **○** `ReservationFlowMediator` を Submit／取消／結果採用の所有者とし、`attemptId` 照合で旧 A の成功・失敗が新 B を上書きできない。
3. **○** Effect の実行・中断・資源寿命を実行境界へ委譲し、想定内エラー、defect、中断を区別した。中断をサーバー・ロールバックとは同一視していない。
4. **○** 共有 Context の複数 consumer とダイアログ内の quantity／数値形式チェックを維持し、転送専用コンポーネントを要求していない。
5. **○** 既存 binding の operation 状態を再利用し、追加状態を `activeAttemptId` と取消終了待ちに限定した。
6. **○** Submit、Close/Cancel、照合済み・不一致の結果、背景更新を含む具体的な遷移と確認項目を示した。

## Trace

Understanding／Planning／Execution／Formatting: **OK**。

| 段階          | 不明点 | Issue | Cause | General Fix Rule |
| ------------- | ------ | ----- | ----- | ---------------- |
| Understanding | なし   | なし  | なし  | なし             |
| Planning      | なし   | なし  | なし  | なし             |
| Execution     | なし   | なし  | なし  | なし             |
| Formatting    | なし   | なし  | なし  | なし             |

## Discretionary fill-ins

- **アプリケーション方針の選択**: 取消要求直後の再送信は許可せず、A の `finished` による終了・解放確認後に B を開始する方針にした。未解放の実行と B を同時に所有しないためである。要件の曖昧さではない。
- **アプリケーション方針の選択**: `stockRefreshed` は在庫表示を更新してよいが、進行中の予約結果を採用しない。この分離は既存の取得状態を保持しつつ操作フローを守るためである。要件の曖昧さではない。

## Retries

0 回。理由: 指示とシナリオから必要な責務、遷移、確認項目を一度で確定できた。
