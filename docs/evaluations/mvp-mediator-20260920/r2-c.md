# Scenario C: 排他的なデバイスフロー

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| `DeviceFlowsMediator`（共通の親） | 録画と較正の同時所有を禁止する。開始要求、停止、解放完了、失敗を裁定し、切替中の最新要求を 1 件保持する。子に取得開始を許可するのは、現在の所有者が正常に解放された後だけとする。 |
| `RecordingMediator` | 録画 UI の表示、開始・停止要求、録画固有の進行表示を扱う。親の許可後にのみ録画取得を実行層へ依頼し、結果を親へ通知する。 |
| `CalibrationMediator` | 較正 UI の表示、開始・停止要求、較正固有の進行表示を扱う。親の許可後にのみカメラ取得を実行層へ依頼し、結果を親へ通知する。 |
| 実行層 | Effect の実行・Fiber の管理・Scope による資源寿命管理を行う。親の方針に従って停止と解放を実行し、成功・失敗・終了を識別子付きで返す。Scope の close だけを中断完了の証明にはしない。 |
| Passive View | 状態を表示し、`startRecording`、`startCalibration`、`stop` を担当 Mediator に通知する。兄弟 View や他方の実行を直接止めない。 |
| `ProfileMediator` と Profile View | プロフィール編集の入力・保存を独立して扱う。デバイス所有と関係しないため `DeviceFlowsMediator` には送らない。 |

### 親 Mediator の状態遷移

`owner` は `none | recording | calibration`、`pending` は `none | recording | calibration` とする。`runId` は各取得・停止・解放の完了通知を照合するための識別子である。切替中の開始要求は **最新要求を 1 件だけ採用**する。現在の所有者への開始要求は無視し、同じ切替先の再要求も状態を変えない。

| 現在状態 | イベント | 親の裁定と次状態 |
| --- | --- | --- |
| `Idle(owner=none)` | `Start(x)` | `x` の取得を子と実行層へ許可し、`Acquiring(owner=x, runId)`。 |
| `Acquiring(x)` | `AcquireSucceeded(runId)` | `Active(owner=x)`。 |
| `Acquiring(x)` | `AcquireFailed(runId)` | `Idle(owner=none)`。 |
| `Active(owner=x)` | `Start(y)`、`y ≠ x` | `pending=y` を記録し、`Stopping(owner=x, runId)`。実行層へ停止・解放を一度だけ依頼する。 |
| `Active(owner=x)` | `Stop` | `pending=none` として `Stopping(owner=x, runId)`。 |
| `Stopping(owner=x, pending=p)` | `Start(y)` | `pending=y` に置換する。ただし停止・解放の実行は再発行しない。 |
| `Stopping(owner=x, pending=p)` | `Stop` | `pending=none`。停止・解放の完了を待つ。 |
| `Stopping(owner=x, pending=p)` | `Released(runId)` | `p=none` なら `Idle`。`p=y` なら `Acquiring(owner=y, newRunId)` に遷移して初めて `y` の取得を許可する。 |
| `Stopping(owner=x, pending=p)` | `StopFailed(runId)` または `ReleaseFailed(runId)` | `Active(owner=x)` 相当の失敗表示へ戻す。`pending` を破棄し、他方の取得は開始しない。利用者は明示的に再試行または停止を選ぶ。 |

`runId` が一致しない遅延通知は表示結果を更新せず、実行層は必要な資源解放を継続する。これにより、古い停止や取得の結果が新しい要求を上書きしない。

### 実行・検証メモ

親が許可した遷移だけから Effect 実行を開始する。実行層は親が指定した `runId` ごとに取得、停止、解放の寿命を管理し、停止要求後も `Released(runId)` を返すまで次の取得を開始しない。中断要求や Scope の終了は、実際の停止・解放成功通知の代わりに使わない。既存の Effect の Fiber／Scope／中断機構を使用し、親 Mediator とは別のキューやスケジューラを作らない。

確認項目:

1. 録画中に較正を開始すると、録画の停止・解放成功までは較正の取得が実行されず、成功後に一度だけ開始される。
2. 録画の停止または解放が失敗すると、較正は開始されず、失敗表示と明示的な再試行経路が残る。
3. 録画停止待ちの間に較正開始、続けて録画開始を要求すると、最新要求である録画開始だけが採用され、解放後は録画の取得だけが開始される。
4. 較正への切替待ちに `Stop` を送ると、待機要求が消え、解放後は `Idle` になる。
5. プロフィール編集の開始・保存は、録画・較正の状態や待機要求を変えない。

## Requirement achievement

1. ○ 共通親 `DeviceFlowsMediator` が排他を裁定し、各子は局所フローだけを持つ。View が兄弟を直接停止する経路はない。
2. ○ `Stopping` と `Released` を分け、停止・解放の成功後だけ次の取得を許可する。停止・解放失敗時は他方を開始しない。
3. ○ 切替中は最新の開始要求 1 件を採用する方針を明記し、その所有者を親に固定した。
4. ○ プロフィール用 Mediator を独立させ、デバイス外のイベントを親へ集約しない。
5. ○ Effect の実行・Fiber・Scope を実行層に委ね、Scope 終了を中断・解放成功の証明にせず、並行スケジューラも追加しない。
6. ○ 切替、停止・解放失敗、反復要求、待機取消、独立プロフィールを確認する具体的なチェックを示した。

## Trace

- Understanding: OK
- Planning: OK
- Execution: OK
- Formatting: OK

## Unclear points

なし。

## Discretionary fill-ins

- 反復要求の方針として「最新要求を 1 件採用」を選んだ。これは Scenario が要求する一貫した方針の具体化であり、スキルの必須規則の曖昧さではない。
- 停止・解放失敗後は、待機していた切替を自動再開せず破棄する。失敗した所有状態が残る状況で別フローを開始しないための UI 方針である。

## Retries

0。理由: なし。
