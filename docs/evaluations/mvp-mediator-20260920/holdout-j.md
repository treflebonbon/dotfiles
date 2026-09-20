# Holdout J アーキテクチャメモ

## Deliverable

2 枚のアップロードカードを、それぞれ独立した `Card Mediator` と既存のカード単位 operation binding で構成する。Root は 2 カードを配置し、共有 transport の Effect 依存を既存の Service／Layer から渡すだけで、同時実行数・取消・結果採用を裁定しない。

各 Card Mediator は `submit(file)`、`cancel`、実行境界から戻る `succeeded`／`expectedFailed`／`defected`／`interrupted` を扱う。送信を受理するたびに、そのカード内で一意な attempt ID を発行し、操作 ID を `{ cardId, attemptId }` とする。現在の操作 ID に一致する完了だけを既存 binding の pending/result 表示へ採用する。取消後に同じファイルを再送しても、先行試行の遅延した成功・失敗は表示を更新しない。ただし先行試行の終了通知は実行層が Fiber／Scope の解放に使うため処理する。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| idle／result | submit(file) | uploading(current ID) | 当該カードの既存 binding／実行層 | use case を Effect として開始 |
| uploading(A) | cancel | cancelled(A) | 実行層 | A の中断と解放を要求。リモートの巻戻しは仮定しない |
| cancelled(A) | submit(same file) | uploading(B) | 当該カードの既存 binding／実行層 | B を開始。A の完了待ちを全体の開始条件にしない |
| uploading(B) | B の succeeded／expectedFailed | result／error(B) | なし | B の結果だけを採用 |
| uploading(B) | A の succeeded／expectedFailed | uploading(B) | 実行層 | 表示結果を破棄し、A の終了・解放だけを完了 |
| uploading(A) | defected／interrupted | 観測通知／cancelled(A) | 実行層 | defect は期待エラーへ変換せず観測へ渡す。中断は取消として扱う |

View は binding が公開する pending/result と Card Mediator のイベント送信口を受ける。ファイル名整形とヘルプ tooltip の開閉は View の局所状態に置き、他カードやアップロード進行を変えない。ファイルの受理可否は View で再実装せず、upload use case が実行時に検証して型付きの想定内エラーとして返す。Effect の実行・依存解決・Fiber／Scope の寿命は既存の共有機構を使い、各 View の runtime、自作 scheduler、完全な fetch-state モデルを追加しない。

## 凍結チェックリスト

1. ○ 各カードに Card Mediator を 1 つ置き、submit／cancel／結果採用をそのカードだけで裁定する。共有 transport は依存の共有であり、Root に排他状態を置かないため、片方の取消は他方へ届かない。
2. ○ 操作 ID を `{ cardId, attemptId }` とし、current ID の完全一致でのみ結果を採用する。同一ファイルでも A と B は異なる attempt ID なので、A の遅延した成功・失敗は B を上書きできない。
3. ○ ファイル受理の業務規則と実行時検証は upload use case が所有する。ファイル名整形と tooltip は局所表示であり、Card Mediator や use case へ移さない。
4. ○ カード単位 binding の pending/result と共有 Effect 実行・依存・寿命管理を再利用する。必要な追加はカード内の current 操作 ID と結果照合だけで、scheduler と二重の取得状態は作らない。
5. ○ 想定内の業務エラーは型付きエラーとして現在試行に表示し、defect は観測・障害経路へ分け、中断は実行の停止と資源解放として扱う。中断だけでサーバー側アップロードの取消・巻戻しは保証しない。
6. ○ 以下の確認で同時実行、片方だけの取消、再試行後の stale 成功・失敗を検証する。

## 確認項目

| シナリオ | 操作 | 期待結果 |
| --- | --- | --- |
| 同時アップロード | 左右のカードで別ファイルを送信する | 2 枚とも pending となり、共有 transport を使って並行に完了できる。Root に排他や相互取消は発生しない。 |
| 片方の取消 | 左 A を送信し、右 B を送信中のまま左だけ cancel する | 左は A の中断・解放を要求して cancelled になり、右 B は pending のまま完了できる。 |
| stale 成功 | 左 A を送信、cancel、同じファイルで左 B を再送し、その後 A 成功を到着させる | 左の表示は B の pending/result のまま変わらず、A は解放だけ完了する。 |
| stale 失敗 | 上記と同じ手順で A の想定内失敗を到着させる | 左の表示は B の pending/result のまま変わらず、A の失敗は B のエラーとして表示されない。 |

## Trace

- Understanding: OK — 共有 transport は排他要件を生まず、カード／試行境界が stale 結果の照合単位である。
- Planning: OK — 既存 binding と Effect 実行境界を保持し、カード内の裁定と操作 ID のみを明示した。
- Execution: OK — 責務、イベント、状態遷移、結果採用、検証シナリオを具体化した。
- Formatting: OK — フレームワーク API バージョンとアプリケーションコードを含めていない。

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 binding が完了結果の操作 ID を公開しているか未確認 | 問題文は pending/result の公開だけを明示する | binding または実行境界で `{ cardId, attemptId }` を完了通知と結び、現行 ID との照合を可能にする。ファイル名や対象 ID だけを照合キーにしない。 |

## Discretionary fill-ins

- Card Mediator はカードごとのフローなので、独立アップロードのための共通親 Mediator は追加しない。
- stale 結果を表示に採用しなくても、実行層の終了・解放通知は失わない。

## Retries

0
