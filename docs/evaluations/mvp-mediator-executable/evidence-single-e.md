# E: exclusive device の実行証跡

- INPUT `local-skills/mvp-mediator-architecture/SKILL.md` SHA256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da`
- 実装: `evidence-single-e.mjs`。Node 組み込みの `node:assert/strict` だけを使う純粋な決定モデルで、I/O、scheduler、Effect runtime は作らない。
- 実行結果: `node docs/evaluations/mvp-mediator-executable/evidence-single-e.mjs` は exit 0、`selfcheck: 4 scenarios passed` を出力した。

## 責務と状態

共通親 Mediator は `start`、最新 intent、排他、stop/release/retry と結果採用を裁定する。recording/calibration の子は局所 UI と開始要求だけを扱い、profile は独立で `profile` が state/effects を変えない。既存の Effect 実行境界は emitted `acquire`/`stop`/`release` を実行し、typed error、defect、中断、寿命管理を所有して `ok`/`fail` を戻す。

| phase | owner | desired | operationId | 次の完了で行うこと |
| --- | --- | --- | --- | --- |
| idle | null | null | null | start で acquire |
| acquiring | null | 最新 target | acquire ID | 成功時、最新 target と一致なら active。不一致なら stop |
| active | 現 owner | 現 owner | null | 異なる start で stop |
| stopping | 旧 owner | 最新 target | stop ID | 成功後に release |
| releasing | 旧 owner | 最新 target | release ID | 成功後に acquire |
| blocked | 旧 owner | 最新 target | null | retry のみ失敗 stage を再発行 |

停止・解放の失敗は `blocked` にし、開始要求は intent を更新するだけで I/O を再発行しない。acquire 失敗は `idle` に戻し自動 retry しない。すべての新規 stage/retry は単調増加 ID を発行し、現 operationId と異なる `ok`/`fail` は state/effects を変えない。

## 実行した検査

| selfcheck のケース | 実際の event 列と assertion | 結果 | | --- | --- | --- | --- | | acquisition の最新 intent | start recording → start calibration → start recording → ok(1) | recording を active、追加 I/O なし | ○ | | release 失敗と再試行 | active recording → start calibration → start recording → ok stop → fail release → start calibration → retry → ok release → fail acquire | release だけを ID 4 で再試行し、ID 5 の acquire 失敗後は idle・自動 retry なし | ○ | | stale completion | stopping 中に fail(1) | 現 state 同一、effects 空 | ○ | | stop 失敗と profile | fail stop → retry、profile | stop だけを ID 3 で再試行。profile は state/effects 不変 | ○ |

未実行: React 画面、実際の Effect runtime、デバイス API との統合はこの抽象モデルの対象外であり、成功を主張しない。

## 固定基準の照合

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1. 全 waiting phase の latest intent と重複 I/O 回避 | ○ | acquiring/stopping/releasing/blocked の start は intent のみ更新し、acquiring で元 target に戻しても同じ acquire ID を維持する。 |
| 2. stop/release 完了待ち、失敗時の明示 retry | ○ | stop 成功後のみ release、release 成功後のみ acquire。失敗は blocked、retry は `failedStage` のみを再発行する。 |
| 3. ID の存続・freshness・stale 除外 | ○ | `nextId` は新 stage/retry ごとに増加し、completion は `operationId` 一致時だけ採用する。 |
| 4. 親 Mediator と Effect 境界の分担 | ○ | モデルは command を返すだけで、Effect の実行・エラー分類・中断・寿命を実装しない。 |
| 5. 子 flow/profile の独立性 | ○ | 親が device policy を所有し、profile event は state/effects を変えない。 |
| 6. model/memo/check の一致と実行記録 | ○ | 上記 4 ケースを assertion 付きで実行し、実行済みと未実行統合範囲を分離した。 |

## Trace

- Understanding: 親の排他方針と子/profile の独立、最新 start を intent と実行 ID に分離する必要を確認した。
- Planning: 6 phase と `failedStage`、単調 ID、Effect command 出力だけを最小 internal state にした。
- Execution: 純粋 `transition` と 4 assertion ケースを実装し、Node で実行した。
- Formatting: 指定 API、観測値、基準表、実行済み/未実行の区別をこの memo に揃えた。

## 不明点・裁量・再試行

- Issue/Cause/General Fix Rule: 不明点なし。一般則は「実行中の ID は intent 更新で失効させず、completion は current ID と stage でのみ採用する」。
- 裁量: acquire 失敗後は intent を null にクリアした。仕様の idle 復帰・自動 retry 禁止を、次の明示 start が必要な状態として表した。
- 再試行: phase 名の組立てを一度修正した（`releaseping` を `releasing` に修正）。Node selfcheck が release 失敗ケースで検出し、修正後に全ケースを再実行する。
