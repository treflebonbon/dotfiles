# c1e — exclusive device

対象スキル: `/home/ubuntu/.codex/worktrees/90ae/dotfiles/local-skills/mvp-mediator-architecture/SKILL.md`  
読取 SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`

`c1e.mjs` は親 Mediator の純粋な裁定モデルである。子の recording / calibration は局所 UI を持ち、`profile` は独立している。Effect 実行層は返された `acquire` / `stop` / `release` を実行し、型付きエラー・defect・中断・寿命を所有する。

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1. 最新要求と待機中の一貫性 | ○ | `desired` だけを待機中に更新し、acquiring 中は I/O を追加しない。取得成功後の不一致は stop → release → 最新 target の acquire にする。 |
| 2. stop/release 完了と失敗時 retry | ○ | 次の acquire は release の `ok` 後のみ。失敗は `blocked` にし、`retry` は失敗した stage だけを新 ID で再実行する。 |
| 3. ID と stale completion | ○ | `nextId` は各 stage/retry で増加する。現在の `operation.id` 以外の `ok`/`fail` は同じ state と空 effects を返す。 |
| 4. 親裁定と Effect 境界 | ○ | モデルは命令を返すだけで I/O・scheduler・runtime を持たない。排他方針は親 Mediator に置く。 |
| 5. 子フロー/profile の独立 | ○ | `profile` は state/effects を変更しない。デバイス排他だけをこの親モデルが扱う。 |
| 6. 一致した実行可能検証 | ○ | `node docs/evaluations/mvp-mediator-executable/c1e.mjs` を実行し、通常の recording → calibration、acquiring 中の往復要求、stop/release 失敗と明示 retry、stale completion、profile no-op を assertion で確認する。実測結果は `c1e self-check: OK`。 |

状態の所有: `desired`、排他 phase、所有者、実行 ID は親 Mediator。`operation` は実行層へ渡した未完了 command の照合用であり、成功後に初めて acquire target を owner にする。`blocked` では旧 owner を予約したままにする。

Trace: Understanding OK / Planning OK / Execution OK / Formatting OK

Unclear — Issue: acquisition failure 後に `desired` を保持するか。Cause: 「idle に戻る」と「latest intent」の表示上の関係が未指定。General Fix Rule: 実行失敗では要求意図を消さず、再実行は明示 start のみで開始する。

Discretionary choices: 停止開始後に要求が旧 owner へ戻っても stop/release を完了する。これは「stop and release, including returning to an earlier requested target」をそのまま状態遷移へ反映したもの。`retry` は blocked 以外では no-op とした。

Retries: 1 回。初版は `oxlint` の関数形式・分岐複雑度に適合しなかったため、stage ごとの小さな純粋関数へ分け、意味を変えずに再検証した。
