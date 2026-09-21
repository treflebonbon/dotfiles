# F — 既存 Atom だけで足りるフォーム

## Deliverable

最小変更は、フォーム画面と既存の Context consumer が、既存 binding の `pending`、`result`、`error` をそのまま購読して表示を導出することだけである。送信は既存フォームの入力値・形式チェックを通して、既存 binding の送信口へ渡す。 `pending` 中は送信中表示を優先し、完了後は binding の `result` または `error` を表示する。

help tooltip の開閉は tooltip View 内の局所状態に置く。開閉は送信、Atom、他の Context consumer に通知しない。業務検証はユースケースに残し、表示側で可否を再判定しない。

既存 binding が二重送信抑止、操作識別、古い結果の除外を確認済みである、という課題の前提を使う。Atom を採用していること自体を保証の根拠にはしない。

## 追加しないもの

- `isSubmitting`、別 reducer／store、独自 Effect runtime
- Mediator class、CoR の転送チェーン、Root の組み替え、操作 ID、状態機械
- strict Passive View のためだけの一律な購読移動や転送専用コンポーネント

今回、競合するフロー、排他、取消、解放待ち、新しい結果採用方針はない。既存 binding が既に裁定しているため、これらを重ねても判断や保証は増えない。

## 確認項目（未実行）

| 確認 | 操作 | 期待値 |
| --- | --- | --- |
| 送信中表示 | 形式チェック済みのフォームを送信する | binding の `pending` に従う送信中表示になり、settle 後に `result` または `error` の表示へ移る。 |
| 完了・失敗表示 | 成功と失敗をそれぞれ返す | 完了後だけ対応する結果を表示する。再送信中は送信中表示を優先し、既存 binding の確認済み保証により古い結果を採用しない。 |
| tooltip の独立性 | tooltip を開閉する | tooltip の表示だけが変わる。入力値、形式チェック、送信状態、結果、他の Context consumer は変わらない。 |
| 複数 consumer | フォームと別の Context consumer を同時に表示する | 両者が同じ既存 binding の状態を表示でき、追加の中継層や別状態を必要としない。 |
| 業務検証の境界 | 業務上無効な入力を送る | ユースケースが実行時に拒否し、View は返されたエラーを表示する。表示側に同じ規則を追加しない。 |

これは設計メモであり、アプリ検査は実行していない。上表は実装時に行う確認であり、成功結果ではない。

## 固定基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`／`result`／`error` は既存 binding から導出し、二重の送信状態・reducer・store・runtime を追加しない。 |
| 2 | ○ | 新しい競合制約がないため、Mediator class、CoR、Root 再編、操作 ID、状態機械を加えず、既存 binding の所有を保つ。 |
| 3 | ○ | tooltip は局所状態のままにし、複数 Context consumer とフォームの入力・形式チェックを維持する。 |
| 4 | ○ | 業務検証はユースケースに残す。保証の根拠は Atom の存在ではなく、課題が明示する既存 binding の確認済み保証である。 |
| 5 | ○ | 送信中、完了／失敗、tooltip 独立性を具体的な確認項目にした。アプリ検査は未実行と明記した。 |
| 6 | ○ | 追加不要なパターンを、排他・取消・新方針がないという今回の制約に結び付けた。strict Passive View 用の一律移動や中継層も要求しない。 |

## Trace

| 項目 | 状態 | 根拠 |
| --- | --- | --- |
| Understanding | OK | 課題の既存 binding の所有者と確認済み保証を前提として読んだ。 |
| Planning | OK | 必要な表示導出、局所 tooltip、既存の入力・業務検証境界を定めた。 |
| Execution | OK | 設計メモのみを作成し、アプリ／実行モデル／API の実装はしていない。 |
| Formatting | OK | `oxfmt` でこの出力ファイルだけを検査する。 |

## Unclear

| 項目 | 内容 |
| --- | --- |
| Issue | なし。課題が必要な所有者と既存 binding の保証を明示している。 |
| Cause | 該当なし。 |
| General Fix Rule | UI 表示に既存の状態で足りるなら、状態を導出し、追加の裁定状態や転送層を作らない。 |

## Discretionary fill-ins

- 表示の優先順位は `pending`、settle 後の `result`／`error` とする。これにより再送信中に前回の結果を進行中表示と混同しない。
- tooltip の局所状態には React の既存 `useState` を使う想定であり、共有 Atom には置かない。

Retries: 0

## Inputs read

- `local-skills/mvp-mediator-architecture/SKILL.md`
  - SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
- `docs/evaluations/mvp-mediator-followup/protocol.md` の `## F —` 節のみ
