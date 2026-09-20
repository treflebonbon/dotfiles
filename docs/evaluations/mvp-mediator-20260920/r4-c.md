# Scenario C: デバイス排他フローの architecture memo

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| Root | `DeviceCoordinatorMediator`、録画 Mediator、較正 Mediator、プロフィール Mediator と各 View を組み立てる。全 UI イベントを集約しない。 |
| `DeviceCoordinatorMediator`（共通親） | デバイス所有者（なし／録画／較正）、切替待ち、開始要求の採用、停止・解放失敗時の遷移を唯一裁定する。子からの開始・停止完了・解放完了・失敗通知を受ける。 |
| 録画 Mediator | 録画画面の表示状態、録画固有の入力、録画中の局所表示を扱う。開始・他フローへの切替・デバイス取得／解放を親へ要求する。 |
| 較正 Mediator | 較正画面の表示状態、較正手順の局所状態を扱う。開始・他フローへの切替・デバイス取得／解放を親へ要求する。 |
| プロフィール Mediator と View | プロフィール編集の入力、保存、表示を独立して扱う。デバイス所有状態は読まず、親の排他裁定にも参加しない。 |
| Model／ユースケース | 録画・較正・プロフィールの業務規則と実行時検証を所有する。UI の排他判断は持たない。 |
| Effect 実行層 | 親が受理した停止、解放、取得、開始を実行し、成功、型付きの想定内失敗、defect、中断を区別して親へ通知する。親の方針に従い Fiber の中断と Scope による資源解放を結び付ける。 |
| View | 表示し、担当 Mediator にイベントを通知する。録画 View が較正を止めたり、較正 View が録画を解放したりしない。 |

### 親 Mediator の状態・イベント・遷移

`pending` は切替を待つ最新の利用者要求であり、実行中の停止・解放の識別子とは別に保持する。反復要求の方針は **latest-wins** とする。同じ待機中に来た開始要求は `pending` を最後の要求へ置換する。ただし、すでに開始した停止・解放は置換で無効化せず、終了通知を必ず照合して処理する。

| 現在状態 | イベント | 親の裁定と実行 | 次状態 |
| --- | --- | --- | --- |
| `Idle` | `Start(recording)` | 録画用デバイス取得を実行する。 | `Acquiring(recording)` |
| `Idle` | `Start(calibration)` | 較正用デバイス取得を実行する。 | `Acquiring(calibration)` |
| `Acquiring(x)` | `AcquireSucceeded(x, operationId)` | 識別子が一致するときだけ `x` の開始を実行する。 | `Starting(x)` |
| `Acquiring(x)` | 取得失敗／defect／中断 | 失敗を `x` の表示状態へ変換し、所有者を残さない。 | `Idle` |
| `Starting(x)` | `Started(x, operationId)` | 識別子が一致すれば `x` を現在の所有者にする。 | `Owned(x)` |
| `Owned(x)` | `Start(x)` | すでに所有中なので子の局所処理へ委ね、再取得しない。 | `Owned(x)` |
| `Owned(x)` | `Start(y)`（`y != x`） | `pending = y` を記録し、`x` の停止を実行する。 | `Stopping(x, pending=y)` |
| `Stopping(x, pending=y)` | `Start(z)` | `pending = z` に更新する。停止中の実行識別子は保持する。 | `Stopping(x, pending=z)` |
| `Stopping(x, pending=y)` | `StopSucceeded(x, operationId)` | 識別子が一致すれば `x` のデバイス解放を実行する。 | `Releasing(x, pending=y)` |
| `Stopping(x, pending=y)` | 停止失敗／defect／中断 | `y` を開始せず、失敗を `x` に表示する。必要なら回復操作を待つ。 | `Owned(x)` または `StopFailed(x, pending=y)` |
| `Releasing(x, pending=y)` | `Start(z)` | `pending = z` に更新する。解放中の実行識別子は保持する。 | `Releasing(x, pending=z)` |
| `Releasing(x, pending=y)` | `ReleaseSucceeded(x, operationId)` | 識別子が一致すれば、最新の `pending` の取得を実行する。 | `Acquiring(y)` |
| `Releasing(x, pending=y)` | 解放失敗／defect／中断 | `y` を開始しない。デバイス所有が不明または残存し得るため、失敗を `x` に表示し、明示的な回復・再試行だけを受ける。 | `ReleaseFailed(x, pending=y)` |
| `StopFailed(x, pending=y)` | `RetryStop(x)` | `x` の停止を改めて実行する。 | `Stopping(x, pending=y)` |
| `ReleaseFailed(x, pending=y)` | `RetryRelease(x)` | `x` の解放を改めて実行する。 | `Releasing(x, pending=y)` |

