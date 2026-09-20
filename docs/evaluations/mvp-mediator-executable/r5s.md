# r5s: Query 検索の最新結果採用

## Deliverable

- [r5s.mjs](r5s.mjs) は Node 組み込みの `node:assert/strict` だけを使う純粋な実行可能モデルである。
- UI の結果採用の唯一の所有者は `searchResultAcceptanceMediator` と `acceptBindingCompletion` である。View は検索語を渡し、既存の Query/binding は `binding.execute` と通常の pending/result を担当する。
- `requestId` は入力 text ではなく要求ごとに増える。completion は `currentRequestId` と一致した場合だけ表示状態を更新する。
- ツールチップの開閉は局所的な View 状態であり、検索の request ID、取消、結果採用には関与しない。

## 責務とイベント

| 所有者 | 入力 | 出力・責務 |
| --- | --- | --- |
| Passive View | `search(text)`、tooltip の開閉 | 検索要求を Mediator へ通知する。tooltip はここで完結する。 |
| `searchResultAcceptanceMediator` | 新しい検索語 | 新しい `requestId`、表示上の `pending`、既存 binding への execute と最善努力の cancel 要求を裁定する。 |
| 既存 Query/binding 実行層 | execute/cancel 要求、通信完了 | 要求を実行し、success/failure を request ID 付きで返す。cancel は通信停止を試みるだけで、サーバー処理停止・ロールバックを意味しない。 |
| `acceptBindingCompletion` | request ID 付き success/failure | ID が current のときだけ `pending` と `result` を更新する。古い完了は無視する。 |

`requestId` は再入力した同じ text でも別になる。したがって `cat → cat` の 1 回目の成功・失敗は、2 回目が pending の間も、2 回目の結果が出た後も表示へ採用されない。

## 検証

実行済み:

```sh
node docs/evaluations/mvp-mediator-executable/r5s.mjs
```

自己検査は同一 text の連続入力で ID が異なること、最初の stale success と stale failure が新しい pending/result を変えないこと、最新 success と最新 failure がそれぞれ表示状態へ適用されることを確認する。これは純粋モデルの確認であり、ブラウザ、React、TanStack Query、通信ランタイムとの統合を実行したという主張ではない。

`node docs/evaluations/mvp-mediator-executable/r5s.mjs` は `r5s self-check: passed`、`bunx oxfmt --check docs/evaluations/mvp-mediator-executable/r5s.mjs` と `bunx oxlint docs/evaluations/mvp-mediator-executable/r5s.mjs` は成功した。`git diff --check` も成功した。

## 固定要件

| 要件 | 判定 | 根拠 |
| --- | --- | --- |
| 1. text 等値でなく最新要求 ID で success/failure を採用する | ○ | completion の `requestId === currentRequestId` だけを判定し、`cat → cat` も別 ID と assertion で確認する。 |
| 2. stale success/failure が新しい pending/results を変えず、current completion は適用される | ○ | stale の二経路は `deepEqual(state, pendingNewest)`、current の success/failure は期待状態との `deepEqual` を実行する。 |
| 3. 既存 binding の実行と通常の pending/result を再利用し、追加は採用調停だけ | ○ | effect は `binding.execute` / `binding.cancelBestEffort` を既存実行層へ渡すだけで、追加状態は request ID と採用判定である。 |
| 4. Effect/Atom/custom scheduler/取消ロールバック promise を強制しない | ○ | Node 組み込みのみを使う同期・純粋モデルであり、cancel は最善努力の effect と明記する。 |
| 5. tooltip は方針と独立し、名前のある一つの UI 結果採用所有者がある | ○ | tooltip は Passive View の局所状態、`searchResultAcceptanceMediator` / `acceptBindingCompletion` が結果採用の単一責務を持つ。 |
| 6. メモとモデルが一致し、チェック・限界・非統合を明記する | ○ | 上記の責務表、実行済み自己検査、統合未実施の範囲が同じ ID 採用方針を記録する。 |

## Trace

| 段階 | 状態 | 内容 |
| --- | --- | --- |
| Understanding (reading) | OK | MVP/Mediator スキルと TanStack 向け条件付き参照、repo の OXC 設定を読んだ。 |
| Planning (approach) | OK | 既存 Query/binding を保ち、request ID を使う結果採用だけを Mediator の責務にした。 |
| Execution (doing work) | OK | Node 組み込みだけの純粋モデルと同梱 assertion を作成した。 |
| Formatting (report) | OK | repo 設定で対象 MJS を format/lint し、メモへ実行結果を反映する。 |

## Issues

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 取消後でも古い応答が届く | 通信中断はサーバー処理や配送済み応答の停止を保証しない | 取消を正しさの根拠にせず、完了通知を操作単位 ID と current ID で照合する。 |

## Discretionary fill-ins

- 実装接続時は、既存 binding が開始した各要求の ID を success/failure 通知へ同じ値で戻す。
- 「最新」の範囲が画面全体でなく検索欄ごとなら、各欄の Mediator が独立した連番を所有する。

## Retries

私自身のやり直した判断: 0 回。アプリケーション通信の retry はこの数に含めない。
