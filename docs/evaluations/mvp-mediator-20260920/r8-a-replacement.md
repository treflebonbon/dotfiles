# 在庫予約画面: MVP + Mediator 責務設計

## Deliverable

### 責務の地図

| 所有者 | 責務 | 所有しないもの |
| --- | --- | --- |
| 予約ユースケース | 在庫が予約可能かという業務規則、予約開始時の在庫再検証、予約の成功または型付き業務エラー | dialog の数量書式、UI の取消・結果採用 |
| `InventoryReservationMediator` | 予約要求の受理、`attemptId` の発行、送信中の閉じる操作を取消として裁定、現在の試行だけの結果採用 | 在庫可否を再計算すること、Effect を直接実行すること |
| 既存の operation pending/outcome binding | pending と採用済み outcome の共有表示、Mediator が渡した `attemptId` 付き完了通知の配送 | 独自の `isSubmitting`、在庫 refresh による操作状態の初期化 |
| Effect 実行境界 | 受理済み予約 Effect の起動、Fiber の中断、Scope による資源解放、成功・型付き業務エラー・defect・中断の区別 | 取消をサーバー側の巻戻しとみなすこと、どの結果を UI に採用するか |
| Reservation dialog | 数量入力と数値形式の局所状態、`SubmitRequested` / `CloseRequested` の通知、pending/outcome の表示 | 在庫ポリシー、結果の世代判定 |
| 在庫パネルと予約パネル | 同じ Context から在庫表示、operation 表示、Mediator へのイベント送信口を読む | 兄弟パネルの直接操作、Context 経由の転送専用コンポーネント |

`InventoryReservationMediator` の **結果採用ハンドラ**を、成功と失敗の両方を除外する唯一の UI 所有者とする。operation binding と実行境界は完了通知に必ず `attemptId` を添え、このハンドラを通る前に shared outcome を書き換えない。

既存の operation state（pending/outcome）は保持する。追加する状態は Mediator の `activeAttemptId: AttemptId | none` と、取消済みかを表す当該試行の coordination だけである。item ID は同じ item の試行 A/B を区別できないため、`attemptId` の代わりにはならない。

### イベントと遷移

| 前状態 | イベント | Mediator の裁定・後状態 | 実行効果 |
| --- | --- | --- | --- |
| idle | `SubmitRequested(itemId, quantity)` | 新しい `attemptId=A` を発行して active(A)。既存 operation を pending として A に結び付ける | 実行境界へ予約ユースケースを A 付きで依頼する。ユースケースが開始時に在庫を再検証する |
| active(A) | `CloseRequested` | A を取消済みにして idle。A の outcome は採用しない | 実行境界へ A の Fiber の中断と解放を依頼する |
| idle（A 取消後） | `SubmitRequested(same item, quantity)` | 新しい `attemptId=B` を発行して active(B) | B を実行する。A の終了を B の開始条件にしない |
| active(B) | `OperationSucceeded(A)` | ID 不一致なので active(B) と outcome を変えない | なし |
| active(B) | `OperationFailed(A, expectedError)` | ID 不一致なので active(B) と outcome を変えない | なし |
| active(A) | `OperationSucceeded(A)` | A のみ成功 outcome を採用して idle | 既存の成功後 refresh/invalidation を起動する |
| active(A) | `OperationFailed(A, expectedError)` | A のみ型付き業務エラー outcome を採用して idle | なし |
| active(A) | `OperationInterrupted(A)` | A が取消済みなら outcome を作らず idle のまま。非取消なら中断として観測し、A 以外は変えない | Fiber 終了・Scope 解放を待つ |
| active(A) | `OperationDefected(A, cause)` | A の active を終了し、defect を既存の障害通知境界へ渡す。業務エラー outcome に変換しない | defect を記録・報告し、資源を解放する |
| idle / active(A) | `StockRefreshed(stock)` | 在庫表示を更新するだけ。activeAttemptId、pending、outcome を変更しない | 既存の refresh 購読に任せる |

`CloseRequested` の「取消」は UI が結果を採用しないことと Effect の中断要求を意味する。通信済みの予約をサーバー側で必ず巻き戻す約束ではない。再度の予約は B として開始でき、後着した A の成功・型付き失敗・defect・中断はすべて A の世代として扱う。

### 実行境界の契約

