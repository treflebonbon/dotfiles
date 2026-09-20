# Scenario B 変更メモ

## Deliverable

既存の TanStack Query と共有 Context を維持したまま、合計表示には既存 formatter を適用し、ヘルプ tooltip を表示する。tooltip の開閉状態は、その表示箇所の局所状態にだけ保持する。送信、業務規則、Query の取得・キャッシュ、Context の構成は変更しない。

## 要件達成

1. ○ Query とプロジェクト既存設計を維持する。Effect、Atom、MVP 移行は追加しない。
2. ○ 合計整形と tooltip は表示専用で、送信や他操作の許可・進行を変えないため、Mediator、reducer、グローバル UI 状態を追加しない。
3. ○ 既存の複数 Context consumer と compound component 構成を維持し、単一 connector や props の中継階層を要求しない。
4. ○ 合計値は既存 formatter を使う。tooltip の開閉は表示箇所の局所状態に留める。
5. ○ 業務規則、送信処理、送信状態、Query の取得・キャッシュ処理は移動も書換えもしない。
6. ○ 表示された合計が既存 formatter の出力と一致すること、tooltip を開閉しても送信状態・他操作・表示以外の状態が変化しないことを確認する。

## 確認手順

1. formatter の入力となる合計値を表示し、既存 formatter による期待表記と一致することを確認する。
2. tooltip を開く、閉じるを繰り返し、説明の表示だけが切り替わることを確認する。
3. tooltip を開いた状態と閉じた状態の双方で、既存の送信操作と Query 表示が従来どおり動作することを確認する。

## Trace

Understanding / Planning / Execution / Formatting: すべて OK。

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| tooltip の具体的な文言と配置 | 要求に文言・配置の指定がない | 既存画面の tooltip 表記・配置規約を使い、なければ最小の説明文とする。 |

## Discretionary fill-ins

既存 formatter と既存 tooltip 実装が利用可能であればそれらを再利用する。tooltip の実装選択が未定でも、送信や他操作に影響しない局所状態という境界は維持する。

## Retries

0
