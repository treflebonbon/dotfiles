# O — 実行時の業務判定（dispatch前固定）

実行した抽象モデル: `node docs/evaluations/mvp-mediator-followup/r2-o.mjs`

## 責務メモ

- **Model／ユースケース**: `cancelOrder` が dispatch 時に authoritative な最新 status を読み、発送済みなら `{ _tag: "OrderAlreadyShipped" }` の typed business error を返す。cached status は表示用で、ここで規則を再実装しない。
- **既存 binding の模擬**: `ExistingCancelBinding` の `pendingByOrder`、`resultByOrder`、操作 ID は既存の pending/result と古い結果の除外を表す。Mediator はこれを共用し、独自の `isSubmitting` や結果状態を持たない。
- **追加裁定**: `CancelMediator.requestCancel` は binding が pending の同一注文を拒否するだけで、業務上のキャンセル可否は判断しない。追加の裁定状態はない。
- **検証専用**: `cases` と assertion のみ。実行時の状態として使わない。
- **View**: `tooltipOpen` は局所表示状態。表示整形もここに置ける。一覧取得・他フロー・tooltip は CancelMediator の操作判断へ集約しない。

Effect を実装する場合、既存の Effect 実行境界／binding がユースケースを実行して成功または typed business error を戻す。defect と中断は観測・取消・解放の扱いであり、`OrderAlreadyShipped` へ変換しない。このモデルは API 非依存の純粋 Node モデルで、runtime、scheduler、依存は追加しない。

## 実行結果

以下は `r2-o.mjs` 内の実行済み assertion 名で、いずれも `ok` だった。

| ケース                                               | 結果 |
| ---------------------------------------------------- | ---- |
| 通常のキャンセル成功                                 | ok   |
| 発送競合はユースケースが typed business error で拒否 | ok   |
| pending 中の重複送信を Mediator が拒否               | ok   |
| 旧成功は再試行中の新しい試行を完了させない           | ok   |
| 旧失敗は再試行中の新しい試行を完了させない           | ok   |
| tooltip は局所表示であり操作裁定を変えない           | ok   |

未実行: 実 React/Effect runtime、実 API、既存 Atom binding との統合。抽象モデルの成功はそれらの統合成功を示さない。

## 固定基準

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | `発送競合はユースケースが typed business error で拒否` が cached の `cancellable` と実行時 `shipped` を分け、ユースケースの拒否を確認する。Mediator/View に業務規則はない。 |
| 2 | ○ | `pending 中の重複送信を Mediator が拒否` と、旧成功・旧失敗の各ケースが pending 抑止、別 attempt ID、旧結果の除外を確認する。 |
| 3 | ○ | `ExistingCancelBinding` が pending/result と操作 ID を持つ。責務メモで binding 模擬、追加裁定、検証専用を分類した。 |
| 4 | ○ | 責務メモが Effect の既存実行境界、typed business error、defect／中断の区別を示す。自作 runtime と依存追加はない。 |
| 5 | ○ | 通常成功、発送競合、重複要求、再試行中の旧成功／旧失敗を別 assertion として実行結果に列挙し、未実行の統合を明記した。 |
| 6 | ○ | tooltip の独立を assertion で確認し、責務メモで局所状態と、global FSM に集約しない範囲を記した。 |

## Trace

| Understanding | Planning | Execution | Formatting |
| ------------- | -------- | --------- | ---------- |
| OK            | OK       | OK        | OK         |

Unclear Issue: なし。

Cause: なし。

General Fix Rule: cached 表示状態を業務判定に使わず、実行時のユースケースが authoritative な状態で検証する。UI は既存 binding の操作 ID と pending/result を共用して、現在の試行だけを採用する。

Discretionary fill-ins: `release` は実行層が中断済みの試行を解放した後に通知する最小の模擬として置いた。これにより、新しい試行を開始した後の旧応答を検査できる。

Retries: 0

SKILL.md SHA-256: `6253f70613454fca7d5dd2c98a3bdab7c3053956651f62e89bf7ab4701cd4211`

参照: `local-skills/mvp-mediator-architecture/SKILL.md`, `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
