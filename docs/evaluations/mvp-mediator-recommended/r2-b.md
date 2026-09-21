# R2-B: Effect 未導入画面の表示変更メモ

## Deliverable

既存の合計値表示コンポーネントだけを変更する。

- 合計値は、現在その画面で使われている formatter に値を渡して表示する。
- 既存の局所 tooltip の実装・見た目を使い、同コンポーネント内の開閉状態だけで help を表示する。
- compound Context の各 consumer、TanStack Query、送信処理、業務規則は変更しない。
- Effect、Atom、Mediator、reducer、global state、実行モデル、単一 connector、中継専用コンポーネントは追加しない。

## 基準との照合

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. Query と既存設計を保つ | ○ | TanStack Query と compound Context をそのまま使い、Effect／Atom／MVP 移行を含めない。 |
| 2. 表示と局所 tooltip に限定する | ○ | 変更は合計値の整形と同一 View 内の tooltip 開閉だけであり、裁定・状態遷移・実行の仕組みを増やさない。 |
| 3. 複数 Context consumer を保つ | ○ | 既存 consumer の読み取り方を変えず、単一 connector や中継層を置かない。 |
| 4. formatter と局所 tooltip を再利用する | ○ | 新しい整形関数や tooltip 実装を作らず、画面で採用済みのものを使う。 |
| 5. 業務規則・送信制御の所有者を変えない | ○ | tooltip は表示だけを扱い、送信可否、送信状態、Query の取得・更新には関与しない。 |
| 6. 釣り合う確認を示し、未実行を明記する | ○ | 下記の表示・局所操作確認だけを提案し、アプリ検査は未実行として扱う。 |

## 確認メモ

- formatter に代表的な合計値を渡し、既存の通貨・桁区切り表記と同じ結果になることを確認する。
- help を開閉し、説明だけが表示・非表示になり、合計値、送信可否、送信中表示、Query の状態が変わらないことを確認する。
- tooltip のトリガーには既存パターンのアクセシブルな名前と関連付けを使う。

アプリコードの変更・実行は求められていないため、上記のアプリ検査は未実行。

## YOUR Trace

- Understanding: allOK
- Planning: allOK
- Execution: allOK（変更メモのみを作成）
- Formatting: allOK

## Unclear

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 対象コンポーネント、formatter、tooltip の具体名と import 元 | 課題は設計メモのみで、アプリコードの調査を要求していない。 | 実装時に既存の合計表示箇所と採用済み formatter／tooltip を検索し、同じコンポーネント内への最小変更にする。 |

## 任意補完

tooltip は既存のアクセシビリティ規約に従い、説明との関連付けを保つ。

## YOUR Retries

やり直し: 0 回。課題の 6 基準を満たす最小提案であることを確認した。

## INPUT

- target `local-skills/mvp-mediator-architecture/SKILL.md`（全文）: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実読 reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`（全文、React／TanStack Query に該当）
