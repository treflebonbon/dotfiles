# Scenario C: 相互排他的なデバイス・フローの設計メモ

## Deliverable

画面録画とカメラ較正は、それぞれ固有の UI フロー Mediator を持つ。ただしデバイスを同時に所有できるか、どちらへ切り替えるか、停止・解放待ちの間に受ける要求をどう採用するかは、両者の親である `DeviceFlowMediator` が一意に裁定する。プロフィール編集はこの親に参加せず、既存の独立したプロフィール・フローのままにする。

| 所有者 | 責務 |
| --- | --- |
| 録画／較正の各 View | 状態を表示し、`start`、`stop`、`retry` を自分の Mediator へ通知する。兄弟 View を直接停止・開始しない。 |
| `RecordingMediator` | 録画固有の表示、設定、開始後の局所イベントを扱う。排他が関わる開始・停止要求は親へ渡す。 |
| `CalibrationMediator` | 較正固有の表示、手順、開始後の局所イベントを扱う。排他が関わる開始・停止要求は親へ渡す。 |
| `DeviceFlowMediator` | 現在のデバイス所有者、希望フロー、切替、停止／解放失敗、反復要求の採用を裁定する。 |
| デバイス用ユースケースと Effect 実行層 | 録画・較正の開始、停止、解放を実行し、成功、型付きの想定内エラー、defect、中断を区別して通知する。 |
| プロフィール Mediator／View | 編集、保存、表示だけを扱う。デバイス排他状態を読んだり、親を経由して操作を直列化したりしない。 |

`DeviceFlowMediator` の状態は、`Idle`、`Active(owner)`、`Stopping(owner, pendingTarget, shutdownId)`、`Acquiring(target, acquisitionId)`、`ShutdownFailed(owner, pendingTarget, shutdownId, error)` とする。`owner` は解放成功が通知されるまで維持するため、停止要求を出しただけではデバイスが空いたとは表さない。

反復した開始要求の方針は親が所有する。「同じ希望先」は統合し、「異なる希望先」は停止・解放中の `pendingTarget` を最後に受けた要求へ更新する（last request wins）。既に開始した停止は取り消さず、解放成功後に、その時点の `pendingTarget` だけを取得する。したがって、停止待ち中に録画開始を再要求した場合も、録画を再取得するのは旧所有者の停止と解放の成功通知の後である。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| `Idle` | 録画開始 | `Acquiring(recording, id)` | なし | 録画取得を実行する。 |
| `Idle` | 較正開始 | `Acquiring(calibration, id)` | なし | 較正取得を実行する。 |
| `Acquiring(target, id)` | 取得成功 (`id`) | `Active(target)` | `target` | 該当子 Mediator に active 表示を通知する。 |
| `Acquiring(target, id)` | 取得失敗／defect／中断 (`id`) | `Idle` | なし | 種別を保って UI 境界へ通知する。 |
| `Active(recording)` | 較正開始 | `Stopping(recording, calibration, id)` | recording | 録画の停止とデバイス解放を実行する。 |
| `Active(calibration)` | 録画開始 | `Stopping(calibration, recording, id)` | calibration | 較正の停止とデバイス解放を実行する。 |
| `Active(owner)` | 停止 | `Stopping(owner, none, id)` | owner | 停止と解放を実行する。 |
| `Stopping(owner, target, id)` | 開始要求 | `Stopping(owner, 最新 target, id)` | owner | 同一 target は統合し、別 target は希望先だけ更新する。停止／解放を再発行しない。 |
| `Stopping(owner, target, id)` | 停止・解放とも成功 (`id`) | `Acquiring(target, newId)` または `Idle` | なし | `target` があればその取得を開始する。 |
| `Stopping(owner, target, id)` | 停止または解放失敗 (`id`) | `ShutdownFailed(owner, target, id, error)` | owner（解放未確認） | 別フローを開始しない。失敗種別を表示する。 |
| `ShutdownFailed(owner, target, id, error)` | retry shutdown | `Stopping(owner, target, newId)` | owner | 停止／解放を再試行する。 |
| `ShutdownFailed(owner, target, id, error)` | 開始要求 | `ShutdownFailed(owner, 最新 target, id, error)` | owner | 希望先だけ更新し、成功するまで取得を開始しない。 |