操作完了通知は対象フローと `operationId` の両方で照合する。古い停止、解放、取得、開始の成功・失敗は現在の状態を上書きしない。ただし、実行層は古い実行に属する資源の解放・終了通知を失わない。

### 実行方針

親 Mediator が許可した遷移だけを Effect 実行層へ渡す。停止の受理後に新フローを開始せず、停止成功の後に解放成功まで待ってから次の取得を開始する。停止または解放が失敗した場合は、待機していたフローを開始しない。

Effect の既存の実行・寿命管理を使い、親の切替方針に必要な中断と資源解放を委譲する。Scope を閉じた事実だけで停止済み・デバイス解放済みとは見なさず、実行層からの `StopSucceeded` と `ReleaseSucceeded` を待つ。親と別にキュー、キャンセルフラグ、scheduler を作らない。

### 確認項目

| 確認シナリオ | 期待結果 |
| --- | --- |
| 録画中に較正開始 | 親が録画停止を一度だけ実行し、停止成功後に解放を実行する。解放成功の後にだけ較正の取得・開始を実行する。2 フローは同時にデバイスを所有しない。 |
| 録画停止が失敗 | 較正は開始されない。録画側に失敗が表示され、親は `RetryStop` まで所有状態または失敗状態を保つ。 |
| 録画解放が失敗 | 較正は開始されない。解放失敗を表示し、再試行以外で次フローの取得をしない。 |
| 停止待ちに較正開始、次に録画開始 | 最後の録画要求が `pending` となる。進行中の録画停止・解放の完了を処理した後、録画を再開するかは親が同一所有要求として局所処理へ委ねる。不要な較正取得は起きない。 |
| 解放待ちに録画・較正・録画開始 | 最後の録画要求だけを採用する。解放成功後の取得は一度だけで、古い通知は `operationId` 照合で無視する。 |
| プロフィール編集を録画・較正の切替中に操作 | プロフィールの編集・保存は継続し、デバイス親の状態遷移は変化しない。 |

## Achievement

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 共通親がデバイス排他を所有し、子と View の直接的な兄弟停止を排除した。 |
| 2 | ○ | 停止待ち、停止成功、解放待ち、解放成功を別遷移にし、停止・解放失敗では次フローを開始しない。 |
| 3 | ○ | pending を latest-wins と明示し、親を唯一の採用者にした。 |
| 4 | ○ | プロフィールを独立 Mediator／View とし、Root と親へ全 UI イベントを集約しない。 |
| 5 | ○ | Effect 実行・寿命管理を既存機構へ委譲し、Scope 閉鎖だけを中断・解放の証拠にせず、自作 scheduler を置かなかった。 |
| 6 | ○ | 切替、停止失敗、解放失敗、反復要求、独立プロフィールを具体的な確認項目にした。 |

## Trace

| フェーズ | 判定 | 内容 |
| --- | --- | --- |
| Understanding | OK | 要求された排他、停止・解放待ち、反復要求、独立フローを特定した。 |
| Planning | OK | 共通親と子の責務を分離し、親の状態遷移と照合識別子を先に定めた。 |
| Execution | OK | 責務マップ、状態遷移、実行方針、確認項目を作成した。 |
| Formatting | OK | 指定された評価記録の構成で Markdown に整形した。 |

## Unclear points

なし。アプリケーション方針として、反復開始要求は latest-wins を選んだ。この選択はシナリオが求める一貫した方針を具体化したものであり、スキル指示の曖昧さではない。実際の製品で FIFO や reject が必要なら、親 Mediator の `pending` 採用規則だけを置き換える。

## Discretionary fill-ins

- `operationId` を停止・解放・取得・開始に使い、遅延通知が現行遷移へ混入しないようにした。
- 解放失敗時は所有が不明または残存し得るため、次の取得を禁止する回復状態を置いた。

## Retries

0 回。理由: 指示範囲内の読み取りと memo 作成で完了した。
