# 検索画面: 重複リクエストの結果採用 — 責務/イベント/検証メモ

## 前提・範囲

対象は「入力ごとに検索リクエストを発行し、pending/result を binding が公開する」既存の React + TanStack Query 画面。TanStack Query とその実行機構（fetch・abort・キャッシュ）はそのまま使い、Effect は導入しない。競合する検索リクエストの「どれを表示に採用するか」という裁定と、独立したヘルプ tooltip の扱いだけを設計・モデル化する。

## 責務の所有者

| 役割 | このフローでの責務 |
| --- | --- |
| 実行層（TanStack Query） | 実際の fetch 実行、best-effort な abort 送出、購読解除・リソース解放。中断がサーバー処理を止めたことの証明はしない。 |
| Mediator（検索の採用裁定） | どのリクエストが「最新」かの判定、再入力を含む重複発行時の旧リクエストへの中断指示、完了通知が最新リクエストのものかどうかの判定（結果採用）。 |
| UI binding | Query が公開する pending/result を Mediator の裁定に必要な形で中継する。 |
| View | 採用済み結果の表示、tooltip の開閉。他の操作の許可・取消・進行には関与しない局所状態のみを持つ。 |

Model／ユースケース層は本フローには無い。検索結果の採用可否は業務規則ではなく UI 上の「どのリクエストを信じるか」という調停なので、責務は Mediator に置く。

## 操作方針

- 検索入力（同じテキストの再入力を含む）は毎回新しい論理リクエストとして扱う。テキストで重複排除すると、同じテキストへの古い応答を新しい応答と誤認する。
- 新しいリクエストを発行するとき、まだ完了していない旧リクエストには best-effort の中断を送るが、その旧リクエストを「終了済み」として扱わない。完了通知は届く前提で待ち、届いたら解放処理だけ行う。
- 表示に採用するのは「現在最新のリクエスト（acceptedId）」自身の完了通知（成功・失敗いずれも）のみ。到着順ではなく、どの要求の応答かで採否を決める。
- ヘルプ tooltip の開閉は上記のどの判断にも影響せず、上記のどの判断からも影響を受けない View 局所状態として扱う。

## 状態の説明

抽象モデルを作成したため、5列表で記載する。

| 状態 | 判断に使う目的・所有者 | 抽象モデルでの区分 | 抽象モデルでの表現 | 本実装での情報源 |
| --- | --- | --- | --- | --- |
| リクエストID発行（`nextId`） | 再入力を含む各検索発行を区別するID発行。Mediator | 既存 binding／実行層の模擬 | モデル内の連番 | 未確認: 既存の検索 binding が呼び出しごとに区別可能なIDを既に発行しているか（例: queryKey に連番を含める、または呼び出しごとに新しい queryFn/AbortController を束ねているか）を確認する。無ければ Mediator 側で発行する |
| 未完了リクエスト集合（`pending`） | 新規発行時にどのリクエストへ中断指示を送るか、完了通知が既知のリクエストかの判定。Mediator | 既存 binding／実行層の模擬 | モデル内の Set | 既存 Query 呼び出しの pending 状態一覧。未確認なら「同時に発行され得るリクエスト数と、その pending 状態を binding からまとめて取得できるか」を確認する |
| 採用対象ID（`acceptedId`） | 表示へ採用する結果の選択。Mediator（追加の採用判断の所有者。既存 binding が「最新だけ採用」を保証しないため） | 追加の裁定 | モデル内で保持する採用ID | 採用判断の所有者（Mediator）がこの値を保持する。新規実装が必要 |
| 採用済み結果（`adopted`） | 表示の元になる最後に採用された完了通知。Mediator→View | 追加の裁定 | モデル内の `{id, outcome}` | 同上。`selectDisplay` を通じてのみ読む。Mediator が別の `display` フィールドへ書き換えることはしない |
| tooltip 開閉（`tooltipOpen`） | 当該 View 内の開閉表示。View | View の局所状態 | モデル内の真偽値 | 当該 View のローカル状態（`useState` 等）。Mediator の状態とは無関係 |
| 期待値・比較用 snapshot | assertion・検査報告だけに使う | 検証専用の補助 | 検査側のローカル値 | 本実装には不要 |

## ケースと操作列

| ケース | 操作列 | 対応する分担 |
| --- | --- | --- |
| `normalPath` | `search("cat")` → 自身の成功完了 | 通常経路。他リクエストなし |
| `caseFailure` | `search("dog")` → 自身の失敗完了 | 失敗ケース（通常経路と別名） |
| `caseReentrySameText` | `search("cat")` → `search("cat")`（再入力）→ 旧IDの完了（stale）→ 新IDの完了（current） | 反復要求ケース。同一テキストでも新IDが発行されること、旧の完了が無視されることを確認 |
| `caseOutOfOrderStale` | `search("ca")` → `search("cat")`（旧を中断指示）→ 新IDの完了（先着・採用）→ 旧IDの完了（後着・stale、release のみ） | 古い通知ケース。到着順ではなくID一致で採否が決まること、cancel が best-effort であることを確認 |
| `caseTooltipIndependence` | `search("owl")` → `toggleTooltip` → 検索系フィールド不変を確認 → 完了通知 → tooltip 不変を確認 | tooltip の独立性ケース |

