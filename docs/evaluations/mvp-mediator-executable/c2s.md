# C2S: held-out search UI

## 責務と状態

| 状態・処理 | 所有者 | 分類 |
| --- | --- | --- |
| 要求ごとの実行、`pending`、成功値、失敗値 | 既存の React/Query binding | 既存 binding／実行層の模擬 |
| 最新の要求 ID と結果採用 | `SearchMediator` | 本実装で追加する裁定状態 |
| `tooltipOpen` | Passive View | 検証専用の局所状態 |

View は検索入力を `SearchMediator.search(text)` へ通知し、`view()` の binding 状態を表示する。実行完了は binding から `outcome({ id, status, value })` へ戻る。Mediator は `id === latestId` の場合だけ表示採用を許可する。検索語の一致は使わない。ツールチップは View 内だけで開閉し、検索イベントを送らない。

Query の取消は既存実行層に委ねる。取消は最善努力であり、サーバー実行の取消や巻戻しを意味しない。Effect、Atom、自作 scheduler、Promise は導入しない。

## 遷移と検証

| 検査名 | 前状態 / イベント | 期待結果 | 実測結果 |
| --- | --- | --- | --- |
| `normalPath` | 初期 / `search(alpha)` → 同 ID 成功 | pending 後に alpha を表示 | ○ assertion 成功 |
| `overlappingRequests` | old pending, new pending / old 成功 | new の pending を維持 | ○ assertion 成功 |
| `overlappingRequests` | new pending / new 成功 | new の成功を表示 | ○ assertion 成功 |
| `repeatedTextAndLocalTooltip` | same#1 pending, same#2 pending / same#1 失敗 | same#2 の pending を維持 | ○ assertion 成功 |
| `repeatedTextAndLocalTooltip` | same#2 pending / same#2 失敗 | same#2 の失敗を表示 | ○ assertion 成功 |
| `repeatedTextAndLocalTooltip` | same#2 pending / tooltip 開閉 | 検索状態は不変 | ○ assertion 成功 |

実行: `node docs/evaluations/mvp-mediator-executable/c2s.mjs`。Node 組込み `assert` の純粋モデルであり、React、Query、ブラウザー、通信取消の統合は検証していない。

## 固定 6 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. 最新要求 ID | ○ | 連番 ID と `latestId` を照合し、同一 text の再要求も区別する。 |
| 2. stale 成功・失敗と current 完了 | ○ | stale 成功、同一 text の stale 失敗、current 成功・失敗を assertion で確認する。 |
| 3. 既存 binding の再利用 | ○ | pending/result は `SearchBinding` に置き、Mediator の追加状態は最新 ID のみ。 |
| 4. 不要な導入・取消主張なし | ○ | Effect/Atom/scheduler/Promise を持たず、取消のサーバー巻戻しを主張しない。 |
| 5. tooltip と単一所有者 | ○ | tooltip は局所変数、結果採用は名前付き `SearchMediator` のみが裁定する。 |
| 6. 一致・実行・限界 | ○ | 本メモとモデルの ID 照合が一致し、実行コマンドと非統合の限界を記録する。 |

## 作業記録

| 項目 | 状態 | 内容 |
| --- | --- | --- |
| Trace Understanding | OK | S の要求 ID、重複 text、局所 tooltip、Query 維持をモデル化した。 |
| Trace Planning | OK | binding と採用裁定を分離し、最小の ID 照合にした。 |
| Trace Execution | OK | Node 組込み assertion の通常・重複・反復 text ケースを実行した。 |
| Trace Formatting | OK | 指定された `.mjs` と日本語 `.md` のみを対象にする。 |

Unclear Issue: 実際の Query binding が完了通知をどの API で渡すかは未指定。Cause: シナリオは既存画面の概念仕様であり API 契約を示さない。General Fix Rule: binding の既存完了通知で要求 ID を保持し、View へ渡す直前の既存接続点から `SearchMediator.outcome` を一度だけ呼ぶ。

裁量: binding は要求ごとの状態を保持する最小模擬にし、表示状態は `latestId` から導出した。再試行: 初回 lint の class 数・記法指摘に対し、binding を closure に縮小して再検証した。
