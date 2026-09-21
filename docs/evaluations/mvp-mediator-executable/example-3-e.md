# Scenario E: exclusive device

## 責務と状態

親 Mediator は recording と calibration の排他、最新要求、停止・解放・再試行の裁定だけを持つ。子フローの局所 UI と profile は独立し、`profile` は状態とコマンドを変えない。Effect 実行層は出力された `acquire`、`stop`、`release` を実行し、型付きエラー、defect、中断、寿命管理を所有する。この純粋 Node モデルは I/O、scheduler、Effect runtime を持たない。

| 状態/フィールド | 所有者 | 分類 | 意味 |
| --- | --- | --- | --- |
| `phase`、`owner`、`desired`、`operationId` | 親 Mediator | 本実装で追加する裁定状態 | 排他の進行、予約中の旧 owner、最新意図、実行中 ID。 |
| `nextId`、`pendingTarget`、`failedStage` | 親 Mediator | 検証専用 | ID の一意性、取得対象、停止/解放の再試行段階。 |
| `acquire` / `stop` / `release` の結果 | Effect 実行層 | 実行層の模擬 | 実行層が `ok` / `fail` イベントとして戻す。 |
| recording / calibration / profile の局所 UI | 各子フロー | 既存 binding／実行層の模擬 | 排他方針を持たず、親へ要求を通知する。 |

`idle → acquiring → active` が通常経路である。所有者を切り替えると `active → stopping → releasing → acquiring` を必ず通る。停止または解放が失敗したら `blocked` とし、同段階だけを `retry` で実行する。取得失敗は `idle` へ戻り、再試行は出力しない。待機中の `start` は `desired` だけを更新するため、実行中 ID と I/O は増えない。完了イベントは現在の ID に一致するときだけ採用する。

## 検証記録

`node example-3-e.mjs` を実行し、4 件すべて assertion を通過した。各列は `前状態 / イベント / 後状態 / 資源所有者 / 実行効果` を、実際の JSON 出力から要約したもの。

| 検査名 | 操作 | 期待結果と実測結果 |
| --- | --- | --- |
| `normal-completes` | `start(recording) → ok(1)` | `idle / start / acquiring / null / acquire(recording,1)`、次に `acquiring / ok / active / recording / なし`。passed。 |
| `latest-intent-returns-to-inflight` | 取得中に `calibration`、次に `recording` を要求して `ok(1)` | ID 1 の `acquire(recording)` だけを保ち、`desired` は往復する。完了時は `active(recording)`。passed。 |
| `release-before-next-acquire` | active recording から切替中に要求を recording へ戻す | `stop(recording,2) → release(recording,3) → acquire(recording,4)`。stop/release 完了前に acquire はない。passed。 |
| `failures-require-explicit-stage-retry` | 取得失敗、停止失敗、block 中 start/profile/stale、retry、解放失敗、retry | 取得失敗は idle・自動 I/O なし。block 中は意図更新のみ。retry は `stop(...,4)`、後の retry は `release(...,6)` だけを出力する。passed。 |

YOUR Trace: 4phase 全件 passed のため **allOK**。

### 凍結 6 基準

| 基準 | 結果 | 理由 |
| --- | --- | --- |
| 1. 待機中の最新意図 | ○ | acquiring / stopping / releasing / blocked の `start` は `desired` だけを更新し、in-flight ID と I/O を保持する。戻し要求も検査済み。 |
| 2. stop/release の完了と失敗 | ○ | 次の acquire は release の `ok` 後だけ。各失敗は blocked になり、明示 retry が失敗段階だけを再実行する。 |
| 3. ID と stale 結果 | ○ | stage/retry ごとに `nextId` で新規 ID を発行し、不一致の `ok` は無変更として検査した。 |
| 4. 親 Mediator と Effect の境界 | ○ | 親は方針とコマンド生成、Effect は実行・エラー・中断・寿命を所有する。モデルは I/O をしない。 |
| 5. 子フローと profile の独立 | ○ | `profile` は常に無変更で、子ローカル UI を状態へ取り込まない。 |
| 6. モデル・メモ・具体チェックの一致 | ○ | 4 ケースを実行し、ここには実測 JSON と一致する遷移だけを記録した。統合 Effect 確認は提案のみで未実行。 |

## Unclear Issue / Cause / General Fix Rule

- **Issue:** 実行層が stop/release の失敗を `fail(id)` として返せない実装では、block と stage 別 retry を判断できない。
- **Cause:** 実行境界が command ID と完了段階を保存せず、古い完了も区別できない。
- **General Fix Rule:** 実行層は各 command の ID と種類を対応付け、同じ ID の `ok` / `fail` を親 Mediator へ一度だけ返す。Effect の中断・解放の寿命管理はその境界で完結させる。

## 任意補完

提案のみ（未実行）: 実アプリでは Effect の scoped resource で device の release を保証し、遅延完了をこのモデルの ID で戻す統合確認を追加する。

## YOUR Retries

やり直し数: 2。ID を維持する取得失敗遷移と、リポジトリの lint/format 規約を修正後、Node self-check、oxlint、oxfmt を再実行した。

## INPUT と参照

- target SHA256: `170ad5348f5ce8110cd32744f86328574100dd6ed7bf1da185f31a3727583fed`（`protocol.md` の `## E — exclusive device (executable)` 節のみ）
- 実際に読んだ参照: `local-skills/mvp-mediator-architecture/SKILL.md`、`local-skills/mvp-mediator-architecture/references/model-verification.md`
