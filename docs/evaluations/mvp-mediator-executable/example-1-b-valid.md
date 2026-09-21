# Example 1-B: valid local display change

## 判定

既存の React/TanStack Query 画面で、既存 formatter により total を整形して表示し、局所的なヘルプツールチップを追加する。ツールチップの開閉は表示だけを変え、送信・mutation・他の業務操作には接続しない。プロジェクトの構成は保持する。

## 凍結基準の自己報告

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1. Query/project を保持し、Effect/Atom/MVP へ移行しない | ○ | 既存 React/TanStack Query をそのまま使う表示修正であり、依存関係・アーキテクチャを変更しない。 |
| 2. 表示を局所に保ち、Mediator/reducer/global state/executable model を追加しない | ○ | total の整形表示とツールチップ開閉だけで、他操作の許可・取消・進行を変更しない。 |
| 3. 複数の Context consumer を許し、単一 connector/転送を強制しない | ○ | compound components は共有 Context を直接読める。裁定が必要な新規イベントもないため connector は増やさない。 |
| 4. 既存 formatter と局所 tooltip を使う | ○ | total は既存 formatter を再利用し、tooltip は当該 View の局所表示状態だけを持つ。 |
| 5. 無関係な業務・送信の所有者を変えない | ○ | submission/mutation と業務規則には変更を加えない。 |
| 6. 具体的で相応な format/tooltip 確認を示し、未実行の app test を成功と主張しない | ○ | 本メモを `oxfmt --check` で確認する。アプリコードや実行モデルは対象外のため、アプリテストは未実行として記録する。 |

## Trace

| 段階 | 判定 | 記録 |
| --- | --- | --- |
| Understanding | OK | これは状態制約・資源所有・反復要求を含まない局所表示変更である。 |
| Planning | OK | 既存 formatter を呼び、tooltip の開閉を View 内に閉じる。既存 Context 購読と送信所有者を維持する。 |
| Execution | OK | アプリコード・モデル・依存関係は変更しない。この評価メモのみを作成する。 |
| Formatting | OK | ローカル `oxfmt` をこの Markdown に実行し、続けて `--check` を実行する。 |

## 確認

| 確認 | 期待結果 | 実測結果 |
| --- | --- | --- |
| `oxfmt --check docs/evaluations/mvp-mediator-executable/example-1-b-valid.md` | Markdown が整形済み | 実行予定。 |
| tooltip を開閉する手動確認 | help の表示だけが変わり、送信・mutation・他操作は起動しない | アプリコードを変更しない評価のため未実行。アプリテスト成功は主張しない。 |
| total の表示確認 | 既存 formatter の出力を表示する | アプリコードを変更しない評価のため未実行。 |

## 不明点・一般化規則

| 項目 | 記録 |
| --- | --- |
| Issue | tooltip の実際の実装箇所・既存 formatter 名は、この blank-slate 評価では未指定。 |
| Cause | シナリオは変更の妥当性評価だけを求め、アプリコードの調査・編集を範囲外としている。 |
| General Fix Rule | 表示専用の整形と tooltip は既存 View/formatter に置く。送信、排他、取消、進行を変える場合だけ、その既存フローの裁定所有者を確認する。 |

## 任意の補完と再試行判断

- 任意の補完: tooltip は当該 View 内の局所 open/close 状態であるとした。利用者操作や送信状態を変えないことが前提である。
- 再試行: なし。凍結基準をすべて満たし、追加の実装・モデル・テストはシナリオ外である。

## 入力

- `local-skills/mvp-mediator-architecture/SKILL.md` SHA256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 読了した参照: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
- 未読の参照: `references/model-verification.md`（抽象実行モデルを作成しないため非該当）
