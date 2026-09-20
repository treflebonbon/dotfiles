# Scenario S 実行メモ

対象: `docs/evaluations/mvp-mediator-executable/confirm-s.mjs`

対象 SHA-256: `4cb798739c69b6fb887733e55512c52fc97fadda7ab58e7abb41f3a73671b44b`

## 責務

| 所有者 | 責務 |
| --- | --- |
| SearchResultMediator | 最新 `requestId` を保持し、成功・失敗の表示採用を ID 一致で裁定する。 |
| 既存 Query binding / 実行層 | 検索の開始、通常の pending / result / failure、best-effort cancellation を扱う。取消してもサーバー処理が巻き戻るとは扱わない。 |
| Passive View | binding の表示と検索操作の通知を行う。 |
| ヘルプ tooltip | View 内の局所的な開閉だけを扱い、検索要求・結果採用・取消に関与しない。 |

結果採用の名前付き所有者は **SearchResultMediator** である。Effect、Atom、自作 scheduler、取消によるサーバー処理の巻き戻しは導入しない。

## 状態対応

| 状態 | 実行モデルの模擬 | 本番での所有者 | 検証での用途 |
| --- | --- | --- | --- |
| `pending` | `binding.pending` | 既存 Query binding | 新しい要求が stale completion 後も待機中であることを照合する。 |
| `result` | `binding.result` | 既存 Query binding | stale success が表示結果を置換しないことを照合する。 |
| `failure` | `binding.failure` | 既存 Query binding | stale failure が新しい要求へ混入しないことを照合する。 |
| `latestRequestId` | `mediator.latestRequestId` | SearchResultMediator が追加する結果採用状態 | テキストではなく要求単位で成功・失敗を採用する。 |
| assertion の期待値 | `assert` の比較対象 | 本番には追加しない | 通常、stale success、同文面の stale failure を実行確認する。 |

遷移は `開始(requestId)` で `latestRequestId` を更新し、`完了(requestId, success/failure)` は ID が一致するときだけ binding に適用する。不一致の完了は binding を変更しない。したがって同じ `text` の要求 4 と 5 も、5 が最新なら 4 の失敗を除外する。

## 実行した検証

`node docs/evaluations/mvp-mediator-executable/confirm-s.mjs` を実行する。

| 検査名 | 前状態 / イベント / 後状態 | 実測 |
| --- | --- | --- |
| `normal-current-success` | 初期 / request 1 → success 1 / `result: ["alpha"]`, pending なし | PASS |
| `stale-success` | request 2 → request 3 / success 2 / request 3 の pending と既存 result を維持。続く success 3 を採用 | PASS |
| `repeated-text-stale-failure` | `again` の request 4 → `again` の request 5 / failure 4 / request 5 の pending と result を維持。続く failure 5 を採用 | PASS |

これは純粋モデルと binding 模擬の assertion 実行であり、ブラウザー、React、TanStack Query の実ランタイム統合、通信取消、サーバー停止は検証していない。

## 基準ごとの自己報告

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | `latestRequestId` だけで success / failure を採否し、同じ `again` でも ID 4 と 5 を区別した。 |
| 2 | ○ | stale success と stale failure が新しい pending / result を変えない assertion と、current completion の採用 assertion を実行する。 |
| 3 | ○ | pending / result / failure は既存 Query binding の模擬に置き、追加した裁定状態は `latestRequestId` のみである。 |
| 4 | ○ | Effect / Atom / scheduler は追加せず、取消は best effort でサーバー処理を戻さないと明記した。 |
| 5 | ○ | SearchResultMediator を単一の結果採用所有者とし、tooltip は局所 View 状態として分離した。 |
| 6 | ○ | モデル、責務、遷移、実行済み assertion の記録を一致させ、未検証の統合範囲を明記した。 |

## Trace

| 区分          | 状態 |
| ------------- | ---- |
| Understanding | OK   |
| Planning      | OK   |
| Execution     | OK   |
| Formatting    | OK   |

## 不明点と裁量

- Issue: なし。
- Cause: なし。
- General Fix Rule: なし。
- 裁量: Query の具体 API が与えられていないため、実行層は pending / result / failure を持つ最小の immutable binding 模擬にした。ID は binding から開始時に受け取る前提とし、モデルは採否だけを所有する。
- Retries: 0 回。同じ判断の再試行はない（モデルが扱う反復検索は Retries に数えない）。