1. Mediator が受理した試行だけを既存の application/runtime 境界で実行する。View は runtime や cancel flag を作らない。
2. 実行境界は A の Fiber を A の所有期間に結び付け、取消時に中断し、Scope で資源を解放する。Scope を閉じれば任意の実行も中断されるとは仮定しない。
3. 型付きの在庫不足などは `OperationFailed(A, expectedError)`、予期しない defect は `OperationDefected(A, cause)`、中断は `OperationInterrupted(A)` として区別する。いずれも結果採用ハンドラが `activeAttemptId` と照合する。
4. `StockRefreshed` は読み取りモデルの通知であり、operation binding の pending/outcome や attempt coordination を書き換える経路を持たない。

### 具体的な確認

| 確認 | 操作 | 期待結果 |
| --- | --- | --- |
| 実行時在庫検証 | 表示在庫が残っていても、送信直前に在庫を消費させて送信する | UI は独自に許可判定せず、ユースケースが型付き在庫不足を返す |
| 取消後の同一 item 再送 | A を送信、dialog を閉じ、同じ item を B として送信する | B は pending になり、A の成功も型付き失敗も B の pending/outcome を変えない |
| 遅延失敗 | 前項の後で A の expected failure を到着させる | B の状態・表示・成功後処理は変わらない |
| 遅延成功 | 前項の後で A の success を到着させる | B の状態・表示・成功後処理は変わらない |
| refresh 中の送信 | A が pending の間に background stock refresh を到着させる | 在庫表示だけ更新され、A の pending、activeAttemptId、採用待ち結果は維持される |
| Context の複数購読 | 在庫パネルと予約パネルが同じ Context を購読し、dialog では数量書式を変更する | どちらも同じ Mediator のイベント送信口を使い、数量書式は dialog 内に留まり、転送用 component は不要 |
| 中断と defect | A を閉じて中断し、別ケースで defect を発生させる | 中断を業務失敗に偽装せず、defect は障害境界へ渡る。どちらも後続 B を上書きしない |

## 六つの達成状況

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 在庫ポリシーと送信開始時の再検証を予約ユースケースだけに置いた。UI は表示と結果表示のみを行う。 |
| 2 | ○ | `InventoryReservationMediator` の結果採用ハンドラを明記し、`attemptId` 照合で同一 item の古い成功・失敗をともに除外した。 |
| 3 | ○ | 実行・Fiber 中断・Scope 解放を実行境界へ委譲し、型付き業務エラー、defect、中断を分離した。取消を rollback と約束していない。 |
| 4 | ○ | 両パネルの Context 購読と dialog の数量書式を許容し、判断を重複させず mandatory forwarding を置いていない。 |
| 5 | ○ | 既存 operation pending/outcome binding を継続使用し、追加を attempt/cancel coordination に限定した。 |
| 6 | ○ | 再検証、取消→再送、古い成功・失敗、送信中 refresh、Context、defect/interruption の具体的確認を列挙した。 |

## Trace（四段階）

| 段階 | 状態 | 記録 |
| --- | --- | --- |
| 1. 状態を分ける | OK | 読み取り在庫 refresh と operation pending/outcome、active attempt を分離した。 |
| 2. 要求と実行を分ける | OK | Mediator が要求を受理・取消し、実行境界が Effect を実行・中断・解放する。 |
| 3. 各待機状態から再生する | OK | active(A) から close、B の再送、A の遅延成功・失敗、refresh を遷移表で追った。 |
| 4. 境界で検証する | OK | ユースケース再検証、attemptId による採用、Effect の終了種別、refresh 非干渉を確認項目にした。 |

## Unclear

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 operation binding が完了時に無条件で shared outcome を更新する場合、Mediator の照合より先に A が B を上書きする | outcome の書込み経路が試行の世代を持たない | shared outcome を更新する唯一の入口を `attemptId` 付き結果採用ハンドラにし、世代不一致の通知は捨てる。 |
| close 後のサーバー予約の扱いが未定義 | UI の中断と業務上の取消を同一視している | UI 取消の契約を「結果不採用＋実行中断要求」に限定し、サーバー取消が必要なら別ユースケースとして明示する。 |

## 裁量で補った点

- operation binding が attemptId を完了通知に保持できることを前提にした。保持できない場合は、既存 binding の完了イベントへ ID を通す最小の coordination を追加する。
- 背景 refresh は読み取り在庫だけを更新するものとして扱った。予約成功後の refresh/invalidation は既存の機構へ接続する。

## retries

0 回。設計対象の既存コード、評価履歴、利用状況は参照していない。
