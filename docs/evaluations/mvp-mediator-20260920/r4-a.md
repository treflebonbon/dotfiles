# Scenario A 実行メモ

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| 予約ユースケース（Model） | 在庫可否を定義し、予約の実行時にも再検証する。数量の画面表示用ルールは持たない。 |
| 予約ダイアログ Mediator | submit、close/cancel、結果採用を裁定する。現在の試行 ID、取消済みで終了待ちの試行 ID、ダイアログの表示状態を持つ。既存 binding の操作状態から表示を作る。 |
| Effect 実行境界／既存 UI binding | Mediator が受理した試行を実行し、試行 ID 付きの結果と終了通知を返す。取消要求を Fiber の中断へ接続し、Scope による資源解放を担当する。 |
| ダイアログ View と二つの Context consumer | quantity と数値形式チェック、表示、操作通知を担当する。複数 consumer は同じ Context の表示状態と event dispatcher を直接読む。兄弟 View を操作しない。 |

quantity と数値形式チェックはフォームの局所状態に残す。submit は形式が通った quantity を Mediator に通知するだけで、在庫量からの可否判定を View に追加しない。既存 binding の pending/outcome は現在試行の表示に再利用し、Mediator には全取得状態の複製ではなく `currentAttemptId`、`retiringAttemptIds`、表示中かだけを追加する。

### イベントと遷移

`attemptId` は submit を受理するたびに新規に発行する。同一 item ID は結果採用の照合キーとして不足しているため、必ず `attemptId` も照合する。

| 現在状態 | イベント | Mediator の遷移・実行 | 結果の扱い |
| --- | --- | --- | --- |
| closed | open | editing へ。フォームを表示する。 | なし |
| editing | input | フォーム局所状態だけを更新する。 | なし |
| editing | submit(quantity) | 形式が有効なら新しい `attemptId` を `currentAttemptId` にして submitting へ。実行境界へ予約を依頼する。 | 形式不正ならフォームに留まる。 |
| editing | close | closed へ。 | なし |
| submitting | stockRefresh | 状態を維持し、在庫表示だけを既存の購読更新で描画する。 | active submission は reset しない。 |
| submitting | close | 現在 ID を `retiringAttemptIds` へ移し、current を空にして closed へ。実行境界へその ID の中断を依頼する。 | 中断要求は server rollback を意味しない。 |
| closed | open → submit | 新しい ID を current にして submitting へ。取消済み試行の終了通知を待たずに再試行できる。 | 実行時の在庫再検証が競合を判定する。 |
| submitting | success/error(id) | `id === currentAttemptId` のときだけ既存 outcome を現在結果として採用し、成功なら完了表示、想定内エラーなら編集可能な結果表示へ遷移する。 | 異なる ID の成功・失敗は UI 状態を更新しない。 |
| 任意 | terminal(id, kind) | `retiringAttemptIds` の ID なら資源解放完了として除去する。 | stale な success/error、終了通知は B の表示を変更しない。 |

実行境界は成功、想定内エラー、defect、中断を別の通知として返す。Mediator は想定内エラーを利用者へ表示できる結果へ写し、defect は既存の障害通知経路へ渡す。中断は取消方針の完了として処理するが、予約済みデータを巻き戻したとは扱わない。A を取消後に B を開始した場合、A の成功・失敗・終了通知は A の解放にだけ使い、B の `currentAttemptId` と outcome を更新しない。

### 確認項目

| 確認 | 期待結果 |
| --- | --- |
| 在庫不足で submit | View は独自の在庫判定をせず、ユースケースが実行時に拒否し、その想定内エラーを表示する。 |
| A を submit → close/cancel → B を同じ item で submit → A success | B は submitting のままで、A success は採用されない。 |
| A を submit → close/cancel → B を同じ item で submit → A failure | B の outcome は A failure で上書きされない。 |
| submitting 中に stockRefresh | 在庫表示は更新されても `currentAttemptId`、pending、ダイアログ進行は維持される。 |
| submitting 中に close | ID 指定の中断と解放を依頼し、rollback 済みとは表示しない。 |
| 二つの Context consumer から submit/cancel | 同じ Mediator dispatcher に届き、両方で在庫規則や排他規則を再実装しない。 |

## 6 要件の達成

| 要件 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 在庫規則と実行時再検証を予約ユースケースだけに置き、View は形式チェックと表示だけに限定した。 |
| 2 | ○ | 予約ダイアログ Mediator を submit/cancel/結果採用の所有者に名付け、item ID ではなく試行 ID で A/B の成功・失敗を除外した。 |
| 3 | ○ | Effect 実行境界へ実行・中断・Scope の資源寿命を委譲し、想定内エラー、defect、中断、server rollback を区別した。 |
| 4 | ○ | 複数 Context consumer とフォーム局所の quantity/形式チェックを残し、転送専用コンポーネントを要求していない。 |
| 5 | ○ | 既存 binding の pending/outcome を再利用し、取消と試行識別だけを Mediator の追加状態として特定した。 |
| 6 | ○ | `stockRefresh` を submitting で状態不変とする遷移と、取消・再試行・遅延結果を含む確認表を示した。 |

## Trace

| フェーズ | 状態 | 根拠 |
| --- | --- | --- |
| Understanding | OK | Scenario A の制約、特に close=cancel、同一 item 再試行、遅延結果、background refresh を責務へ分解した。 |
| Planning | OK | 既存 operation state の再利用を先に決め、必要最小限の追加状態を試行 ID と終了待ち ID に限定した。 |
| Execution | OK | 責務マップ、遷移、受理条件、確認項目を作成した。フレームワークコードや package version は追加していない。 |
| Formatting | OK | Deliverable、各要件の判定と理由、Trace、不明点、裁量補完、retry を記録した。 |

## 不明点

### Understanding

- Issue: 既存 UI binding が試行 ID を結果と終了通知に保持できるかは Scenario A からは確定しない。
- Cause: binding の公開契約が与えられていない。
- General Fix Rule: 古い結果を除外する必要がある操作では、実行境界が opaque な operation/attempt ID と terminal 通知を返す契約を確認し、不足時だけそこで補う。

### Planning

- Issue: 取消要求直後に同一 item を再試行可能にするか、A の終了完了を待つかは指定されていない。
- Cause: 「after cancel」が取消要求時点か終了通知後かを定義していない。
- General Fix Rule: 操作開始可否は Mediator の明示的なプロダクト方針として決め、即時再試行を許すなら古い試行の解放通知を捨てず ID で照合する。

### Execution

なし。

### Formatting

なし。

## Discretionary fill-ins

- **アプリケーション方針の選択**: close で取消を要求した後は B を開始可能とした。A の予約がサーバー側で進んでいた場合も、B のユースケース実行時再検証に委ねる。これは UI の即時再試行方針であり、スキル記述の曖昧さではない。
- **アプリケーション方針の選択**: current の成功は完了表示、想定内エラーは編集可能な結果表示へ進める。成功後に自動で閉じるかは指定がないため、既存 UI の outcome 表示方針に従う。
- **命令上の不明確さ**: operation ID と terminal 通知の binding 契約が未提示である。新たな state manager や scheduler は導入せず、既存 binding の実行境界で ID を運べるかを実装前に確認する。

## Retries

0 回。要件間の矛盾や修正を要する失敗はなかった。
