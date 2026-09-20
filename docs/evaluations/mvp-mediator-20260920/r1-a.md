# Scenario A 実行レポート

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| Root | 在庫画面と共有 Context を組み立てる。2 パネルへの表示状態とイベント入口の共有を許すが、転送専用コンポーネントは増やさない。 |
| 予約ダイアログ Mediator | `submit`、送信中の `close`（取消）、結果採用、再送信を裁定する。各受理済み送信に `attemptId` を割り当て、現在の有効試行を一つだけ保持する。 |
| Passive View（ダイアログ） | 数量入力値と数値形式エラー、ツールチップ等の局所表示を保持し、形式検証済みの送信要求と close 要求を Mediator へ通知する。表示用の在庫可否を再判定しない。 |
| 予約ユースケース（Model） | 利用可能在庫の業務規則を所有し、実行時にも在庫を再検証して予約を成功または想定内の業務エラーで返す。React／Context には依存しない。 |
| Effect 実行境界と既存 UI バインディング | Mediator が受理した試行を実行し、`attemptId` 付きの成功・想定内エラー・defect・中断を返す。Fiber の中断と Scope による解放を既存の寿命管理へ接続し、既存の operation の pending/outcome 表示状態を供給する。 |
| 在庫の背景更新 | 既存の取得・キャッシュ更新機構で在庫表示を更新する。予約 Mediator の有効試行や取消状態は更新しない。 |

同じ `attemptId` を実行開始から通知まで保持する。既存 UI バインディングが試行単位で古い結果を除外できるならその仕組みを使い、できない部分だけ Mediator の結果採用ゲートで照合する。追加する状態は全取得状態の複製ではなく、`activeAttemptId` と取消済み試行の無効化、および必要な中断ハンドルの対応だけである。

### イベントと遷移

| 現在状態 | イベント | Mediator の裁定と次状態 |
| --- | --- | --- |
| Closed | `open` | Editing。 |
| Editing | `quantityChanged` | View の局所入力値・数値形式だけを更新。 |
| Editing | `submitRequested(quantity)` | 形式不正なら View の形式エラーを表示して Editing 継続。形式正なら新しい `attemptId=A` を発行し、`activeAttemptId=A` にして Submitting(A)。実行境界へ予約を依頼する。 |
| Submitting(A) | `closeRequested` | 取消を裁定する。まず A を無効化して Closed にし、実行境界へ A の中断と関連リソース解放を依頼する。中断はサーバー予約のロールバックを意味しない。 |
| Closed | `open`、`submitRequested(quantity)` | 新しい `attemptId=B` を発行して Submitting(B)。取消処理中の A は B の開始を妨げない。 |
| Submitting(X) | `succeeded(X, result)` | `X === activeAttemptId` の場合だけ成功を既存 operation outcome として採用し、`activeAttemptId` を解除して Editing（または画面で定めた完了表示）へ進める。不一致なら無視する。 |
| Submitting(X) | `expectedFailed(X, domainError)` | ID 一致時だけ業務エラーを表示用結果へ変換し Editing へ戻る。不一致なら無視する。 |
| Submitting(X) | `defected(X, defect)` | ID 一致時だけ defect として既存の障害通知・記録へ渡し、想定内業務エラーには変換しない。不一致なら無視する。 |
| Submitting(X) | `interrupted(X)` | ID 一致かつ取消裁定外なら中断として扱う。取消済みまたは不一致なら表示結果を変更しない。 |
| 任意 | `stockRefreshed` | 在庫表示の再描画のみ。`activeAttemptId`、状態、結果採用条件は変えない。 |

結果採用は、現在が `Submitting(X)` かつ ID が一致する場合に限る。従って A を取消して B を開始した後に到着する A の成功・想定内失敗・defect・中断のいずれも、B の pending/outcome や画面状態を上書きできない。

### 確認項目

| 確認シナリオ | 期待結果 |
| --- | --- |
| 在庫が不足した状態で送信 | ユースケースが実行時に拒否する。View はその業務エラーを表示するだけで独自の在庫規則を持たない。 |
| 数量に文字列や不正形式を入力 | View が送信前の形式エラーを表示し、実行を開始しない。 |
| A を送信中に閉じる | Mediator が A を無効化して中断を依頼し、ダイアログを閉じる。サーバー側の予約取消を成功と推定しない。 |
| A の取消直後に同一商品を B として送信 | B は Submitting(B) になる。遅延した A の成功と失敗の両方が B の表示を変更しない。 |
| B の想定内業務エラー | B のみが Editing の表示用 outcome へ反映される。defect や中断と同じエラー表示に潰れない。 |
| B の defect または非取消の中断 | 既存の障害／中断の扱いへ区別して渡し、業務エラーや成功として採用しない。 |
| A または B の送信中に背景在庫更新 | 在庫表示は更新されるが、該当試行の pending、`activeAttemptId`、取消・結果採用条件は変わらない。 |
| 2 パネルが共有 Context を購読 | 両方が同じ Mediator の表示状態とイベント入口を使用でき、兄弟 View の直接操作や必須の転送層はない。 |

## Requirement achievement

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 在庫規則と実行時再検証を予約ユースケースに置き、View は形式検証と表示だけに限定した。 |
| 2 | ○ | 予約ダイアログ Mediator を命名し、現在の `attemptId` 一致を結果採用条件にしたため、旧 A の成功・失敗は新 B を上書きできない。 |
| 3 | ○ | Effect 実行境界へ実行・Fiber 中断・Scope 解放を委譲し、想定内エラー、defect、中断を別イベントにした。中断をサーバーロールバックと扱っていない。 |
| 4 | ○ | 共有 Context の複数購読と View 内の数量／形式状態を維持し、転送専用コンポーネントを要求していない。 |
| 5 | ○ | 既存 operation の pending/outcome を再利用し、追加状態を有効試行 ID、取消無効化、中断対応に限定した。 |
| 6 | ○ | 背景更新中の送信、取消後の再送信、遅延結果を含む具体的なイベント遷移と確認を示した。 |

## Trace

| フェーズ | 状態 | 内容 |
| --- | --- | --- |
| Understanding | OK | Scenario A の制約と、React／Effect 向け参照の適用条件を確認した。 |
| Planning | OK | 既存 operation 状態の再利用を前提に、試行 ID と結果採用ゲートだけを追加責務とした。 |
| Execution | OK | 責務マップ、遷移、確認項目を作成した。 |
| Formatting | OK | 指定された自己報告項目を日本語 Markdown にまとめた。 |

## Unclear points

なし。既存 UI バインディングが試行 ID による古い結果除外を持つかは実装時に確認すべき事実であり、指示の曖昧さではない。その有無に応じて既存機構を使うか Mediator の採用ゲートを接続するのは通常の適用方針である。

## Discretionary fill-ins

- `attemptId` は Mediator が送信受理時に発行し、実行境界が全結果通知に付与する。
- 取消は UI フロー上の A の無効化を即時に行う。物理的な中断・解放の完了を B の開始条件にしない。
- 成功後の最終表示（Editing 継続か完了表示）は画面要件に委ねた。どちらでも結果採用ゲートと業務規則の所有者は変わらない。

## Retries

0 回。Scenario A の見出し表記が指定文字列と完全一致しなかったため、見出し一覧だけを確認して `Scenario A` から `Scenario B` 直前までを抽出した。内容の再実行はしていない。
