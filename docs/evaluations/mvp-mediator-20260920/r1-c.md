# Scenario C: 排他的なデバイスフローの設計メモ

## Deliverable

### 責務マップ

| 所有者 | 責務 | 所有しない責務 |
| --- | --- | --- |
| Root | 画面を組み立て、`DeviceFlowMediator` と独立した `ProfileMediator` を接続する。 | 全 UI イベントの裁定。 |
| `DeviceFlowMediator`（共通親） | デバイス所有者（`none` / `recording` / `calibration`）、切替要求、停止・解放待ち、再要求方針、結果採用を裁定する。 | 録画・校正それぞれの詳細な画面状態、デバイス操作そのもの。 |
| `RecordingMediator` / `CalibrationMediator`（子） | 各フロー固有の表示状態と、親から受けた開始・停止・解放の結果を表示用状態へ変換する。自分だけで決められない開始・切替要求を親へ委譲する。 | 兄弟フローの停止、排他の判断。 |
| Model / ユースケース | 録画停止、デバイス解放、校正開始の業務規則と実行時検証を Effect として表す。 | React の状態や UI の排他判断。 |
| Effect 実行層 | 親が受理した停止・解放・取得を既存の実行境界で起動し、Fiber の中断と Scope による資源解放を所有方針に従って扱う。成功、想定内失敗、defect、中断を区別して親へ返す。 | Scope を閉じただけで中断済み・解放済みとみなすこと、独自 scheduler の追加。 |
| Recording / Calibration View | 表示し、開始・停止要求を担当 Mediator へ通知する。 | 兄弟 View や兄弟 Mediator を直接停止すること。 |
| `ProfileMediator` / Profile View | プロフィール編集の入力、送信、表示を独立して扱う。 | デバイス排他状態への参加。 |

### 親 Mediator の状態と遷移

親の状態は `Stable(owner)`、`Acquiring(target, requestId)`、`Switching(from, to, requestId, phase)`、`Blocked(from, to, reason)` とする。`phase` は `stopping` または `releasing`。`requestId` は、遅延した結果を現在の切替へ混入させないための操作単位の識別子である。

| 現在状態 | イベント | 親の裁定・次状態 | 実行層への指示 |
| --- | --- | --- | --- |
| `Stable(none)` | `requestStart(recording または calibration)` | 新しい `requestId` を発行し `Acquiring(target, id)`。 | 対象デバイスを取得し、開始する。 |
| `Acquiring(A, id)` | `acquired(id)` | `Stable(A)`。 | なし。 |
| `Acquiring(A, id)` | `acquireFailed(id)` | `Stable(none)` に戻り、A の子へ失敗を返す。 | 失敗を分類して返す。 |
| `Stable(A)` | `requestStart(A)` | 既に所有しているため開始しない。子へ現在状態を返す。 | なし。 |
| `Stable(A)` | `requestStart(B)`（A ≠ B） | 新しい `requestId` を発行し `Switching(A, B, id, stopping)`。B は待機表示にする。 | A の停止を要求する。 |
| `Switching(A, B, id, stopping)` | `stopped(id)` | `Switching(A, B, id, releasing)`。 | A のデバイス解放を要求する。 |
| `Switching(A, B, id, releasing)` | `released(id)` | 新しい B 用の識別子で `Acquiring(B, id)`。B は開始中表示にする。 | B のデバイス取得・開始を要求する。 |
| `Switching(A, B, id, *)` | `stopFailed(id)` / `releaseFailed(id)` | `Blocked(A, B, reason)`。B は開始しない。A の実際の状態と再試行可能性を表示する。 | 失敗を分類して返す。自動的に B を開始しない。 |
| `Switching(A, B, id, *)` | `requestStart(C)` | **latest-wins**: 現在の停止・解放は継続し、待機先を C に置換して新しい `requestId` を発行する。古い id の結果は採用しない。 | 追加の停止・解放は要求しない。 |
| `Blocked(A, B, reason)` | `retrySwitch(B)` | 新しい `requestId` で、実測された A の状態に応じて停止または解放段階から再開する。 | 必要な操作だけを再試行する。 |
| `Blocked(A, B, reason)` | `cancelPending` | B への保留要求を破棄し、A の実際の状態を維持する。 | 進行中の Fiber があれば親の取消方針に従って中断を要求する。中断結果を待つ。 |

