# Scenario C 実行メモ

## Deliverable

画面録画とカメラ較正が同じデバイスを同時に所有しないための、親 Mediator を中心とした責務、遷移、実行境界、確認手順を定義する。プロフィール編集はこの排他制御の外に置く。

### 責務地図

| 所有者 | 責務 |
| --- | --- |
| Model／ユースケース | 録画の開始・停止、較正の開始・停止、デバイス取得・解放の実行時検証と業務結果を定義する。 |
| デバイス親 Mediator | 現在のデバイス所有フロー、切替先、停止・解放の待機、失敗時の再試行可否、結果採用を裁定する。 |
| 録画／較正の子 Mediator | 各フロー固有の表示状態・手順を管理し、開始要求と停止／解放の結果を親へ通知する。兄弟を停止しない。 |
| Effect 実行層 | 親が受理した開始、停止、解放を既存の実行・寿命管理機構で動かし、操作 ID を付けて成功、型付きエラー、defect、中断を親へ返す。 |
| Passive View | 親が作った操作可否と進捗を表示し、録画開始・較正開始・再試行を対応する Mediator へ通知する。兄弟 View を直接止めない。 |
| プロフィール Mediator／View | プロフィール編集だけを扱う。デバイス親へイベントを送らず、録画・較正の状態にも依存しない。 |

### 親 Mediator の状態と遷移

方針は **最後に届いた開始要求を切替先として採用する（last request wins）**。停止または解放を始めた後は取り消さず、終了まで待ってから、その時点の切替先を取得する。同じ要求の重複は統合する。`shutdownId` は停止・解放実行の照合用、`requestId` は最新の利用者要求の照合用であり、別に保持する。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| `Idle` | `Start(recording/calibration, requestId)` | `Acquiring(target, requestId)` | なし | target の取得・開始を実行する。 |
| `Acquiring(target, requestId)` | 同じ target の再要求 | 同左 | なし | 重複を統合する。 |
| `Acquiring(target, requestId)` | 別 target の開始要求 | `Acquiring(target, desired, requestId)` | なし | 実行中の取得は重複・取消せず、最新 desired だけを保持する。 |
| `Acquiring` | `Acquired(opId)` が最新操作に一致 | desired がなければ `Active(target)`、あれば `Stopping(target, desired, shutdownId, requestId)` | target | 子 Mediator に開始完了を通知し、desired があれば停止を実行する。 |
| `Acquiring` | 型付き失敗／defect／中断 | `Idle`（結果を表示） | なし | 他フローを開始済みにしない。 |
| `Active(source)` | `Start(target != source, requestId)` | `Stopping(source, target, shutdownId, requestId)` | source | source の停止を実行する。 |
| `Active(source)` | `Start(source)` | `Active(source)` | source | 何もしない。 |
| `Stopping(source, desired, shutdownId)` | 任意の `Start(target, requestId)` | 同左（desired を最新 target に更新） | source | 停止を重複発行しない。 |
| `Stopping` | `Stopped(shutdownId)` | `Releasing(source, desired, shutdownId)` | source | source のデバイス解放を実行する。 |
| `Stopping` | 停止失敗 | `SwitchBlocked(source, desired, stopFailure)` | source | desired の取得を行わない。明示的な再試行だけを受ける。 |
| `Releasing(source, desired, shutdownId)` | 任意の `Start(target, requestId)` | 同左（desired を最新 target に更新） | source | 解放を重複発行しない。 |
| `Releasing` | `Released(shutdownId)` | `Acquiring(desired, requestId)` | なし | 最新 desired の取得・開始を実行する。 |
| `Releasing` | 解放失敗 | `SwitchBlocked(source, desired, releaseFailure)` | source | desired の取得を行わない。明示的な再試行だけを受ける。 |
| `SwitchBlocked` | `RetryShutdown` | `Stopping` または `Releasing` | source | 失敗した段階から再試行する。 |

遅延した停止・解放通知は `shutdownId` が一致するときだけ状態を進める。待機中に利用者要求だけが更新されても、継続中の停止・解放の終了通知は無効化しない。これにより資源の解放を取りこぼさず、古い要求による取得も避ける。

### Effect の実行境界

