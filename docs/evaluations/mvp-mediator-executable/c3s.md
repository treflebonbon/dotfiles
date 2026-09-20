# S: 最新検索結果の採用

対象: `/home/ubuntu/.codex/worktrees/90ae/dotfiles/docs/evaluations/mvp-mediator-executable/protocol.md#S`  
SHA-256: `18e1033cb8dcd626e8a4f2f393d17755fccb3f5033e255ffd6a9c8a741f77561`

読了スキル: `/home/ubuntu/.codex/worktrees/90ae/dotfiles/local-skills/mvp-mediator-architecture/SKILL.md`  
SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`

`SearchResultMediator` が唯一の結果採用者である。View は `SEARCH_REQUESTED { id, text }` を送る。Mediator は `latestRequestId` を更新し、既存 Query binding に実行を任せる。binding から `QUERY_SETTLED { id, outcome }` が届いたとき、`id === latestRequestId` ならその request の既存 pending/result を表示する。異なる ID の成功・失敗は binding 内の記録には残っても表示へ採用しない。文字列の同一性は判定しない。

| 状態 | 所有者 | 分類 |
| --- | --- | --- |
| request ごとの `pending` / `outcome` | 既存 Query binding / 実行層 | 既存 binding／実行層の模擬 |
| `latestRequestId` | `SearchResultMediator` | 本実装で追加する裁定状態 |
| tooltip の開閉 | `TooltipView` | 検証専用の局所表示状態 |

Query の取消は best effort であり、サーバー処理の取消や巻戻しを意味しない。本件は Effect、Atom、自作 scheduler、Promise 制御を導入しない。tooltip は View 内だけで完結し、検索要求・採用方針を変更しない。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| 初期 | `q1` を要求 | `q1` pending | Query binding、Mediator は `q1` を採用 | Query を開始 |
| `q1` pending | `q1` 成功 | `q1` success を表示 | 同上 | binding の結果を採用 |
| `q2(cat)` pending | `q3(cat)` を要求 | `q3(cat)` pending | Query binding、Mediator は `q3` を採用 | 同じ文字列でも新規 ID で Query を開始 |
| `q3` pending | `q2` 遅延成功 | `q3` pending のまま | Query binding | `q2` は表示へ不採用 |
| `q5` pending | `q4` 遅延失敗 | `q5` pending のまま | Query binding | `q4` は表示へ不採用 |
| `q5` pending | `q5` 失敗 | `q5` failure を表示 | 同上 | binding の結果を採用 |
| 任意の検索状態 | tooltip toggle | 検索状態は不変 | TooltipView | 局所表示だけを変更 |

## 検証

`node docs/evaluations/mvp-mediator-executable/c3s.mjs` を実行し、`c3s self-check: ok` を確認した。

| 検査名 | 期待結果 | 実測結果 |
| --- | --- | --- |
| 通常経路 | `q1` の pending → success が表示される | ○ |
| 同文言の反復要求 | `q2(cat)` の成功は `q3(cat)` pending を変えず、`q3` 成功は表示される | ○ |
| 遅延失敗 | `q4` failure は `q5` pending を変えず、`q5` failure は表示される | ○ |
| tooltip | 開閉しても検索表示と採用 ID は変わらない | ○ |

この自己検証は純粋モデルのイベント順序と責務境界だけを対象にする。ブラウザ、React、TanStack Query、ネットワーク取消、サーバー処理の統合動作は検証していない。

## 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. 最新要求 ID | ○ | `accepts` は ID の等値だけを使い、`q2(cat)` / `q3(cat)` を別要求として検査する。 |
| 2. 遅延結果 | ○ | 遅延 success と failure が新しい pending を変えず、current の success/failure が反映されることを assertion で確認する。 |
| 3. 既存 binding の再利用 | ○ | pending/result と Query 実行は `QueryBinding` の模擬へ置き、Mediator には採用 ID のみを追加する。 |
| 4. 不要な導入なし | ○ | Effect/Atom/scheduler/Promise を使わず、取消を server rollback と扱わない。 |
| 5. tooltip と所有者 | ○ | `SearchResultMediator` を唯一の採用者とし、tooltip は独立した `TooltipView` に閉じ込める。 |
| 6. 記録と実行範囲 | ○ | このメモと自己検証は同じ遷移を記載し、実行済み結果と統合検証外の範囲を明記する。 |

Trace Understanding / Planning / Execution / Formatting: all OK.

## Unclear Issue / Cause / General Fix Rule

- Issue: 遅延した同一文言の応答を最新の応答と誤認する。
- Cause: text を同一性として使う、または表示側が request ID を持たない。
- General Fix Rule: 各要求へ新しい ID を割り当て、結果採用は単一 Mediator の最新 ID との一致で決める。

## 裁量と再試行

- 裁量: 実行を再実装せず、既存 Query binding を最小の `Map` で模擬した。`latestRequestId` 以外の検索状態は追加していない。
- 再試行: なし。自分の同じ判断を繰り返す修正は行っていない。
