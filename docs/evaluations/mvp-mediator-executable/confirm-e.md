# Scenario E 実行メモ

対象 SHA256（`local-skills/mvp-mediator-architecture/SKILL.md`）: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`。

## 責務

共通 UI 親 Mediator が recording と calibration の排他、最新 start 意図、停止・解放・再試行の方針を所有する。子フローは各々の局所表示と start 通知だけを所有し、profile editor は独立する。Effect 実行層はモデルが出力した `acquire`、`stop`、`release` を実行し、型付きエラー、defect、中断、寿命管理を所有する。モデルは純粋な状態遷移とコマンド出力のみで、I/O、scheduler、Effect runtime を実装しない。

## 状態対応

| フィールド | 模擬／本実装 | 検証専用 |
| --- | --- | --- |
| `phase`, `owner`, `desired`, `operationId` | 親 Mediator の裁定状態を模擬する。production では `operationId` と既存の Effect 実行状態を結び、pending/result はその binding から導出できる。 | なし |
| `kind`, `failed`, `nextId` | モデルが停止・解放の失敗段階と新しい command ID を表す内部裁定状態。production では親 Mediator の方針状態。 | なし |
| assertion 内の変数と期待 effect | なし | 実行済み自己検査専用 |

`idle` は owner/desired/id がすべて null、`acquiring` は owner null、`active` は取得済み owner、`stopping`・`releasing`・`blocked` は解放完了まで旧 owner を予約する。`blocked` の operationId は null で、retry により新しい ID の失敗段階 command を発行する。

## 遷移・実測

| 検査 | 前状態 / event | 期待結果 | 実測 |
| --- | --- | --- | --- |
| latest intent | acquiring recording / start calibration, start recording, ok 1 | acquire を重複せず recording を active にする | 実行済み・一致 |
| stop failure retry | active recording / start calibration, fail 2, start recording, retry | blocked は最新 intent のみ更新し、retry は stop recording を新 ID 3 で一度だけ出す | 実行済み・一致 |
| stale/profile | stopping ID 3 / ok 2, profile | state/effects は不変 | 実行済み・一致 |

通常の割込みなし経路（`start recording` → `ok 1`）は最初の assertion として実行した。`bun docs/evaluations/mvp-mediator-executable/confirm-e.mjs` は exit 0、`confirm-e self-check: ok` を出力した。提案のみの追加検査はない。

## 基準自己報告

| 基準 | 結果 | 理由 |
| --- | --- | --- |
| 1 | ○ | 全 waiting phase の start は desired だけを更新し、in-flight ID/effect を維持する。acquire 完了時に最新 desired と照合する。 |
| 2 | ○ | stop 成功後だけ release、release 成功後だけ acquire。失敗は blocked、retry は失敗した stage のみを新 ID で再実行する。 |
| 3 | ○ | `nextId` は command ごとに増加し、intent 更新時の ID は不変。現在 ID 以外の completion は無視する。 |
| 4 | ○ | 親の方針と Effect 実行境界を分離し、モデルは command のみを返す。 |
| 5 | ○ | `profile` は state/effects を変えず、子の局所 UI はモデルの外にある。 |
| 6 | ○ | モデル、上表、`selfCheck()` の assertion が同じ経路を検査し、実行結果を記録した。 |

## Trace

| 区分 | 結果 |
| --- | --- |
| Understanding | OK |
| Planning | OK |
| Execution | OK — `bun docs/evaluations/mvp-mediator-executable/confirm-e.mjs` は exit 0、`confirm-e self-check: ok`。 |
| Formatting | OK — local `oxfmt --write` と `oxlint` は exit 0。 |

Issue: なし。Cause: なし。General Fix Rule: なし。

Discretionary decisions: acquisition failure は fresh `idle` に戻し、失敗した start 意図は保持しない。これは自動再試行を表現しないためであり、次の明示的 start が新しい acquisition を作る。Retries: 1 回。自己検査で retry の effect stage `stop` を phase として再利用していたため、`stopping`／`releasing` への対応を明示した。
