# Scenario S: 検索 UI の責務・状態・検証メモ

## 責務

| 所有者 | 責務 |
| --- | --- |
| Query binding / 実行層 | リクエスト発行、各 request ID の pending/result/error の保持、完了通知。取消があってもサーバー処理の巻き戻しは主張しない。 |
| SearchMediator | `latestRequestId` を更新し、その ID の binding 状態だけを表示へ採用する。成功・失敗とも ID で採否を裁定する唯一の所有者。 |
| Passive View | `observe` 相当の表示と `search(text)` 通知。help tooltip の開閉は View ローカルであり、検索要求・取消・進行には影響しない。 |

既存 binding の request ごとの pending/result/error を再利用する。追加する裁定状態は `latestRequestId` と次の採番だけであり、Effect、Atom、独自 scheduler / Promise は導入しない。

## 状態対応表

| 状態 | 所有者 | 分類 | 用途 |
| --- | --- | --- | --- |
| `binding.requests[id].pending/result/error` | Query binding | 既存 binding／実行層の模擬 | request ごとの通常の実行状態。 |
| `mediator.latestRequestId` | SearchMediator | 本実装で追加する裁定状態 | 最新要求の結果だけを採用する ID 境界。 |
| `mediator.nextRequestId` | SearchMediator | 検証専用 | 純粋モデルで一意 ID を採番する。実際は Query の request ID を使う。 |
| tooltip open | Passive View | 既存 binding と無関係な局所状態 | 表示だけ。モデルには含めない。 |

## 遷移方針

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| 初期 / 任意 | `search(text)` | 新 ID が最新、当該 binding は pending | Query binding | request を発行する。 |
| 最新 ID が pending | 同 ID の success / failure | 当該 result / error を表示 | Query binding、採用は SearchMediator | 完了を記録し表示へ採用する。 |
| 新 ID が pending | 古い ID の success / failure | 新 ID の pending / result は不変 | Query binding、除外は SearchMediator | 古い完了を記録しても表示から除外する。 |

`example-1-s.mjs` の最初のケースは、初期状態から `search → success` を割込みなく assertion する通常経路である。以後のケースは失敗、同一 text の反復、古い失敗を別の初期状態で確認する。

## 実行済み検査記録

実行: `node docs/evaluations/mvp-mediator-executable/example-1-s.mjs`

| 検査名 | 期待結果 | 実測結果 |
| --- | --- | --- |
| `normal-current-success` | 最新 ID の成功を表示する。 | passed: ID 1 の `tea-1` を表示。 |
| `current-failure-applies` | 最新 ID の失敗を表示する。 | passed: ID 1 の `timeout` を表示。 |
| `stale-success-cannot-replace-repeated-text` | 同じ `tea` を再入力しても ID 1 の成功は ID 2 pending を変えず、ID 2 の成功だけを表示する。 | passed: ID 2 pending を維持後に `new-tea` を表示。 |
| `stale-failure-cannot-replace-newer-pending` | ID 1 の失敗は ID 2 pending を変えず、ID 2 の成功を表示する。 | passed: ID 2 pending を維持後に `coffee-1` を表示。 |

実行モデルは pure Node の状態遷移であり、browser / React / Query runtime 結合、通信取消、サーバー停止の検証は未実行である。Query の取消は best effort であり、サーバー仕事が戻ることを前提にしない。

## 凍結基準の判定

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `latestRequestId` と完了イベントの `id` の一致で成功・失敗を採用し、同一 text の再入力を実行する。 |
| 2 | ○ | stale success / failure と current success / failure を assertion で実行し、新しい pending / result の不変と現在完了の採用を確認した。 |
| 3 | ○ | request ごとの pending/result/error は binding に残し、Mediator には結果採否に必要な ID だけを置く。 |
| 4 | ○ | Effect、Atom、独自 scheduler / Promise はなく、取消によるサーバー巻き戻しも主張しない。 |
| 5 | ○ | tooltip は View ローカル、結果採否の所有者は `SearchMediator` と明記した。 |
| 6 | ○ | メモの遷移表とモデルを同じ ID 方針にし、実行済み assertion と未実行の runtime 範囲を区別した。 |

## YOUR Trace

| 区分          | 結果 | 記録                                                 |
| ------------- | ---- | ---------------------------------------------------- |
| Understanding | OK   | Scenario S と六つの凍結基準だけを入力にした。        |
| Planning      | OK   | binding の通常状態と Mediator の採否状態を分離した。 |
| Execution     | OK   | pure Node self-check を実行する。                    |
| Formatting    | OK   | 日本語メモ、状態表、遷移表、検査記録を揃える。       |

## Unclear

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| なし | Scenario S が ID 方針と検証範囲を明示している。 | 実装では Query が発行した一意 request ID を Mediator に渡し、text で照合しない。 |

## 任意の補完

- モデルの ID は連番。実装では Query が提供する request ID に対応付ける。
- stale 完了も binding には記録する。表示採否だけを Mediator が除外する。

## YOUR Retries

再試行した判断はない（0 回）。

## 入力・参照

- INPUT `local-skills/mvp-mediator-architecture/SKILL.md`: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 読んだ参照: `local-skills/mvp-mediator-architecture/SKILL.md`、`local-skills/mvp-mediator-architecture/references/model-verification.md`、`docs/evaluations/mvp-mediator-executable/protocol.md` の Scenario S（37–47 行）。
