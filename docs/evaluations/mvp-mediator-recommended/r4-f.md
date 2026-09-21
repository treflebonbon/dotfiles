# F — 既存 Atom だけで足りるフォーム

## Deliverable

最小変更は、既存 binding が公開する `pending`、`result`、`error` を各表示箇所で購読して、送信中・完了・失敗を導出することだけである。フォームは従来どおり入力値と形式チェックを所有し、help tooltip の開閉はその View の局所状態に置く。複数の Context consumer は既存どおり表示状態を読める。

送信の二重実行抑止と古い結果の除外は、課題で確認済みかつテスト済みとされた既存 binding の保証を使う。`isSubmitting`、reducer、store、操作 ID、runtime は追加しない。業務検証はユースケースに残し、表示条件のために複製しない。

## 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`、`result`、`error` を既存 binding から導出するため、送信状態を重複保持する `isSubmitting`、reducer、store、独自 runtime は不要。 |
| 2 | ○ | 新しい排他・取消・解放待ちの制約がない。したがって Mediator class、CoR、Root の組み替え、操作 ID、状態機械には今回裁定する対象がない。 |
| 3 | ○ | tooltip の開閉は局所的な表示状態にとどめる。既存フォームの入力値・形式チェックと、複数 Context consumer による表示購読を変更しない。 |
| 4 | ○ | 業務可否はユースケースの実行時検証に残す。二重送信と古い結果の除外は Atom 採用そのものではなく、課題が明示した既存 binding の確認済み保証を根拠にする。 |
| 5 | ○ | 確認項目は、(1) 送信中に `pending` に対応する表示になること、(2) 完了時に `result`、失敗時に `error` の表示になること、(3) tooltip の開閉が送信表示・入力・他 consumer を変えないこと。実アプリ検査は未実行であり、成功とは扱わない。 |
| 6 | ○ | 今回は既存 binding が必要な非同期方針を満たし、競合フローもないため、形式的な Mediator／CoR／Root 層は判断を増やさない。緩和した Passive View では複数 consumer の購読を許すため、strict Passive View を理由に一律の購読移動や中継専用層も不要。 |

## YOUR Trace

### Understanding

既存 binding が送信状態と操作識別を所有し、二重送信抑止・古い結果の除外をすでに保証するフォームの表示整理である。新しい操作間制約はないため、表示状態を重ねず既存所有者から導出する。

### Planning

既存の `pending`、`result`、`error` を表示へ接続し、tooltip だけを View 内の局所状態として扱う。業務検証、入力値、形式チェック、binding の並行実行方針は既存所有者に残す。

### Execution

設計メモのみを作成した。実アプリ、実行モデル、API コードは作成・変更していない。

### Formatting

このファイルに対して `node_modules/.bin/oxfmt --check` を実行する。

## Unclear Issue / Cause / General Fix Rule

該当なし。

## Optional fill-ins

- 実装時は既存 binding の `pending`、`result`、`error` の実際の表示契約を確認する。
- 再送信中に前回結果を保持する binding なら、送信中表示と前回の完了・失敗表示を既存契約どおり区別する。

## YOUR Retries

0

## INPUT

- 対象スキル: `local-skills/mvp-mediator-architecture/SKILL.md`
- 対象スキル SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実際に読んだ参照: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
