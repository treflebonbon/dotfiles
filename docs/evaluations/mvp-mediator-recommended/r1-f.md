# F — 既存 Atom だけで足りるフォーム: 変更メモ

## Deliverable

既存の `@effect/atom-react` binding が持つ `pending`、`result`、`error` をフォームと各 Context consumer の表示へそのまま導出する。送信ボタンと送信中表示は `pending` を参照し、完了表示は `result`、失敗表示は `error` を参照する。二重送信抑止と古い結果の除外は、確認済みの binding の保証を利用する。

フォームが持つ入力値と形式チェックは変更しない。help tooltip の開閉は当該 View の局所状態に保ち、送信状態、入力値、業務フローを変更しない。業務検証は既存ユースケースに残す。

新しい `isSubmitting`、reducer、store、runtime、Mediator class、CoR チェーン、Root 再編、操作 ID、状態機械、中継専用層は追加しない。今回は排他・取消・解放待ちの方針がなく、binding が必要な送信制約をすでに所有しているためである。strict Passive View を求めるためだけの一律な購読移動もしない。

確認項目（未実行）:

- 送信開始時に送信中表示が `pending` から表示され、連続した送信操作が binding の既存保証により重複実行されないこと。
- 成功時は `result` による完了表示、失敗時は `error` による失敗表示になること。
- tooltip の開閉がフォームの入力値・形式チェック・送信中表示・完了/失敗表示へ影響しないこと。
- 複数の Context consumer が同じ既存 binding の表示状態を読めること。

実アプリおよび実行モデルは課題の対象外のため、上記は確認すべき項目であり、実行済みの成功結果ではない。

## 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`、`result`、`error` を既存 binding から導出し、二重の送信状態や runtime を増やさない。 |
| 2 | ○ | 新しい操作間制約がないため、Mediator class、CoR、Root 再編、操作 ID、状態機械を加えず既存の所有者を維持する。 |
| 3 | ○ | tooltip は局所状態に留め、複数 Context consumer とフォームの入力値・形式チェックをそのまま使う。 |
| 4 | ○ | 業務検証をユースケースに残し、表示条件へ再実装しない。Atom 一般ではなく、課題で確認済みの binding の保証を根拠にする。 |
| 5 | ○ | 送信中、完了/失敗、tooltip 独立性、複数 consumer の確認項目を示し、未実行のアプリ検査を成功と記載していない。 |
| 6 | ○ | 追加しないパターンを、既存 binding の保証と追加の排他・取消方針がないという今回の制約に結び付け、購読移動や中継層を要求していない。 |

## YOUR Trace

all OK: Understanding / Planning / Execution / Formatting。

## Unclear

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| なし | 課題の前提が、binding の所有状態と確認済み保証、フォーム・tooltip の責務を明示している。 | 新しい操作間制約、取消、解放待ちが追加された場合だけ、その不足する裁定状態と所有者を設計する。 |

## 任意補完

再送信中に前回の成功・失敗を残す既存 binding であれば、`pending` と前回結果を区別して表示する。これは新しい状態を作らず既存表示値の条件分岐で行う。

## YOUR Retries

0 回。課題の前提と skill の既存 binding 優先規則が一致していたため、やり直しは不要だった。

## INPUT

- 課題: `docs/evaluations/mvp-mediator-recommended/protocol.md` の「F — 既存Atomだけで足りるフォーム」節のみを抽出して読んだ。
- Skill: `local-skills/mvp-mediator-architecture/SKILL.md`
- Skill SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実読 reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
