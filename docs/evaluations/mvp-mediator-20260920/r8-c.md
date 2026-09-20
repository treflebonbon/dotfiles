# Scenario C: 排他的なデバイスフローの責務・遷移メモ

## Deliverable

画面録画とカメラ較正は、共通の `DeviceFlowMediator` がデバイス所有権と切替を裁定する。録画／較正の子 Mediator はそれぞれの表示・局所操作を扱い、相手を直接停止しない。プロフィール編集はこの親に接続せず、独立したフローとして維持する。

| 所有者 | 責務 |
| --- | --- |
| Model／ユースケース | 録画開始・停止、較正開始・終了／解放の業務規則と実行時検証。想定内の停止・解放失敗は型付きエラーとして返す。 |
| `DeviceFlowMediator` | デバイスの現在所有者、要求先、切替、再試行、結果採用を裁定する。録画と較正の同時所有を許可しない。 |
| 録画／較正の子 Mediator | 各フロー固有の表示状態と操作要求を整え、開始・停止要求を親へ渡す。排他判定や兄弟の停止はしない。 |
| Effect 実行層 | 親が受理した開始・停止・解放を実行し、Fiber の中断と Scope による資源解放を既存の実行境界で管理する。終了結果、型付きエラー、defect、中断を区別して親へ返す。 |
| Passive View | 親または子から受けた表示状態を描画し、利用者の要求を通知する。兄弟 View や実行層を直接操作しない。 |
| プロフィール Mediator／View | 入力・保存を自身のフロー内で裁定する。デバイス排他状態には従属しない。 |

### 親 Mediator の状態と要求採用方針

`owner` は実際にデバイスを保有しているフロー、`desired` は最後に受理した開始先（または停止の `none`）、`operationId` は開始・停止・解放の結果を対応付ける識別子である。親は「遷移中は最後の開始要求を採用する」を一貫した方針にする。同じ要求は `desired` を変えず I/O を重複発行しない。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| `Idle` | `Start(recording)` | `Acquiring(recording, desired=recording, operationId)` | なし | 録画の取得・開始を 1 回実行する。 |
| `Idle` | `Start(calibration)` | `Acquiring(calibration, desired=calibration, operationId)` | なし | 較正の取得・開始を 1 回実行する。 |
| `Owned(recording)` | `Start(calibration)` | `Releasing(recording, desired=calibration, operationId)` | 録画 | 録画の停止とデバイス解放を 1 回実行する。較正はまだ開始しない。 |
| `Owned(calibration)` | `Start(recording)` | `Releasing(calibration, desired=recording, operationId)` | 較正 | 較正の終了と解放を 1 回実行する。録画はまだ開始しない。 |
| `Owned(owner)` | `Stop(owner)` | `Releasing(owner, desired=none, operationId)` | `owner` | 停止と解放を 1 回実行する。 |
| `Releasing(owner, desired)` | `Start(target)` | 同一状態、`desired=target` | `owner` | 最後の開始先だけを更新する。追加の停止・解放は発行しない。`Start(owner)` も、既に停止を始めた実行を戻さず、解放成功後に必要なら再取得する。 |
| `Releasing(owner, desired)` | 同じ `Start(desired)` または `Stop` | 同一状態 | `owner` | `desired` が変わらない限り I/O を発行しない。`Stop` は `desired=none` にする。 |
| `Releasing(owner, desired)` | `Released(operationId)` | `Idle` または `Acquiring(desired, newOperationId)` | なし | `desired=none` なら終了する。開始先があれば、解放成功を確認してからその 1 回だけ取得・開始する。 |
| `Releasing(owner, desired)` | `StopOrReleaseFailed(operationId, error)` | `Owned(owner)` | `owner` | 相手の開始を行わず、失敗を表示する。次の開始要求があれば、新たな切替として停止・解放を再試行する。 |
| `Acquiring(target, desired)` | 同じ `Start(target)` | 同一状態 | なし（取得中） | 取得を重複しない。 |
| `Acquiring(target, desired)` | `Start(other)` または `Stop` | 同一状態、`desired=other` または `none` | なし（取得中） | 追加の取得は始めない。完了結果を待って次の行へ進む。 |
| `Acquiring(target, desired)` | `Acquired(operationId)` | `Owned(target)`、または直ちに `Releasing(target, desired, newOperationId)` | `target` | `desired=target` なら所有を確定する。別の開始先または停止が最後に採用されていれば、所有確認後に親が解放を開始する。 |
| `Acquiring(target, desired)` | `AcquireFailed(operationId, error)` | `Idle` | なし | 失敗を表示する。待機中に更新された `desired` を自動実行せず、利用者の次の明示要求を待つ。 |

