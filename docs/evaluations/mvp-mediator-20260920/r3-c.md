# Scenario C 実行メモ

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| `DeviceFlowMediator`（共通の親） | 録画とキャリブレーションの排他、開始要求の採用、停止・解放・取得の順序、失敗時の遷移、実行中操作の識別子の照合を裁定する。 |
| `RecordingMediator` | 録画 View の表示状態と、録画開始・停止の意図を親へ通知する。兄弟を停止しない。 |
| `CalibrationMediator` | キャリブレーション View の表示状態と、開始・停止の意図を親へ通知する。兄弟を停止しない。 |
| 実行層 | 親の裁定に従い、停止、デバイス解放、取得を実行して結果イベントを親へ返す。Effect の Fiber と Scope で実行と寿命を管理する。 |
| `ProfileMediator` | プロフィール編集の状態と操作を独立して裁定する。`DeviceFlowMediator` には通知しない。 |
| Passive View | 表示と利用者操作の通知だけを行う。録画 View からキャリブレーションを直接停止するような接続は持たない。 |

業務上のデバイス利用可否は Model／ユースケースが実行時にも検証する。親はその結果と UI の進行状態を使って、次の操作を許可する。

### 状態とイベント

親の状態は `Idle`、`Owned(recording | calibration, leaseId)`、`Draining(owner, drainId, desired)`、`DrainFailed(owner, desired, drainId, error)`、`Acquiring(target, acquireId)`、`AcquireFailed(target, error)` とする。`desired` は `recording`、`calibration`、または停止のみの `none` である。

| 現在状態 | イベント | 親の裁定と次状態 | 実行 |
| --- | --- | --- | --- |
| `Idle` | `Start(target)` | `Acquiring(target, acquireId)` | target の取得を開始する。 |
| `Owned(owner)` | `Start(owner)` | 状態を維持 | すでに所有中なので何もしない。 |
| `Owned(owner)` | `Start(other)` | `Draining(owner, drainId, desired=other)` | owner の停止と解放を順に開始する。 |
| `Owned(owner)` | `Stop(owner)` | `Draining(owner, drainId, desired=none)` | owner の停止と解放を順に開始する。 |
| `Draining(owner, drainId, desired)` | `Start(target)` | 同じ `drainId` のまま `desired=target` に更新 | 進行中の停止・解放は中断・再実行しない。 |
| `Draining(owner, drainId, desired)` | `Stop(owner)` | 同じ `drainId` のまま `desired=none` に更新 | 解放完了後は `Idle` にする。 |
| `Draining(owner, drainId, desired)` | `Released(drainId)` | desired が target なら `Acquiring(target, acquireId)`、`none` なら `Idle` | 成功した解放を確認した後にだけ target を取得する。 |
| `Draining(owner, drainId, desired)` | `StopOrReleaseFailed(drainId, error)` | `DrainFailed(owner, desired, drainId, error)` | 次の取得を開始しない。 |
| `DrainFailed(owner, desired, drainId, error)` | `RetryShutdown` | 新しい `Draining(owner, newDrainId, desired)` | 明示的な再試行として停止・解放をやり直す。 |
| `DrainFailed(owner, desired, drainId, error)` | `Start(target)` / `Stop(owner)` | `desired` を最後の要求へ更新、失敗状態を維持 | 先に解放が成功するまで取得しない。 |
| `Acquiring(target, acquireId)` | `Acquired(acquireId, leaseId)` | `Owned(target, leaseId)` | なし。 |
| `Acquiring(target, acquireId)` | `AcquireFailed(acquireId, error)` | `AcquireFailed(target, error)` | なし。 |
| 任意 | 識別子が一致しない完了イベント | 状態を維持 | 古い結果を表示状態に採用しない。必要な実行層の解放は結果を捨てる前に完了させる。 |

反復した `Start` は親が採用する**最後の要求を優先**する。たとえば録画からキャリブレーションへの切替中に録画開始が来た場合、停止・解放は完了まで継続し、解放成功後に録画を再取得する。これは停止を取り消したように見せたり、完了通知を失ったりしないためである。同じ target の重複要求は `desired` を変えず、追加の停止・解放を開始しない。

