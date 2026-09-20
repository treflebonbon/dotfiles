# R5-C: 相互排他のデバイスフロー

## Concrete Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| DeviceCoordinator（共通親 Mediator） | デバイス所有者（なし／録画／較正）、切替要求、停止・解放待ち、次の要求の採用、失敗時の遷移を裁定する。 |
| Recording Mediator | 録画固有の開始・停止 UI と表示を扱う。開始・停止のうちデバイス所有に影響する要求は親へ送る。 |
| Calibration Mediator | 較正固有の開始・進行・結果表示を扱う。デバイス取得を伴う開始要求は親へ送る。 |
| Profile Mediator／View | プロフィール編集の入力・保存・表示を扱う。デバイス所有状態を読まず、親の排他対象にもならない。 |
| Model／ユースケース | 録画・較正の業務上の開始／停止可否と実行時検証を行う。 |
| Effect 実行境界 | 親が裁定した停止、中断、解放、取得を既存の Effect 実行・寿命管理へ接続し、成功、型付きエラー、defect、中断を区別して親へ通知する。 |
| View | 状態を表示し、`requestRecording`、`requestCalibration`、`stop` を担当 Mediator へ通知する。兄弟 View や兄弟 Mediator を直接停止しない。 |

切替中に新しい要求が来た場合の方針は「最後の要求を保留先として採用する」とする。同じ保留先への重複要求は無視し、異なる保留先への要求は保留先を置換する。この判断は DeviceCoordinator だけが行う。停止済みという通知だけでは切替を進めず、解放成功通知を待つ。

### 状態・イベント遷移表

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| Idle | `requestRecording` | Starting(recording) | なし | 録画用デバイス取得を Effect 実行境界へ依頼する。 |
| Idle | `requestCalibration` | Starting(calibration) | なし | 較正用デバイス取得を Effect 実行境界へ依頼する。 |
| Starting(x) | `acquired(x)` | Active(x) | x | x の子 Mediator へ開始完了を通知する。 |
| Starting(x) | `acquireFailed(x, error)` | Idle | なし | エラー種別を保ったまま x の表示へ通知する。 |
| Active(recording) | `requestCalibration` | ShuttingDown(recording, calibration) | recording | 録画停止とデバイス解放を Effect 実行境界へ依頼する。 |
| Active(calibration) | `requestRecording` | ShuttingDown(calibration, recording) | calibration | 較正停止とデバイス解放を Effect 実行境界へ依頼する。 |
| ShuttingDown(current, pending) | `requestRecording`／`requestCalibration` | ShuttingDown(current, latest) | current | `latest` を上記方針で更新する。停止・解放処理は重複起動しない。 |
| ShuttingDown(current, pending) | `stopped(current)` | ShuttingDown(current, pending) | current | 停止完了を記録するが、解放成功までは取得しない。 |
| ShuttingDown(current, pending) | `released(current)` | Starting(pending) | なし | pending のデバイス取得を依頼する。 |
| ShuttingDown(current, pending) | `stopOrReleaseFailed(current, error)` | Active(current) | current | pending を破棄し、失敗を current の子 Mediator へ通知する。他方を開始しない。 |
| Active(x) | `stop` | ShuttingDown(x, none) | x | 停止と解放を依頼する。 |
| ShuttingDown(x, none) | `released(x)` | Idle | なし | 追加の取得は行わない。 |

`released(current)` は停止と解放の両方が成功したことを実行境界が確認してから送る。Scope の close だけをこの通知の根拠にせず、親が選んだ停止方針に従って Effect の Fiber 中断と Scope による資源解放を既存の仕組みで結び付ける。並行制御用の別 scheduler やキャンセルフラグは追加しない。

### 実行・検証メモ

| 確認 | 操作列 | 期待結果 |
| --- | --- | --- |
| 録画から較正への切替 | 録画を開始し、Active(recording) 中に較正を要求する。`stopped(recording)` の後に `released(recording)` を送る。 | `released` 前には較正を取得しない。`released` 後にだけ Starting(calibration) となり、取得成功後に Active(calibration) となる。 |
| 切替中の解放失敗 | Active(recording) から較正を要求し、`stopOrReleaseFailed(recording, error)` を送る。 | Active(recording) に戻り、較正は開始されない。失敗は種別を失わず録画フローへ表示される。 |
| 切替中の反復要求 | Active(recording) から較正を要求し、ShuttingDown 中に録画、較正、録画を順に要求する。 | 停止・解放は一度だけ依頼され、保留先は recording になる。解放成功後は Starting(recording) に進む。 |
| View 境界 | 録画 View から較正開始を要求する。 | 録画 View は較正 View を停止しない。担当 Mediator 経由で DeviceCoordinator が切替を裁定する。 |
| 独立フロー | 録画から較正へ切替中にプロフィールを編集・保存する。 | プロフィール操作は実行でき、デバイスの状態・保留先・停止処理を変更しない。 |

## 凍結チェック

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | DeviceCoordinator を共通親の唯一の排他判断者とし、子は局所フローを維持、View の兄弟直接停止を禁止した。 |
| 2 | ○ | ShuttingDown と `released` を分離し、停止または解放の失敗では他方の取得へ進まない遷移を定義した。 |
| 3 | ○ | 切替中の最後の要求を採用する方針、重複要求の扱い、所有者を明記した。 |
| 4 | ○ | Profile Mediator／View を親の排他状態から分離し、全 UI イベントの中央集約を避けた。 |
| 5 | ○ | Effect 実行境界へ停止・中断・解放を委譲し、Scope close 単独を中断証明にせず、別 scheduler を追加しないとした。 |
| 6 | ○ | 切替、停止・解放失敗、切替中の反復要求を操作列と期待結果で確認できるようにした。 |

## Trace

| 区分 | 状態 | 根拠 |
| --- | --- | --- |
| Understanding | OK | 排他対象の二つのデバイスフロー、解放待ち、失敗、反復要求、独立プロフィールフローを責務へ分解した。 |
| Planning | OK | 共通親の状態と、停止・解放成功を境界にした遷移を設計した。 |
| Execution | OK | 要求された責務マップ、遷移表、実行・検証メモを作成した。 |
| Formatting | OK | 日本語で、達成状況、根拠、未確定事項、裁量補完、再試行回数を記録した。 |

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 停止失敗後に録画を継続可能か、エラー状態として利用者の復旧操作を待つかは未指定。 | デバイス実装が停止失敗時の実際の所有状態を規定していない。 | 実行境界が所有状態を確認できない失敗では、新規取得を禁止し、確認済みの所有状態と明示的な復旧イベントだけで次遷移を許可する。 |
| `latest` が現在の所有者と同じ場合に、解放後に再取得するか Idle にするかは未指定。 | 同一フローの反復開始が再起動要求か取消要求か定義されていない。 | 各フローの開始要求を冪等と再起動のどちらにするかを Model／親 Mediator の契約に明記し、保留先採用規則に反映する。 |

## Discretionary fill-ins

- 切替中は最後の開始要求を採用する方針を置いた。利用者の直近の意図を保ちつつ、停止・解放を一回にできるためである。
- 停止または解放の失敗時は Active(current) へ戻す前提を置いた。実装が所有状態を確認できない場合は Unclear points の一般則に従い、専用の復旧状態へ変更する。

## Retries

0
