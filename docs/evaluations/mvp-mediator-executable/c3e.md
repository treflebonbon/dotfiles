# C3E: 排他デバイスの抽象決定モデル

対象スキル: `local-skills/mvp-mediator-architecture/SKILL.md`、SHA-256 `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`。

親 Mediator が `owner`、`desired`、段階遷移を裁定する。子の recording/calibration は開始要求だけを親へ渡し、profile は完全に独立する。Effect 実行境界は出力された `acquire` / `stop` / `release` を実行し、型付きエラー、defect、中断、寿命を所有する。この純粋モデルは I/O、scheduler、runtime を持たない。

| 状態 | 所有者 | 分類 |
| --- | --- | --- |
| `phase`, `owner`, `desired`, `operationId` | 親 Mediator | 本実装で追加する裁定状態 |
| `acquire` / `stop` / `release` effect | Effect 実行境界 | 実行層の模擬 |
| assertion 内の期待値 | 検証 | 検証専用 |

| ケース | 前状態 / event | 期待後状態・effect | 実測 |
| --- | --- | --- | --- |
| 通常 | idle / start recording → ok 1 | acquiring acquire 1 → active recording | 一致 |
| 反復要求 | acquiring recording / start calibration → start recording → ok 1 | I/O 重複なし、ID 1 のまま recording を active | 一致 |
| stop 失敗 | stopping recording / fail 2 → start recording → retry | blocked、start は再試行せず、retry が stop 3 | 一致 |
| stale 完了 | stopping 3 / ok 2 | 状態不変 | 一致 |
| release 失敗 | releasing recording / fail 4 → start calibration → retry | blocked、retry は release 5 だけを再発行 | 一致 |
| stale 完了 | releasing 5 / ok 4 | 状態不変 | 一致 |
| release 後 | releasing recording / ok 5 | 最新意図 calibration を acquire 6 | 一致 |
| acquire 失敗 | acquiring 6 / fail 6 | idle、auto retry なし | 一致 |
| profile | acquiring 6 / profile | 状態・effect 不変 | 一致 |

実行済み: `node docs/evaluations/mvp-mediator-executable/c3e.mjs`（assertion-based self-check）。提案のみ: 実 Effect 境界との結合試験（この抽象モデルの範囲外）。

| 基準 | 評価 | 根拠 |
| --- | --- | --- |
| 1. 最新 intent | ○ 1.0 | 全待機段階で `desired` のみ更新し、進行 ID と I/O を維持する。取得成功後にだけ意図を照合する。 |
| 2. stop/release と retry | ○ 1.0 | 次 acquire は release 成功後のみ。失敗は blocked、retry は失敗段階だけを新 ID で再発行する。 |
| 3. ID と stale | ○ 1.0 | `nextId` は単調増加し、completion は現在の `operationId` だけを受理する。 |
| 4. 責務境界 | ○ 1.0 | 親は方針、Effect は実行と寿命、モデルは command 出力だけを担当する。 |
| 5. 独立 flow | ○ 1.0 | `profile` は入力 state を同じ参照で返し effect は空。 |
| 6. 整合・実行記録 | ○ 1.0 | 上表の通常・失敗・反復の assertion を実行し、結果を記録した。 |

合計 **6.0 / 6.0**。critical 2項目はいずれも full のため成功。

Trace: Understanding / Planning / Execution / Formatting はすべて OK。Unclear Issue: なし。Cause: なし。General Fix Rule: stale completion は current `operationId` と一致するときだけ採用する。裁量: idle の acquisition failure 後も最後の `desired` は観測用に保持し、次の明示 start だけが再取得を始める。再試行: 1 回。初回の実 repo lint/format 指摘を、モデルの方針を変えずコード形だけ修正して再実行した。