親 Mediator は方針だけを持ち、既存の Effect 実行・Fiber・Scope の仕組みに開始、停止、解放を委譲する。各実行は親が発行する操作 ID と結び、実行層は終了結果を親へ返す。Scope の close だけを停止完了やデバイス解放完了の証拠にせず、停止・解放の成功通知を待つ。想定内の停止／解放失敗は型付きエラーとして扱い、defect と中断を同じ失敗に潰さない。親の排他方針とは別のキャンセルフラグや scheduler は作らない。

### 確認手順

| 確認 | 操作列 | 期待結果 |
| --- | --- | --- |
| 切替 | 録画中に較正開始 | 録画停止成功、デバイス解放成功の順に完了するまで較正を開始せず、その後にのみ較正が所有者になる。 |
| 停止失敗 | 録画中に較正開始、録画停止失敗 | `SwitchBlocked` になり、較正の取得・開始は一度も実行されない。再試行成功後だけ切替が続く。 |
| 解放失敗 | 停止成功後に解放失敗 | `SwitchBlocked` になり、較正の取得・開始は一度も実行されない。解放再試行の成功後だけ切替が続く。 |
| 反復要求 | 録画→較正の停止待ち中に録画、較正、録画の順で開始要求 | 停止は一度だけ実行され、解放後には最後の録画だけを取得する。遅延した旧操作の通知で所有者が変わらない。 |
| 独立性 | デバイス切替待ち中にプロフィールを編集 | プロフィール編集は継続し、デバイス親の状態・実行回数を変えない。 |
| View 境界 | 較正 View の開始操作 | View は要求を送り、録画 View や録画子 Mediatorを直接停止しない。 |

## 六つの確認項目

| # | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | 共通のデバイス親 Mediator が排他と切替を所有し、子は局所フロー、View は要求通知だけを担当する。 |
| 2 | ○ | `Stopping` と `Releasing` を分け、停止・解放の各失敗を `SwitchBlocked` として保持する。新しい取得は `Released` 後だけである。 |
| 3 | ○ | last request wins と重複統合を明示し、親だけが待機中の切替先を更新する。 |
| 4 | ○ | プロフィールを別 Mediator／View とし、デバイス親はデバイス競合イベントだけを裁定する。 |
| 5 | ○ | Effect の既存実行・Fiber・Scope を親の方針の実行に使い、Scope close を中断の証明にせず、自作 scheduler を置かない。 |
| 6 | ○ | 切替、停止・解放失敗、反復要求、独立プロフィール、View 境界の具体的な操作列と期待結果を示した。 |

## Trace

| 段階 | 記録 |
| --- | --- |
| Understanding | 排他対象はデバイスを所有する録画と較正だけであり、プロフィール編集は独立である。切替の安全条件は「停止成功」だけでなく「解放成功」まで待つこととした。 |
| Planning | 共通親に所有者と切替方針を集約し、子へ局所フローを残した。待機中の反復要求には、操作 ID と要求 ID を分離した last request wins を選んだ。 |
| Execution | 責務地図、状態遷移表、Effect 実行境界、確認操作列を作成した。フレームワーク API の選定やアプリ実装は行っていない。 |
| Formatting | 指定された Deliverable、六項目判定、Trace、不明点、裁量補完、再試行を日本語で一ファイルに記録した。 |

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 停止失敗時に録画／較正が実際に継続しているか | デバイス API の停止失敗後の保証が未提示である。 | 所有・解放が確認できない限り、前所有者が保持しているものとして扱い、別フローを開始しない。API 契約を確認して `SwitchBlocked` の復旧操作を決める。 |
| 待機中に以前の所有者へ戻す要求の UX | シナリオは反復要求の方針を求めるが、利用者への表示を指定しない。 | 方針を親に一つだけ置き、現在の待機先と、停止を完走する必要を View に表示する。 |

## 裁量による補完

- 反復開始要求は last request wins とした。キューイングや先着順は要求されておらず、切替待ちの操作を増やさないためである。
- 停止開始後は取り消さず、完了後に最新要求を取得する。停止・解放の実行を途中で切り替えて資源解放を失うことを避ける。
- 失敗後の再試行は明示操作とした。自動再試行回数やバックオフは要件にないため定義しない。

## 再試行

作業上の再試行: 0 回。実行時の再試行は上記 `RetryShutdown` のみを親 Mediator が受理する。
