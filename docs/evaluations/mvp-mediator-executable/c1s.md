# S: held-out search UI

## 責務とイベント

| 所有者 | 状態・責務 | イベント |
| --- | --- | --- |
| 既存 Query binding | request ごとの `pending`、`result`、`error` と実行 | `begin`、成功、失敗を記録する。キャンセルは Query の best effort のままにする。 |
| `ResultAcceptanceMediator` | 追加する裁定状態 `latestId`。画面に採用する request identity を一つだけ決める。 | `search(text)` で新 ID を採用する。`succeeded(id)` / `failed(id)` は binding へ返し、表示は常に `latestId` の binding から導出する。 |
| Passive View | binding 由来の表示と `search` 通知 | 独自に成功・失敗を採否判定しない。 |
| `tooltipOpen` | View の局所的な open/close | 検索の開始・完了・採否を変えない。 |

`latestId` だけが追加の結果採否調整である。text 比較は使用しないため、同じ text の再入力も別 request として扱う。Query の実行・通常の pending/result は再実装せず、Effect、Atom、自作 scheduler、キャンセルによるサーバー処理の巻戻しも導入しない。

| 検査名 | 前状態 / イベント | 後状態・資源所有者 / 実行効果 | 期待結果 / 実測結果 |
| --- | --- | --- | --- |
| 通常 | 初期 / `search("cats")` → 現在 ID の成功 | `latestId` が新 ID、binding が pending 後 result。Query が実行を所有。 | result `["cat"]` を表示 / ○ |
| 古い成功 | 同 text の A 後に B が pending / A の成功 | `latestId` は B のまま。A の binding は完了しても B は pending。 | B の pending と空 result を維持 / ○ |
| 古い失敗 | B が pending / A の失敗 | `latestId` は B のまま。A の error は B の表示へ混入しない。 | B の pending と空 error を維持 / ○ |
| 現在の完了 | B が pending / B の成功 | B の binding を表示する。 | `["new cat"]` を表示 / ○ |
| tooltip | B 完了 / tooltip toggle | tooltip の局所状態のみ変化。 | 検索 result を維持 / ○ |

## 検証

`node docs/evaluations/mvp-mediator-executable/c1s.mjs` を実行し、`c1s self-check: passed` を確認した。最初に割込みなしの通常経路を assertion で実行し、その後に同一 text の重複要求、古い成功、古い失敗、現在成功、tooltip 独立性を検査する。これは純粋モデルの遷移確認であり、ブラウザや TanStack Query runtime との統合は対象外である。

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `latestId` で成功・失敗の表示採否を決め、同一 text A/B を別 ID として検査する。 |
| 2 | ○ | assertion が古い成功・失敗で B の pending/result/error が変わらず、B の成功だけが反映されることを示す。 |
| 3 | ○ | `SearchBinding` は既存 binding の実行と request 別状態の模擬であり、追加状態は `latestId` のみである。 |
| 4 | ○ | Effect/Atom/scheduler/promise を導入せず、キャンセルがサーバー処理を戻すとは扱わない。 |
| 5 | ○ | `HelpTooltip` は局所 state のみを持ち、結果採否の単一所有者は `ResultAcceptanceMediator` である。 |
| 6 | ○ | メモとモデルは同じ ID 採用方針を記し、自己検証を実行済みとして、runtime 統合未検証を明記する。 |

### Trace

| 区分          | 状態 |
| ------------- | ---- |
| Understanding | OK   |
| Planning      | OK   |
| Execution     | OK   |
| Formatting    | OK   |

### Unclear

| Issue | Cause | General Fix Rule |
| ----- | ----- | ---------------- |
| なし  | —     | —                |

### 裁量と再試行

- 裁量: 最新 request の binding 状態を直接表示し、採用済み result の複製 state を置かなかった。
- 再試行: 初回の 3 class 構成は実設定の oxlint により `max-classes-per-file` 違反となったため、binding と tooltip を closure の局所状態へ縮小した。ID 採用方針と assertion は不変である。