古い完了通知は `operationId` が現在の操作と一致するときだけ採用する。したがって、再試行前の停止・解放・取得結果は、新しい要求の表示や所有状態を上書きしない。

### 実行境界

親は I/O を実装せず、受理した遷移を既存の Effect 実行境界へ渡す。実行層は親の取消方針に従って Fiber を中断し、取得済みの資源は対応する Scope で解放する。ただし Scope を閉じただけでは処理が中断されたとも、外部デバイスが解放されたとも判定しない。親が `Released` を受け取るまで次の取得を開始しない。別のキャンセルフラグや並行スケジューラは追加しない。

### 検証メモ

| 確認 | 操作 | 期待結果 |
| --- | --- | --- |
| 切替 | 録画中に較正開始を要求し、停止・解放を成功させる。 | 較正は `Released` 後に 1 回だけ始まり、両者が同時に所有しない。 |
| 解放失敗 | 録画から較正への切替で停止または解放を失敗させる。 | 録画の所有状態と失敗を表示し、較正の取得を開始しない。 |
| 同一要求の反復 | 録画停止待ち中に較正開始を複数回送る。 | 停止・解放は 1 回、解放後の較正取得も 1 回である。 |
| 要求先の変更 | 録画停止待ちに較正開始、続けて録画開始を送る。 | 最後の録画要求を採用し、解放後に録画だけを再取得する。 |
| 独立フロー | デバイス切替中にプロフィールを編集・保存する。 | プロフィール操作はデバイス排他の状態遷移を変えず、デバイス待機で無効化されない。 |
| 古い結果 | 失敗後の再試行中に、前の操作の遅延結果を返す。 | `operationId` 不一致の結果を採用せず、現在の要求を上書きしない。 |

## 六つの確認項目

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | 共通親が所有権と排他を裁定し、子と View の兄弟直接停止を禁じた。 |
| 2 | ○ | `Releasing` で停止・解放成功を待ってから `Acquiring` へ進み、失敗時は相手を開始しない遷移を定義した。 |
| 3 | ○ | 遷移中の最後の開始要求を採用し、同一要求では I/O を追加しない方針と所有者を明記した。 |
| 4 | ○ | プロフィールを親の対象外である独立 Mediator／View として記した。 |
| 5 | ○ | Effect の既存実行境界、Fiber、Scope を役割ごとに示し、Scope 終了を中断・解放の証明としなかった。 |
| 6 | ○ | 切替、失敗、反復要求に加え、要求先変更・古い結果・独立フローの確認を具体化した。 |

## Trace

| 区分 | 状態 | 根拠 |
| --- | --- | --- |
| Understanding | OK | 排他、停止・解放待ち、失敗、遷移中の反復要求、独立プロフィールを要件として分離した。 |
| Planning | OK | 親の所有権状態、子の局所責務、Effect 実行境界、確認ケースを先に対応付けた。 |
| Execution | OK | フレームワーク API や実装コードを選ばず、責務表・遷移表・実行／検証メモを作成した。 |
| Formatting | OK | 指定された Deliverable、六項目、Trace、不明点、補完判断、再試行を日本語で収めた。 |

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| Effect の具体 API と既存実行境界の実装は未指定。 | Scenario が API 選定とフレームワークコードを明示的に対象外としている。 | 導入済み版の API と既存の実行境界を確認してから、ここで定義した親の遷移・結果通知契約へ接続する。 |

## 補完した判断

- 遷移中の反復開始は最後の要求先を採用する。停止・解放を開始した後に元の所有者を要求しても、その処理を巻き戻さず、解放成功後に必要なら再取得する。
- 取得失敗後は待機中に変わった要求を自動実行しない。利用者の次の明示要求で再試行する。

## 再試行

なし。
