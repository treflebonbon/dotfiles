# F — 既存 Atom だけで足りるフォーム: 最小変更メモ

## Deliverable

既存フォームの送信 UI は、既存の `@effect/atom-react` binding が公開する `pending`、`result`、`error` からそのまま導出する。`pending` の間は現在の送信ボタンを無効化して「送信中」を表示し、完了時は binding の最新 `result`、失敗時は binding の最新 `error` を表示する。再送信中は「送信中」を優先して表示するため、前回の成功・失敗を現在の進行状態と混同しない。送信処理は現在のフォーム submit handler から既存 binding の操作を呼ぶ。

help tooltip はフォーム View 内だけの `helpOpen` に保持し、開閉で Atom、送信、他の Context consumer、入力値、形式チェックを変更しない。既存の複数 Context consumer は現在どおり同じ binding を購読してよく、購読を一つの connector や中継コンポーネントへ集約しない。

追加しないものは、`isSubmitting`、送信結果用 reducer/store、独自 Effect runtime、操作 ID、状態機械、Mediator class、CoR チェーン、Root の組み替えである。二重送信抑止と古い結果の除外は、課題で確認済み・テスト済みとされた既存 binding の保証を使う。業務検証はユースケースに残し、表示条件のためにフォームへ複製しない。

## 受入基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | `pending`、`result`、`error` は既存 binding から導出し、送信状態を重複保持しない。 |
| 2 | ○ | 新しい競合・取消方針がないため、Mediator、CoR、Root 再編、操作 ID、状態機械を追加しない。 |
| 3 | ○ | tooltip はフォーム内の局所状態に限定し、既存フォームの入力・形式チェックと複数 consumer を維持する。 |
| 4 | ○ | 業務検証はユースケースの実行時検証に残す。Atom を使う事実ではなく、既存 binding の確認済み保証を根拠にする。 |
| 5 | ○ | 下記の投稿中・完了/失敗・tooltip 独立性を確認対象として明記し、アプリ検査は未実行である。 |
| 6 | ○ | 独立した新規制約がないため追加パターンは不要であり、緩和した Passive View のまま複数購読を許す。 |

## 確認項目

- 送信開始後、既存 binding の `pending` が真の間だけ送信ボタンが無効になり、「送信中」が表示される。
- 成功後、binding の最新 `result` が完了表示になる。失敗後、binding の最新 `error` が失敗表示になる。
- 失敗または成功の後に再送信すると、`pending` 表示が先に出て前回結果と現在の送信中を区別できる。
- tooltip を開閉しても、入力値、形式チェック、送信の `pending`、完了/失敗表示、他の Context consumer の表示が変わらない。
- 既存 binding の二重送信抑止と古い結果除外に対する既存テストを回帰確認する。

実アプリおよび実行モデルは未実装・未実行であり、上記は実装時に行う確認項目である。

## YOUR Trace

allOK: Understanding（F 節の既存 binding 保証、フォーム所有、tooltip 局所性を抽出）、Planning（既存所有者からの導出だけに限定）、Execution（メモのみ作成し、アプリ・モデル・API は変更しない）、Formatting（Markdown と表を整形）。

## Unclear

| 項目 | 内容 |
| --- | --- |
| Issue | なし。F 節が既存 binding の保証と変更対象を明示している。 |
| Cause | なし。追加の競合、取消、解放待ちがない前提である。 |
| General Fix Rule | 新しい操作間制約が現れた場合だけ、その制約を決める最小の既存所有者拡張を検討する。表示だけの変更では状態や裁定層を増やさない。 |

## 任意補完

成功と失敗の表示文言・配置は既存フォームの表示規約に従う。今回の設計判断に新しい設定値や共通部品は不要である。

## YOUR Retries

やり直し: 0 回。F 節の前提とスキルの「既存 binding が保証済みなら導出だけ」の指針が一致した。

## INPUT

- 対象 SKILL.md: `local-skills/mvp-mediator-architecture/SKILL.md`
  - SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実読した条件付き reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
  - React / Effect / `@effect/atom-react` を課題が指定しているため、SKILL.md の指示に従って全文を読んだ。
