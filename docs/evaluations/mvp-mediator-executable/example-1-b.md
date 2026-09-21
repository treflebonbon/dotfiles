# Example 1-B: display-only negative control

## 変更方針

既存の React と TanStack Query の画面構成、shared Context、および compound components は維持する。合計値は既存 formatter に渡して表示する。ヘルプは表示コンポーネント内の局所 `isHelpOpen` 状態だけで開閉し、送信、Query、他の操作には通知しない。

Effect、Atom、MVP への移行、Mediator、reducer、global state、単一 connector、Context の forwarding component、実行可能な遷移モデルは追加しない。送信と業務規則は既存の Model／ユースケースと送信フローの所有者に残す。

## 凍結基準の判定

| # | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | TanStack Query と既存プロジェクト構成を保持し、Effect／Atom／MVP 移行を提案しない。 |
| 2 | ○ | 合計の整形とヘルプ tooltip は表示コンポーネント内に留め、Mediator、reducer、global state、実行可能な状態モデルを持ち込まない。 |
| 3 | ○ | shared Context を読む複数の compound components をそのまま許容し、単一 connector や forwarding を要求しない。 |
| 4 | ○ | 合計は既存 formatter を再利用し、tooltip の開閉は他の操作を変えない局所状態にする。 |
| 5 | ○ | 業務規則と送信ロジックには触れず、既存の所有者に残す。 |
| 6 | ○ | 下記の具体的な表示確認を定義する。アプリコードも実行環境も与えられていないため、アプリテストは未実行であり、成功とは主張しない。 |

## 検証記録

| 検査 | 期待結果 | 実測結果 |
| --- | --- | --- |
| Query から得た total の表示 | 既存 formatter が返す文字列をそのまま表示する。 | 未実行（対象アプリコードなし）。 |
| tooltip を開閉する操作 | ヘルプの可視状態だけが変わり、合計値、Query の取得状態、送信状態は変わらない。 | 未実行（対象アプリコードなし）。 |
| 複数 Context consumer の表示 | 既存の各 consumer が shared Context を継続して読める。単一 connector や forwarding は不要である。 | 未実行（対象アプリコードなし）。 |

提案する実行確認は、既存の画面テストまたはブラウザ確認で formatter の出力、tooltip の開閉、開閉前後で送信操作と Query の pending/result に変化がないことを確認する。今回、アプリテストを実行したという主張はしない。

## トレース

| 段階 | 記録 |
| --- | --- |
| Understanding | Scenario B は、既存 React/TanStack Query 画面の表示専用変更であり、tooltip は他操作へ影響しない局所状態であると理解した。 |
| Planning | 既存 formatter を再利用し、表示コンポーネント内の局所 tooltip 状態だけを使うメモにした。既存 Query、Context、compound components、送信所有者は変更しない。 |
| Execution | アプリコード、状態モデル、MVP/Mediator、Effect、Atom は作成していない。このメモのみを作成した。 |
| Formatting | 凍結基準6件の判定、具体的な検証と未実行状態、入力 SHA256、裁量補完、反復判断を記録した。 |

## 不明点の扱い

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| formatter の関数名、tooltip の既存部品、対象画面のテスト経路は不明。 | Scenario B は既存アプリの構造だけを与え、実ファイルや実行環境を指定していない。 | 実装時は対象画面で既存 formatter と既存 tooltip の慣例を検索して再利用し、表示だけの状態が他操作へ影響しない最小の確認を既存テスト経路で実行する。 |

## 裁量補完

- tooltip はキーボード操作でも開閉または到達できる既存部品を使う。これは表示専用の範囲でのアクセシビリティ上の補完である。
- formatter の返値は再整形せず、そのまま描画する。表示規則を二重定義しないためである。

## Re-tries: 繰り返した判断

- なし。Scenario B の表示専用制約により、最初の方針から状態遷移モデルや裁定層を追加する必要はなかった。

## 読んだ入力の SHA256

| 入力 | SHA256 |
| --- | --- |
| `local-skills/mvp-mediator-architecture/SKILL.md` | `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f` |
| `local-skills/mvp-mediator-architecture/references/tanstack-effect.md` | `a446ebe95eb01feddbc8fd30041db60d9b66dcb07e629fcd3e5bbeeaf97a27d8` |