### 実行と寿命管理

`DeviceFlowMediator` が遷移を裁定してから、実行層に Effect を起動させる。切替時の Effect は「現在 owner を停止する → デバイスを解放する → `Released(drainId)` を送る」の順で実行する。停止または解放で失敗した場合は `StopOrReleaseFailed(drainId, error)` を送る。`Released` を受け取るまでは、別フローの取得 Effect を作らない。

実行層は Fiber と Scope を使って実行の開始、購読解除、資源解放を管理する。Scope を閉じた事実だけを「停止済み」「解放済み」の証拠にせず、デバイス操作からの成功結果を親へ返す。`drainId` と `acquireId` は、待機中の要求が更新されても、実行済みの停止・解放の完了通知を処理するために保持する。独自のスケジューラや並行制御機構は作らない。

### 検証メモ

| 検証 | 操作 | 期待結果 |
| --- | --- | --- |
| 切替 | 録画中にキャリブレーション開始を要求し、停止・解放を成功させる | `Owned(recording)` → `Draining(recording, desired=calibration)` → `Acquiring(calibration)` → `Owned(calibration)`。取得は `Released` の後に 1 回だけ始まる。 |
| 停止・解放失敗 | 録画中にキャリブレーション開始を要求し、停止または解放を失敗させる | `DrainFailed` になり、キャリブレーションの取得は開始されない。`RetryShutdown` の成功後にのみ要求済み target を取得する。 |
| 反復要求 | 上記の `Draining` 中に calibration、recording、calibration の順で開始を要求する | 停止・解放は 1 回のまま継続し、最後の `calibration` だけを `Released` 後に取得する。 |
| 独立性 | デバイス切替中にプロフィールを編集する | `ProfileMediator` の状態遷移は継続し、デバイス親の状態は変わらない。 |
| 遅延完了 | 古い `drainId` または `acquireId` の完了を返す | 親は現在の状態を上書きしない。 |

## 要件達成

| 要件 | 達成 | 根拠 |
| --- | --- | --- |
| 1. 共通親がデバイス排他を所有し、子と View の境界を守る | ○ | `DeviceFlowMediator` が切替を裁定し、各子は自身の意図と表示だけを扱う。 |
| 2. 保留中の停止・成功した解放を経て取得し、失敗時に他方を始めない | ○ | `Draining`、`Released`、`DrainFailed` の遷移が順序と停止条件を定める。 |
| 3. 反復要求に一貫した方針と単一所有者がある | ○ | 親が最後の要求を `desired` として採用し、解放中の実行は 1 回に保つ。 |
| 4. 独立したプロフィールを全体へ集約しない | ○ | `ProfileMediator` を独立したフローとして定義した。 |
| 5. 親の方針の下で Effect の実行・寿命管理を使い、Scope 閉鎖だけに依存しない | ○ | Fiber／Scope を実行層へ委譲し、明示的な `Released` 成功イベントを取得の前提にした。 |
| 6. 切替、失敗、反復要求を具体的に確認する | ○ | 検証メモにそれぞれの操作と期待遷移を記載した。 |

## 実行トレース

| フェーズ      | 状態 | 不明点 | Issue / Cause / General Fix Rule |
| ------------- | ---- | ------ | -------------------------------- |
| Understanding | OK   | なし   | なし                             |
| Planning      | OK   | なし   | なし                             |
| Execution     | OK   | なし   | なし                             |
| Formatting    | OK   | なし   | なし                             |

## 裁量で補った点

- **アプリケーション方針の選択:** 反復した開始要求は最後の要求を採用する。保留中の停止・解放は取消せず、完了後にその target を取得する。
- **アプリケーション方針の選択:** 停止・解放失敗後の再試行は明示操作にする。自動再試行回数や待機時間は製品要件がないため定めない。
- **指示の曖昧さ:** なし。上記は不足した指示を補う解釈ではなく、要求された反復・失敗時方針の具体的な選択である。

## Retries

0 回。やり直しを要する失敗はなかった。
