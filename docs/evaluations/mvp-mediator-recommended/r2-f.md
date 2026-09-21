# F — 既存Atomだけで足りるフォーム: 変更メモ

## Deliverable

既存の `@effect/atom-react` binding が持つ `pending`、`result`、`error` と操作識別を、現在のフォーム表示へそのまま接続する。送信ボタンの無効化と投稿中表示は `pending` から導出し、完了・失敗表示は `result` と `error` から導出する。送信は既存フォームの検証済み入力を既存の送信口へ渡し、業務検証はユースケースに残す。

help tooltip の開閉だけは、その View の局所表示状態として保持する。複数の Context consumer は現在どおり同じ表示状態を購読し、フォームの入力値・形式チェックの所有者も変更しない。

`isSubmitting`、reducer、store、操作 ID、実行 runtime、Mediator class、CoR、Root 再編、状態機械、中継だけの connector は追加しない。今回の二重送信抑止と古い結果の除外は、課題で確認済みとされた既存 binding の保証で満たされるためである。

## 確認項目（未実行）

| 確認 | 期待結果 |
| --- | --- |
| フォームを一度送信する | binding の `pending` により投稿中表示になり、送信操作は抑止される。 |
| 送信が成功する | `result` から完了表示が出る。 |
| 送信が失敗する | `error` から失敗表示が出る。 |
| tooltip を開閉する | tooltip だけが変化し、送信状態、入力値、形式チェック、他の Context consumer の表示は変化しない。 |
| 複数 Context consumer を表示する | 同一 binding の表示状態を読め、購読を一箇所へ移すための中継層は不要である。 |

これは設計メモであり、実アプリの検査は未実行である。上記は成功結果として扱わない。

## 基準判定

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`、`result`、`error` は既存 binding から導出し、二重の送信状態・reducer・store・runtime を追加しない。 |
| 2 | ○ | 新しい競合、取消、解放待ちがないため、Mediator class、CoR、Root 再編、操作 ID、状態機械のいずれも必要ない。 |
| 3 | ○ | tooltip は局所表示状態に留め、既存フォームの入力・形式チェックと複数 Context consumer を維持する。 |
| 4 | ○ | 業務検証はユースケースに残す。表示は Atom の存在そのものではなく、課題で確認済みの binding の二重送信抑止と古い結果除外の保証を根拠にする。 |
| 5 | ○ | 投稿中、完了、失敗、tooltip 独立性の確認項目を示し、アプリ検査が未実行であることを明記した。 |
| 6 | ○ | 追加不要な層は、競合する操作方針がなく既存 binding が必要な送信制約を満たすため不要である。strict Passive View を理由に購読を一律移動したり、中継専用層を作ったりしない。 |

## YOUR Trace

allOK: Understanding / Planning / Execution / Formatting

## Unclear

| 区分 | 内容 |
| --- | --- |
| Issue | なし。 |
| Cause | 課題の前提で、既存 binding の所有状態と保証が明示されている。 |
| General Fix Rule | 新しい操作間制約がない限り、既存 binding の状態と保証を再利用し、表示専用の状態や裁定層を重ねない。 |

## YOUR Retries

0 回。要件の読み直し・案のやり直しは不要だった。

## INPUT

- target `local-skills/mvp-mediator-architecture/SKILL.md`: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実読 reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
