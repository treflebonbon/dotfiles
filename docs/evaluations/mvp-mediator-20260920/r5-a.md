# Scenario A: 在庫予約ダイアログのアーキテクチャ・メモ

## Deliverable

### 責務表

| 所有者 | 責務 |
| --- | --- |
| 予約ユースケース（Model） | 利用可能在庫の業務規則を保持し、実行時に再検証して予約を成功または型付きの想定内エラーで返す。表示用の在庫規則は作らない。 |
| 予約ダイアログ Mediator | submit、送信中 close（取消）、結果採用を裁定する。`attemptId` を発番し、現在採用できる試行を一つだけ保持する。 |
| 既存 UI binding / Effect 実行層 | 既存の operation の pending/outcome を表示に供給し、Mediator が受理した実行を開始・中断・解放する。想定内エラー、defect、中断を別々に通知する。中断はサーバーの予約処理が巻き戻った証拠にしない。 |
| ダイアログ View | quantity と数値形式チェック、表示、submit/close 通知を担当する。二つのパネルは既存 Context をそのまま購読し、同じ Mediator のイベント口を使う。中継専用コンポーネントは置かない。 |
| 在庫の背景更新 | 既存の取得・再検証機構で在庫表示を更新する。予約試行の状態を変更しない。 |

既存 binding の pending/outcome が送信の進行・結果を表せる部分は再利用する。追加するのは「どの試行の結果を採用できるか」と「送信中 close の取消」という、binding の取得状態だけでは表せない調整だけである。

### イベントと遷移

`activeAttemptId` は Mediator のみが更新する。結果イベントは必ず `attemptId` を持つ。

| 前状態 | イベント | 後状態 | Mediator の裁定 / 実行効果 |
| --- | --- | --- | --- |
| Closed / Ready | `submit(quantity)` | Submitting(`A`) | 数値形式済みの要求を受理し `A` を発番、`activeAttemptId=A` としてユースケース実行を依頼する。 |
| Submitting(`A`) | `close` | Closed | `activeAttemptId` を空にして A の取消を実行層へ依頼する。View は閉じる。中断要求はサーバー取消を意味しない。 |
| Closed | `submit(quantity)` | Submitting(`B`) | 新しい `B` を発番して `activeAttemptId=B` とする。A の停止・解放完了通知は実行層が資源解放に使い、B の採用条件を消さない。 |
| Submitting(`B`) | `result(A, success/failure/defect/interrupted)` | Submitting(`B`) | `A != activeAttemptId` のため表示状態・B の進行を更新しない。必要な解放と観測は実行層で続ける。 |
| Submitting(`B`) | `result(B, success)` | Ready / Closed | B の成功だけを採用し、既存の結果表示・在庫再取得へ接続する。 |
| Submitting(`B`) | `result(B, expected failure)` | Ready | B の型付き業務エラーだけを採用して表示する。 |
| Submitting(`B`) | `result(B, defect)` | Ready | defect として観測し、業務エラーに変換せず技術的失敗の表示方針へ渡す。 |
| Submitting(`B`) | `result(B, interrupted)` | Closed / Ready | 中断として完了を扱う。サーバー上の予約結果は未確定として、必要なら通常の在庫再取得で確認する。 |
| Submitting(`B`) | `backgroundStockRefreshed` | Submitting(`B`) | 在庫表示だけを更新し、`activeAttemptId`、pending、結果採用を変えない。 |

### 確認項目

1. 在庫不足へ submit し、ユースケースの実行時検証による型付きエラーが表示されること。View 側の在庫計算を前提にしないこと。
2. A を送信中に close し、取消要求が実行層へ渡りダイアログが閉じること。中断後もサーバー予約の成否を断定しないこと。
3. close 後に同じ item を B として再送信し、遅れて届く A の成功と失敗のどちらも B の pending/outcome を変えないこと。
4. B の想定内エラー、defect、中断が別の通知・表示方針になること。
5. 二つの Context consumer からの submit/close が同じ Mediator に届き、quantity/形式エラーは各ダイアログに局所のまま残ること。
6. B の送信中に背景在庫更新を発生させても B の pending と `activeAttemptId` が維持され、B の結果だけが採用されること。

## 凍結チェックリストの達成

1. ○ — 在庫方針と実行時再検証を予約ユースケースへ置き、View/Mediator に第二の在庫規則を置かない。
2. ○ — 予約ダイアログ Mediator を submit/cancel/result acceptance の明示的な所有者にし、`attemptId` 一致時だけ結果を採用するため、旧 A の成功・失敗は新 B を上書きできない。
3. ○ — 実行・中断・資源寿命は既存 binding / Effect 実行層へ委譲し、想定内エラー、defect、中断を分離した。中断をサーバー・ロールバックと同一視しない。
4. ○ — 二つの Context consumer と quantity/形式チェックを維持し、強制的な forwarding component を加えない。
5. ○ — 既存 operation state を再利用し、追加状態を取消と試行識別の調整に限定した。
6. ○ — 背景更新中の送信を含む、具体的なイベント遷移と確認項目を提示した。

## Trace

Understanding / Planning / Execution / Formatting: OK。

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 取消後に次の送信を開始できる正確な binding の契約 | 既存 binding の中断完了・再開始の API は指定されていない。 | 実装時に binding が試行ごとの `attemptId` と中断後の再開始を保証する箇所を確認し、保証できなければ実行層でその照合を提供する。Mediator に並行 scheduler を追加しない。 |
| 成功後のダイアログを閉じるか開いたままにするか | シナリオが成功後の表示方針を指定していない。 | プロダクト方針を決めるまで、成功の結果採用と在庫再取得だけを必須にし、open/close は既存 UI 規約に従う。 |

## Discretionary fill-ins

- `attemptId` は item ID ではなく送信ごとに一意な値にする。
- close は「表示を閉じる」だけでなく取消方針を発火する操作として Mediator に通知する。
- 背景更新は予約結果の代替通知にせず、進行中試行の採用可否を変えない。

Retries: 0