Effect の実行は既存のアプリケーション境界または UI binding で行い、親が受理した要求だけを実行層へ渡す。停止時は親の方針に従って該当実行を中断し、必要な停止・解放を完了させる。Fiber の中断と Scope による資源寿命管理を使うが、Scope を閉じただけで実行が中断済み・デバイスが解放済みとは判定しない。実行層は `shutdownId` に対応する成功または失敗を親へ返し、親は一致する通知だけを採用する。別のキャンセルフラグや並行 scheduler は追加しない。

## 実行・確認メモ

| 確認 | 手順 | 期待結果 |
| --- | --- | --- |
| 録画から較正への切替 | 録画中に較正開始を要求する。 | 較正は直ちに取得されず、録画の停止とデバイス解放の成功後にだけ開始する。 |
| 停止／解放失敗 | 録画停止または解放を失敗させて較正開始を要求する。 | `ShutdownFailed` を表示し、較正の取得は開始されない。retry が成功した後にだけ希望先を取得する。 |
| 反復開始 | 切替の停止待ち中に較正開始を連打し、さらに録画開始を要求する。 | 重複した較正要求は一つに統合され、最後の録画要求が希望先となる。停止／解放は一度だけ実行され、成功後に録画を再取得する。 |
| 子と親の境界 | 各 View の start/stop 操作を行う。 | View は兄弟を直接操作せず、排他判断は常に `DeviceFlowMediator` に届く。各子の局所 UI は維持される。 |
| プロフィール編集 | デバイス切替中にプロフィールを編集・保存する。 | プロフィール・フローはデバイスの停止待ちに巻き込まれず、デバイス親へ不要なイベントを送らない。 |
| Effect の終了通知 | 中断、型付きエラー、defect、成功をそれぞれ発生させる。 | 種別は潰れず、`shutdownId` が一致した終了通知だけが状態を進める。解放未確認のまま他フローは開始しない。 |

## 凍結チェックリストの自己評価

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | 共通親 `DeviceFlowMediator` が排他を所有し、各子は局所責務を保つ。View 間の直接停止は設計に含めていない。 |
| 2 | ○ | `Stopping` で停止と解放の両方の成功を待ってから `Acquiring` へ進む。失敗時は `ShutdownFailed` に留まり、他方を開始しない。 |
| 3 | ○ | 停止待ち中は同一要求を統合、異なる要求は last request wins で希望先だけを更新する。裁定者は親一つである。 |
| 4 | ○ | プロフィール編集は独立した Mediator／View に残し、全 UI イベントを親へ集中させていない。 |
| 5 | ○ | 親の方針の下で Effect の既存実行・Fiber・Scope を使い、Scope 終了を中断の証明にせず、自作 scheduler を導入していない。 |
| 6 | ○ | 切替、停止／解放失敗、停止待ち中の反復要求を具体的な確認項目にした。 |

## Trace

| 区分 | 結果 |
| --- | --- |
| Understanding | OK — デバイス排他、停止・解放待ち、反復要求、プロフィール独立を対象として把握した。 |
| Planning | OK — 共有親、子フロー、実行層、プロフィールの責務を分離し、状態と通知を定義した。 |
| Execution | OK — 実装コードや Effect API の版指定をせず、設計メモ、遷移表、確認項目を作成した。 |
| Formatting | OK — 指定された自己評価、Trace、不明点、補完、再試行数を記載した。 |

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| なし | シナリオに必要な排他条件、失敗時の制約、反復要求の扱いを決める裁量が与えられている。 | 実装時に停止・解放 API の完了保証が未確認なら、成功通知の意味と `shutdownId` の照合範囲を導入済みの実行層で確認してから接続する。 |

## 補完した前提

- 停止と解放が別段階でも、親へ送る `shutdown succeeded` は両方の成功後だけにする。
- 停止待ちの新しい要求は現在の停止を取り消さず、親が保持する希望先だけを更新する。
- 過去の完了通知を採用しないため、開始・停止ごとに親が識別子を発行する。

## Retries

0