`released(id)` が確認されるまで B の取得を発行しない。停止要求の送信、Fiber の中断、Scope の close はいずれも「デバイスが解放済み」の証明ではなく、実行層から返る停止・解放結果だけを次の取得の根拠にする。

### 実行・検証メモ

既存の Effect 実行境界で、親が受理した各操作を Fiber とその資源寿命に結び付ける。親は状態遷移と採用する `requestId` を決め、実行層はその方針に従って中断、購読解除、解放を行う。Scope の終了を通信・デバイス操作の完了や中断成功として扱わない。失敗時は想定内失敗、defect、中断を分けて親へ戻し、`Blocked` で B の開始を抑止する。

| 確認 | 操作 | 期待結果 |
| --- | --- | --- |
| 切替 | 録画中に校正開始を要求し、停止成功・解放成功を返す。 | 録画の停止、解放確認後にだけ校正取得を一度開始する。View 同士の直接操作はない。 |
| 停止失敗 | 録画中に校正開始を要求し、停止失敗を返す。 | `Blocked` になり校正は開始しない。再試行または保留取消を親だけが裁定する。 |
| 解放失敗 | 停止成功後に解放失敗を返す。 | `Blocked` になり校正は開始しない。解放成功の確認なしに取得を発行しない。 |
| 繰返し要求 | 録画から校正への切替中に録画または校正の開始要求を繰り返す。 | latest-wins の待機先だけを保持し、同一停止・解放を重複実行しない。古い `requestId` の結果は無視する。 |
| 独立性 | デバイス切替中にプロフィールを編集・送信する。 | プロフィールフローはデバイス親の状態を待たずに進行する。 |

## Requirement achievement

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 排他は `DeviceFlowMediator` が一元的に裁定し、子は局所責務を保持する。View は兄弟を直接停止しない。 |
| 2 | ○ | `stopping` と `releasing` を明示し、`released(id)` 後にだけ次の取得を発行する。停止・解放失敗は `Blocked` として次フローを開始しない。 |
| 3 | ○ | 切替中の要求は latest-wins とし、親が `requestId` で一貫して採用・除外を裁定する。 |
| 4 | ○ | プロフィールは専用 Mediator に残し、デバイス親には参加させない。 |
| 5 | ○ | Effect の既存実行境界、Fiber、Scope を役割に応じて使い、Scope 終了のみを中断・解放の証明にせず、自作 scheduler を置かない。 |
| 6 | ○ | 切替、停止失敗、解放失敗、繰返し要求、独立プロフィールの具体的な確認を定義した。 |

## Trace

| フェーズ | 状態 | 根拠 |
| --- | --- | --- |
| Understanding | OK | 排他対象、待機条件、失敗、反復要求、独立フローを要件として識別した。 |
| Planning | OK | 共通親、子、実行層、View、独立プロフィールの責務を分離した。 |
| Execution | OK | 状態遷移、結果採用、実行方針、検証項目を具体化した。 |
| Formatting | OK | フレームワークコードや Effect API バージョンを選ばず、要求された三種の成果物を記載した。 |

## Unclear points

なし。latest-wins は反復要求に対する通常の適用方針として選択したものであり、指示の曖昧さではない。

## Discretionary fill-ins

- 同一所有者への開始要求は no-op とした。重複取得を防ぐための UI 運用方針である。
- 切替中の要求は latest-wins とした。最後に利用者が求めたフローを待機先にし、既に進行中の停止・解放を重複させないためである。
- `requestId` を導入した。反復要求後に届く古い停止・解放結果の採用を防ぐための状態機械上の補完である。

## Retries

0 回。読み取り時の見出し抽出を補正したが、成果物作成の再試行はしていない。
