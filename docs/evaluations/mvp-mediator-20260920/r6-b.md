# Scenario B — 既存 Query UI の保守: 変更メモ

## Deliverable

既存の合計表示コンポーネントで、現在使われている formatter に合計値を渡して表示する。ヘルプ用ツールチップは同じ表示コンポーネントに置き、開閉状態もそこで局所的に持つ。

TanStack Query の取得・キャッシュ・再検証の扱い、共有 Context と compound components の複数購読、既存の送信と業務ロジックは変更しない。Effect、Atom、Mediator、reducer、グローバル UI 状態は追加しない。

## 要件達成

| 要件 | 判定 | 理由 |
| --- | --- | --- |
| 1. Query／プロジェクト構成を維持し、Effect／Atom／MVP 移行を要求しない | ○ | 既存の TanStack Query とプロジェクト規約をそのまま使い、表示の小修正だけを行う。 |
| 2. 表示専用の変更を局所化し、Mediator／reducer／グローバル UI 状態を追加しない | ○ | 合計の整形は既存表示箇所、ツールチップの開閉はそのコンポーネントの局所状態に限定する。ほかの操作の許可・取消・進行を変えない。 |
| 3. 複数 Context consumer を維持し、単一 connector や中継階層を要求しない | ○ | 既存の共有 Context を読む compound components はそのままにする。今回の表示追加のための pass-through コンポーネントは不要である。 |
| 4. 既存 formatter を使い、ツールチップ状態を局所化する | ○ | 新しい整形ロジックを作らず、既存 formatter の出力を表示する。ツールチップの開閉は表示コンポーネント内だけで完結する。 |
| 5. 無関係な業務／送信ロジックを移動・書き換えない | ○ | 合計表示とヘルプ表示以外、特に submission の実装・所有者・状態遷移には触れない。 |
| 6. 整形とツールチップの振る舞いを適切な粒度で確認する | ○ | formatter の出力表示、ツールチップの開閉、開閉によって submission や Query 状態が変わらないことを確認する。 |

## 確認項目

1. 代表的な取得済み合計値を表示し、画面の文字列が既存 formatter にその値を渡した出力と一致することを確認する。
2. ヘルプのトリガーを操作してツールチップが表示され、既存のツールチップの閉じる操作で非表示になることを確認する。
3. ツールチップの開閉前後で送信操作の可否・進行表示、および TanStack Query の取得状態・キャッシュを変更しないことを確認する。

## Trace

Understanding／Planning／Execution／Formatting: OK。表示整形と局所的な説明表示だけの依頼として扱い、既存の取得・送信・Context 構成を保つ最小変更に限定した。

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| formatter、合計表示コンポーネント、ツールチップ primitive の具体名は未指定 | シナリオは構成と変更目的だけを与え、実装ファイルを指定していない | 実装時に既存の合計表示箇所と formatter の呼出しを確認し、その既存 primitive を使う。新しい依存関係や状態共有は導入しない。 |

## Discretionary fill-ins

既存のツールチップ部品に標準のキーボード操作・フォーカス復帰・閉じる挙動がある場合はそれを使う。独自の開閉制御は、既存部品が必要とする最小限に留める。

## 実行記録

- Retries: 0
- tool_uses: unavailable（dispatch usage metadata 未提供）
- duration_ms: unavailable（dispatch usage metadata 未提供）
