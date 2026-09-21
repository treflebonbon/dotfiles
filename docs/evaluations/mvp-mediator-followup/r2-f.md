# F — 既存 Atom だけで足りるフォーム

## 最小変更案

- 送信中・完了・失敗の表示は、既存 binding が所有する `pending`、`result`、`error` から導出する。送信操作も既存 binding の入口を使う。
- フォームは現在の入力値と形式チェックをそのまま所有する。業務上の可否と実行時検証は Effect のユースケースに残し、表示条件のために再実装しない。
- help tooltip の開閉だけをフォーム View の局所表示状態に置く。開閉は送信、入力、既存 binding の実行状態へ影響させない。
- 複数の Context consumer は現在どおり同じ binding の表示状態を読める。厳密な Passive View 化を目的に、購読を一箇所へ移動したり中継専用層を設けたりしない。

既存 binding は、二重送信の抑止、操作識別、古い結果の除外をすでに保証しテスト済みである。この確認済み保証が今回の表示方針の根拠であり、Atom を使っている事実だけを根拠にはしない。

## 追加しないもの

- `isSubmitting`、別 reducer、別 store、独自 runtime
- Mediator class、CoR チェーン、Root の再編、追加の操作 ID、状態機械

これらは新しい排他、取消、解放待ち、または既存 binding で表せない結果採用の方針が生じたときだけ検討する。今回はいずれもないため、既存の所有者へ重ねる状態や裁定は不要である。

## 確認項目

| 確認 | 期待結果 | 実施状況 |
| --- | --- | --- |
| 送信開始 | binding の `pending` から投稿中表示になり、追加の `isSubmitting` はない | 未実行（実アプリなし） |
| 送信完了 | binding の `result` から完了表示になる | 未実行（実アプリなし） |
| 送信失敗 | binding の `error` から失敗表示になり、フォームの形式チェックと区別できる | 未実行（実アプリなし） |
| tooltip | 開閉が tooltip の局所表示だけを変え、送信・入力・業務フローを変えない | 未実行（実アプリなし） |
| 複数 consumer | 複数の Context consumer が既存 binding の表示状態を読める | 未実行（実アプリなし） |

未実行のアプリ検査は成功として扱わない。二重送信抑止と古い結果除外は、課題で確認済み・テスト済みとされた既存 binding の保証を再利用する。

## 凍結基準の評価

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`／`result`／`error` を既存 binding から導出し、送信状態の重複や独自 runtime を置かない。 |
| 2 | ○ | 競合フローや追加方針がないため、Mediator、CoR、Root 再編、操作 ID、状態機械を加えない。 |
| 3 | ○ | tooltip は局所状態に留め、既存フォームの入力・形式チェックと複数 Context consumer を保つ。 |
| 4 | ○ | 業務検証はユースケースに残し、確認済み binding 保証を根拠にする。 |
| 5 | ○ | 投稿中、完了・失敗、tooltip 独立性の確認項目を示し、実アプリ検査は未実行と明記した。 |
| 6 | ○ | 追加不要なパターンを、排他・取消・解放待ち・結果採用の不足がない制約に結び付け、購読移動や中継層を要求しない。 |

## Trace

| 項目 | 状態 | 内容 |
| --- | --- | --- |
| Understanding | OK | 既存 binding が送信状態と操作識別を所有し、フォームと tooltip の責務が独立している。 |
| Planning | OK | binding の表示導出と tooltip の局所状態だけに変更を絞る。 |
| Execution | OK | 設計メモのみを作成した。アプリ実装・実行モデル・API コードは作成していない。 |
| Formatting | OK | `oxfmt` で整形済み。 |

## Unclear

| 項目 | 内容 |
| --- | --- |
| Issue | 実アプリで `pending`、`result`、`error` が同時に存在する場合の既存表示優先順位は課題文にない。 |
| Cause | 表示仕様が未提示であり、追加の UI 方針を推測するとスコープを越えるため。 |
| General Fix Rule | 実装時は既存 binding／画面の表示規約を確認し、その規約で導出する。既存状態で表せない操作間制約が確認されたときだけ、最小の裁定状態を追加する。 |

## 任意の補足

今回の確認項目は設計提案であり、実行結果ではない。実装後は既存プロジェクトの検証手段で表の各項目を確認する。

## 記録

- Retries: 1（最初の読み取りコマンドは実行環境の Git 呼出規則により拒否され、`cd` 後の通常の `git status` に直して再実行）
- SKILL.md SHA-256: `6253f70613454fca7d5dd2c98a3bdab7c3053956651f62e89bf7ab4701cd4211`
- 参照した skill: `local-skills/mvp-mediator-architecture/SKILL.md`
- 参照した reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
