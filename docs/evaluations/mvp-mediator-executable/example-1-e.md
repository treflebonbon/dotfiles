# Scenario E: 排他デバイスの抽象意思決定モデル

入力は `local-skills/mvp-mediator-architecture/SKILL.md`（SHA-256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`）です。読んだ参照は `references/model-verification.md` です。

## 責務

共通親 Mediator が `desired`、排他所有、段階遷移、再試行を裁定します。録音・較正の子フローは `start` を通知するだけで、profile editor の `profile` はモデルの状態と効果を変えません。Effect 実行層は出力された `acquire`、`stop`、`release` を実行し、型付きエラー、defect、中断、寿命を所有します。この純粋モデルは I/O、scheduler、Effect runtime を持ちません。

| 状態 | 所有者 | 分類 |
| --- | --- | --- |
| `phase` / `owner` / `desired` / `operationId` / `nextId` / `stage` / `stageTarget` / `failedStage` | 親 Mediator | 本実装で追加する裁定状態 |
| 実機の取得・停止・解放と完了通知 | Effect 実行層 | 実行層の模擬 |
| 録音・較正の局所表示、profile 編集 | 各 Passive View / 子フロー | 既存 binding／局所状態 |
| assertion の expected / actual と JSON 実測ログ | 自己検査 | 検証専用 |

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| idle | start(target) | acquiring | なし | acquire(target, fresh id) |
| acquiring | start(target) | acquiring | なし | なし。意図だけ最新化 |
| acquiring | ok(current id) | active / stopping | 取得対象 / 取得対象 | 意図一致ならなし、不一致なら stop |
| stopping | ok(current id) | releasing | 旧 owner | release(旧 owner, fresh id) |
| releasing | ok(current id) | acquiring | なし | acquire(latest desired, fresh id) |
| stopping / releasing | fail(current id) | blocked | 旧 owner を予約 | なし |
| blocked | start(target) | blocked | 旧 owner を予約 | なし。意図だけ更新 |
| blocked | retry | failed stage | 旧 owner を予約 | 失敗段階だけ再実行 |
| acquiring | fail(current id) | idle | なし | なし。自動再試行しない |
| 任意 | profile / stale id / unknown | 不変 | 不変 | なし |

同一 owner への active 中の `start` は不変です。停止や解放を開始した後に意図が旧 owner へ戻っても、旧 owner を一度解放し、その後に最新意図を再取得します。これにより停止中の実行 ID は意図変更で失われず、結果は現在の ID と一致するときだけ採用されます。

## 実行済み検証

`node docs/evaluations/mvp-mediator-executable/example-1-e.mjs` を実行し、以下の assertion-based check はすべて `passed` でした。

| 検査名 | 期待結果 | 実測結果 |
| --- | --- | --- |
| `does-not-mutate-input` | 入力 state は不変、最初の acquire は id 1 | passed |
| `normal-uninterrupted` | acquiring → active | passed |
| `latest-intent-changes-back-without-duplicate-io` | 意図を戻しても acquire は 1 回、recording が active | passed |
| `switch-stops-releases-then-acquires` | stop → release → acquire の順で calibration が active | passed |
| `failure-blocks-until-retry-and-acquire-failure-idles` | stop/release の失敗は blocked、retry は失敗段階だけ実行、acquire fail は idle | passed |
| `profile-and-stale-completions-are-independent` | profile と stale completion は状態・効果を変えない | passed |

未実行の提案: 実際の Effect runtime での中断、Scope 解放、typed error / defect の統合確認。

## 凍結基準の照合

| 基準 | 結果 | 根拠 |
| --- | --- | --- |
| 1. 全 waiting phase の最新意図 | ○ | `acquiring` / `stopping` / `releasing` / `blocked` の start は意図のみ更新し、acquire 中に戻しても重複 I/O を出さない。 |
| 2. stop/release 完了と明示 retry | ○ | 新規 acquire は release の current-id 成功後だけ。stop/release fail は blocked、retry は `failedStage` のみ再実行。 |
| 3. ID と stale 結果 | ○ | `nextId` は各新段階・retry で増加し、current `operationId` と一致しない ok/fail は不変。 |
| 4. 親 Mediator / Effect の分担 | ○ | モデルは命令だけを返し、I/O・scheduler・runtime を実装しない。 |
| 5. 子フローと profile の独立性 | ○ | `profile` は常に不変。start は親への通知として扱い、局所 View 状態を持たない。 |
| 6. モデル・メモ・具体的検査の一致 | ○ | 実行済みの6検査が遷移表の通常、反復、失敗、stale、profile を assertion で確認した。 |

## 実行トレース

| 区分 | 結果 | 記録 |
| --- | --- | --- |
| Understanding | OK | Scenario E の API、6基準、条件付き検証参照を読んだ。 |
| Planning | OK | 親の裁定 state と Effect command を分離し、最新意図と進行中 ID を別管理した。 |
| Execution | OK | Node built-ins だけで pure transition と自己検証を実装した。 |
| Formatting | OK | exported API、JSON 実測ログ、Markdown の状態・遷移・検証表を揃えた。 |

## 不明点と補完

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| acquisition failure 後の `desired` を消すか | protocol は idle への復帰と自動再試行禁止を定めるが、last intent の保持は指定しない | 失敗で I/O を発行しない限り、再試行対象の可視性が必要なら latest intent を保持する。 |

このモデルでは `desired` を保持した。次の `start` が明示的に acquire を開始するため、自動再試行にはならない。

## Discretionary fills と Retries

- Discretionary fills: operation ID は state 内の連番とし、初回を 1 にした。blocked の `operationId` は pending ではないため null にした。
- Retries: 設計判断の再試行はなし。blocked 中の start は retry を起こさず intent のみ更新する方針を全段階で一貫して採用した。
