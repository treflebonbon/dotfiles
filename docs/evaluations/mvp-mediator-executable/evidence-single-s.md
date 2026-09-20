# Scenario S: executable evidence

## 入力

- `local-skills/mvp-mediator-architecture/SKILL.md`
- SHA256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da`
- 条件付き参照: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
- 評価対象: protocol の Scenario S のみ

## 責務と状態

| 所有者 | 責務／状態 |
| --- | --- |
| 既存 React/Query binding（`SearchBinding` の模擬） | 各 request の ID、text、通常の `pending`／`success`／`failure` と結果を実行・保持する。 |
| Result-acceptance Mediator（`SearchResultMediator`） | 最新に開始した request ID を一つ保持し、その ID の binding 状態だけを `displayed()` として採用する。成功・失敗とも text では照合しない。 |
| Query の既存実行層 | 要求の起動、成功・失敗通知、best-effort cancellation を担う。中断してもサーバー処理が巻き戻るとは扱わない。モデルは cancellation を実装しない。 |
| Passive View | `displayed()` を描画し、検索操作を Mediator に通知する。help tooltip の開閉は View 局所状態であり、検索 request ID や結果採用を変えない。 |

追加した裁定状態は Mediator の最新 request ID だけである。通常の pending/result は既存 binding を再利用する。Effect、Atom、独自 scheduler／Promise は導入しない。

## 実行した検査

`node docs/evaluations/mvp-mediator-executable/evidence-single-s.mjs` の実出力:

```text
ok currentSuccess
ok currentFailure
ok staleOutcomesAndRepeatedText
```

| 検査名 | 前状態 | イベント列 | 実際の後状態・照合 |
| --- | --- | --- | --- |
| `currentSuccess` | 新規 binding、最新 ID なし | `search(alpha)` → `success(id, [alpha result])` | `pending` から当該 ID の `success` へ移り、結果を表示。assert 成功。 |
| `currentFailure` | 新規 binding、最新 ID なし | `search(missing)` → `failure(id, not found)` | 当該 ID の `failure` と error を表示。assert 成功。 |
| `staleOutcomesAndRepeatedText` | 新規 binding、最新 ID なし | `search(same)` → `search(other)` → `search(same)` → 1件目 success → 3件目 success → 2件目 failure | 1件目の stale success 後も3件目は `pending`、3件目 success 後の2件目 stale failure でも3件目の result を維持。assert 成功。 |

各検査は新規の binding と Mediator から始める。3件目は1件目と同じ text だが別 ID であり、ID が一致しない古い success／failure は表示状態を変えない。現在 ID の success と failure はそれぞれ採用される。

## 固定基準の判定

| # | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | `staleOutcomesAndRepeatedText` は同じ `same` を再入力し、text ではなく3件目の ID を採用する。 |
| 2 | ○ | stale success は新しい `pending` を変えず、stale failure は新しい `result` を変えない。`currentSuccess` と `currentFailure` は現在完了を採用する。 |
| 3 | ○ | request ごとの pending/result は `SearchBinding` にあり、Mediator の追加状態は最新 ID のみ。 |
| 4 | ○ | Effect／Atom／独自 scheduler／Promise を追加せず、cancellation の server rollback も仮定しない。 |
| 5 | ○ | 結果採用の所有者を `SearchResultMediator` と命名し、tooltip を検索方針から分離した。 |
| 6 | ○ | 上記 self-check を実行済み。memo の ID 採用方針とモデルの `displayed()` は一致する。browser/runtime 統合の検証は主張しない。 |

## 検証環境

- `node docs/evaluations/mvp-mediator-executable/evidence-single-s.mjs`: 成功（上記3行）。
- `node_modules/.bin/oxlint --config oxlint.config.ts docs/evaluations/mvp-mediator-executable/evidence-single-s.mjs`: 成功。
- `node_modules/.bin/oxfmt --check docs/evaluations/mvp-mediator-executable/evidence-single-s.mjs docs/evaluations/mvp-mediator-executable/evidence-single-s.md`: 成功。

この検査は純粋モデルのイベント採用を対象にする。実際の React、TanStack Query、ブラウザ、通信中断、サーバー副作用との統合は対象外である。

## Trace

| 区分 | 記録 |
| --- | --- |
| Understanding | S は既存 Query binding を維持し、重複 text を含む重なった検索で最新 request ID の結果だけを表示する課題と理解した。 |
| Planning | 通常成功、通常失敗、同一 text 再入力を含む stale success/failure の3独立ケースを、Node の `assert` で実行する計画にした。 |
| Execution | `node` self-check、指定 config の `oxlint`、`oxfmt --check` を実行し、すべて成功した。 |
| Formatting | 実行モデルは `.mjs`、責務・状態・固定基準・実行結果・制限はこの Markdown に記録した。 |

## 不明点と判断

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| Query binding が stale request の内部キャッシュをいつ破棄するかは未指定。 | S は表示結果の採用を求め、cache policy は既存 Query に委ねるため。 | 表示採用に必要な最新 operation ID だけを Mediator に置き、cache eviction や cancellation policy は既存実行層の契約に従う。 |

## 裁量と再試行

- 裁量: 最新 ID に対応する binding 状態を表示値として導出した。別の `pending`／`result` state や reducer は作らなかった。
- 再試行: なし。同じ判断を繰り返して変更した箇所はない。