`caseOutOfOrderStale` 内で、旧IDの完了通知に対する `transition` 呼び出し1回に、所定の純粋な遷移チェック（入力不変性・初回結果の保持・同入力の結果一致）を適用した。

## 根拠表

検査コード抜粋（`model.mjs` より、`caseOutOfOrderStale` の純粋性チェック部分）:

```js
const before = snapshot(state);
const event = { type: 'completed', id: 1, outcome: { ok: true, value: ['ca'] } };
const first = transition(state, event);
assertEqual(state, before);
const firstBefore = snapshot(first);
const second = transition(state, event);
assertEqual(state, before);
assertEqual(first, firstBefore);
assertEqual(second, firstBefore);
```

実行コマンドと出力:

```
$ node model.mjs
[ok] normalPath
[ok] caseFailure
[ok] caseReentrySameText
[ok] caseOutOfOrderStale
[ok] caseTooltipIndependence

5/5 checks passed
```

| ケース | 観測時点 | 照合値・比較相手 | 比較式の抜粋 | 検査結果 |
| --- | --- | --- | --- | --- |
| normalPath | `search` 直後 | 発行効果は `fetch(id:1)` のみ | `assertEqual(r.effects, [{type:'fetch', id:1, text:'cat'}])` | 成功（上記出力参照） |
| normalPath | 自身の成功完了直後 | 効果は `adopt`、表示は成功値、`pending` は空 | `assertEqual(r.effects, [{type:'adopt', ...}])`／`assertEqual(selectDisplay(state), {status:'success', value:['cat photo']})` | 成功 |
| caseFailure | 自身の失敗完了直後 | 効果は `adopt`（失敗）、表示は error | `assertEqual(selectDisplay(state), {status:'error', error:'network'})` | 成功 |
| caseReentrySameText | 再入力直後 | 旧ID(1)への `cancel` と新ID(2)への `fetch` が両方発行され、ID が異なる | `assertEqual(rB.effects, [{type:'cancel', id:1}, {type:'fetch', id:2, ...}])`／`assert.notEqual(idA, idB, ...)` | 成功 |
| caseReentrySameText | 旧ID完了（stale）直後 | 効果は `release` のみ、表示は旧結果を反映せず pending のまま | `assertEqual(r.effects, [{type:'release', id:idA}])`／`assertEqual(selectDisplay(state), {status:'pending'})` | 成功 |
| caseReentrySameText | 新ID完了（current）直後 | 表示が新結果に更新される | `assertEqual(selectDisplay(state), {status:'success', value:['new cat']})` | 成功 |
| caseOutOfOrderStale | 新ID(2)の先着完了直後 | 効果は `adopt(id:2)`、表示は新結果 | `assertEqual(r.effects, [{type:'adopt', id:2, ...}])` | 成功 |
| caseOutOfOrderStale | 旧ID(1)の後着完了（純粋性チェック） | 呼出し前後で入力 `state` 不変、1回目と2回目の返却値（`state`+`effects`）が一致 | `assertEqual(state, before)`（2箇所）／`assertEqual(first, firstBefore)`／`assertEqual(second, firstBefore)` | 成功 |
| caseOutOfOrderStale | 旧ID(1)の後着完了直後 | 効果は `release` のみ、表示は新結果のまま不変（stale が表示に混入しない） | `assertEqual(first.effects, [{type:'release', id:1}])`／`assertEqual(selectDisplay(first.state), {status:'success', value:['cat']})` | 成功 |
| caseTooltipIndependence | `toggleTooltip` 直後 | 検索系フィールド（`nextId`/`pending`/`acceptedId`/`adopted`）が不変、`tooltipOpen` のみ反転 | `assertEqual({nextId,pending,acceptedId,adopted}, searchFieldsBefore)`／`assert.equal(state.tooltipOpen, true)` | 成功 |
| caseTooltipIndependence | 完了通知直後 | `tooltipOpen` が完了通知の前後で不変 | `assert.equal(state.tooltipOpen, tooltipBefore)` | 成功 |

全ケースは実際に `node model.mjs` で実行し、上記出力の `5/5 checks passed` で裏付けられている（各行の「検査結果」列はこの実行結果を参照）。

## 未確認・未実行の範囲

- 抽象モデルの検査のみ実施。実アプリの TanStack Query binding への配線・統合検査は未実行（対象の実装コードが本タスクに存在しないため）。
- 「本実装での情報源」欄で「未確認」とした項目（特にリクエストIDの発行元）は、実装時に既存の検索 binding の queryKey／呼び出し構造を確認したうえで接続する。
- best-effort cancel の実装（`AbortController` 経由の abort 送出など）自体は実行層の既存機構を使う想定で、本モデルは「中断指示を出すが完了通知は待つ」という Mediator 側の扱いだけを表現しており、実際の abort 呼び出しコードは対象外。
- tooltip の表示整形（開く方向・アニメーション等）は View の局所実装事項としてモデル化していない。

## 成果物

- `model.mjs`: 純粋モデルと自己検証（`node model.mjs` で実行、5/5 成功）。
- 本メモ（`memo.md`）。
