# Example 2 E: exclusive device

## 責務と状態

親 Mediator は recording と calibration の排他、最新 start 意図、停止・解放失敗時の retry を裁定する。子フローは各自の局所 UI を持ち、`profile` は独立しているため、このモデルの状態・effect を変えない。Effect の実行層は出力された `acquire` / `stop` / `release` を実行し、型付きエラー、defect、中断、寿命を所有する。この純粋モデルは I/O、scheduler、runtime を持たない。

| 状態/フィールド | 所有者 | 分類 | 内容 |
| --- | --- | --- | --- |
| `phase`, `desired`, `operationId`, `blockedStage` | 親 Mediator | 本実装で追加する裁定状態 | 操作許可、最新意図、失敗した stage と再試行を決める。 |
| `owner`, `pendingTarget` | 実行層との境界を親 Mediator が模擬 | 実行層の模擬 | acquisition 成功前は owner なし。stop/release/blocked は旧 owner を保持する。 |
| `nextId` | 検証専用 | 検証専用 | 新 stage/retry の ID が同一 run で再利用されないことを確認する。 |
| `profile` の局所状態 | 子 profile flow | 既存 binding／実行層の模擬の対象外 | ここには保持せず、イベントを no-op として検査する。 |

`desired` は最新 start を保持する。待機中の start は intent だけを更新し、進行中 command の ID は変えず追加 I/O を出さない。acquisition 成功後に owner と desired が異なれば stop、次に release が成功してから desired を acquire する。acquisition 失敗は idle に戻し、retry では再実行しない。stop/release 失敗だけを blocked にし、明示 retry は失敗した stage だけに新 ID を割り当てる。

## 遷移と検証記録

実行コマンド: `node docs/evaluations/mvp-mediator-executable/example-2-e.mjs`

| 検査名 | 前状態 / イベント / 後状態 | 資源所有者 / 実行効果 | 期待 / 実測 |
| --- | --- | --- | --- |
| `normal-completes` | idle → start(recording) → acquiring → ok(operation-1) → active | null → recording / acquire(recording, operation-1) | passed / passed |
| `latest-intent-wins-through-waiting` | acquiring・stopping・releasing 中に target を往復し、各 pending ID の ok を受理 | acquiring は owner なし、stop/release は recording を保持 / 追加 I/O なしで desired 更新、release 後に acquire(recording, operation-4) | passed / passed |
| `acquisition-failure-needs-a-new-start` | acquiring → fail(operation-1) → idle。retry と stale ok は no-op、次の start で acquiring | owner なし / acquire は operation-1 と operation-2 のみ | passed / passed |
| `blocked-stages-retry-only-the-failure` | stop fail → blocked → retry stop → release fail → blocked → retry release → acquire calibration | blocked も recording を保持 / retry は stop(operation-3)、release(operation-5) のみ。stale operation-4 は no-op | passed / passed |
| `profile-is-independent` | idle → profile → idle | owner なし / effect なし、state 同一参照 | passed / passed |

実行済み: 上記 5 assertion-based checks。未実行: 実 Effect runtime との統合・実機 device・UI rendering。これらは実行層/アプリ側の責務であり、抽象モデルには追加していない。

## 凍結基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. 最新 intent と待機 phase | ○ | acquisition/stopping/releasing/blocked で desired のみを更新し、in-flight ID と command を維持する。往復 target を executable trace で確認した。 |
| 2. stop/release 成功と explicit retry | ○ | release 成功前に acquire せず、各 fail は blocked。retry は `blockedStage` の stage のみを新 ID で実行する。 |
| 3. ID と stale completion | ○ | `nextId` が新 stage/retry ごとに増加し、pending ID と異なる ok/fail は no-op。stale release ok を実行して確認した。 |
| 4. 親/Effect の境界 | ○ | 親の純粋 transition は command を返すだけで I/O/runtime を実装しない。 |
| 5. 子 flow/profile の独立 | ○ | `profile` は同一 state と空 effect を返す assertion を置いた。 |
| 6. model/memo/check の一致 | ○ | 同一 `cases` 定義の events/expected/actual を assertion と JSON 出力で共用し、この表は実測結果を記録した。 |

## YOUR Trace

| phase | 結果 |
| --- | --- |
| acquiring | OK: target 往復で operation-1 を維持し、追加 acquire なし。 |
| stopping | OK: target 往復で operation-2 を維持し、stop 成功後だけ release。 |
| releasing | OK: target 往復で operation-3 を維持し、release 成功後だけ最新 target を acquire。 |
| blocked | OK: start は desired 更新だけ、retry は失敗 stage だけを再実行。 |

allOK

## Unclear Issue / Cause / General Fix Rule

Unclear Issue: acquisition failure 後に `desired` を残すか。Cause: 「idle に戻る」と「auto-retry しない」は desired の可視性を定義しない。General Fix Rule: command を出していない idle の desired は最新要求の記録として残してよいが、`retry` を有効にせず、新しい `start` だけが新しい acquire を発行する。

## 任意補完

実アプリ接続時は Effect 実行層が command ID を completion event に戻し、終了通知を落とさない。UI は observe 値から表示を作る。

## YOUR Retries

やり直し数: 2。初回の lint/format 指摘を formatter で確認し、残った規約違反を出力モデルだけで修正した。最終 self-check、oxlint、oxfmt の結果をこのメモに記録する。

## INPUT

- target: `docs/evaluations/mvp-mediator-executable/protocol.md`
- SHA256: `ba0c8fa045387c5026e470b357afe4d8c9a1392fbadc1f0ccceca54d7cbfbcb2`
- 実際に読んだ参照: `local-skills/mvp-mediator-architecture/SKILL.md`、`local-skills/mvp-mediator-architecture/references/model-verification.md`
