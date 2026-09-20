# T — 一括選択とバックグラウンド更新

## 責務マップ

| 所有者 | 責務 |
| --- | --- |
| table selection binding | 選択 ID。更新してもその state を置換しない。 |
| query binding | 読込済み行と refresh。行オブジェクトの置換だけを行う。 |
| `DocumentListMediator` | archive click を受け、選択 ID の snapshot を既存実行境界へ渡す。 |
| archive use case | 実行時の権限検査と archive の実行。 |
| View | `formatDocumentTitle` のような表示整形と click 通知。複数 View が同じ Mediator に接続してよい。 |

production で追加する UI state はない。選択は既存 table binding、行/loading は既存 query binding を再利用する。`t.mjs` の `TableSelectionBinding`、`QueryBinding`、実行済み配列は検証用の模擬であり、実装に追加する state machine ではない。snapshot は Mediator が受理済みコマンドへ渡す immutable な引数で、保持する UI state ではない。

## 実行した確認と限界

`node docs/evaluations/mvp-mediator-executable/t.mjs` を実行した。refresh 後にも選択が `["a", "b"]` のまま、refresh だけでは archive が 0 件、archive click 後に選択を `["c"]` へ変えても受理済み command は `["a", "b"]`、use case が実行時に権限拒否することを assertion で確認する。

これは抽象モデルであり、React の再描画、table/query ライブラリの実 API、Effect runtime、実サービスの権限規則は未検証である。実装時には既存 binding と archive 実行境界へこの接続を行い、その統合テストを追加する。

## 基準

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | refresh は query rows のみを置換し、archive は明示 click の snapshot だけを実行する。後続選択は受理済み IDs を変えない。 |
| 2 | ○ | 権限は `ArchiveUseCase.archive` が実行時に検査する。Mediator/View に disabled 用の業務判定はない。 |
| 3 | ○ | table/query の状態を再利用する。模擬 binding と実行ログの用途、production 追加 state がないことを明記した。 |
| 4 | ○ | Mediator は既存 execution boundary の `runArchive` だけを呼ぶ。scheduler、取消、除外、retry は加えていない。 |
| 5 | ○ | 自己検証は refresh、click 時 snapshot、後続 selection change、実行時権限拒否を実際に実行する。未検証範囲も上記に限定して記した。 |
| 6 | ○ | 表示整形は `formatDocumentTitle` に局所化し、名前付き `DocumentListMediator` が command を経路化する。connector は強制していない。 |

## トレース

| 段階 | 状態 | 内容 |
| --- | --- | --- |
| Understanding（reading） | OK | holdout と適用条件により MVP/Mediator と React/Effect 参照を読んだ。 |
| Planning（approach） | OK | 既存 binding を独立した模擬にし、Mediator は snapshot の受理と実行境界への委譲だけにした。 |
| Execution（doing task） | OK | `t.mjs` とこの memo を作成し、自己検証を実行した。 |
| Formatting（report） | OK | 責務、実行済み確認、限界、六基準を記録した。 |

## 不明点と判断

| 項目 | 内容 |
| --- | --- |
| Unclear Issue | 既存 table/query binding と archive execution boundary の具体 API は与えられていない。 |
| Cause | holdout は architecture memo と抽象 self-check だけを要求し、アプリ実装を禁止している。 |
| General Fix Rule | 実装では既存 binding が選択を refresh で初期化しないこと、click 時の IDs を値として既存 use case 境界へ渡すことを確認する。権限規則は use case にだけ残す。 |
| 裁量判断 | ID は比較可能な安定出力のため snapshot 時に sort した。これは選択順を意味しない。archive の実行結果は use case の値をそのまま返す。 |
| retries count | 0 |
