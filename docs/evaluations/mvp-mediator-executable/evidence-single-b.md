# Scenario B 実行メモ

## 入力

- INPUT `local-skills/mvp-mediator-architecture/SKILL.md` SHA-256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da`
- 与えられた Scenario B: 既存の React/TanStack Query 画面で合計を既存 formatter で整形し、送信などへ影響しないローカルなヘルプ tooltip を加える。

## 最小変更の決定

合計を表示している既存の View で既存 formatter を呼ぶ。tooltip の開閉だけを、その View のローカル状態で保持する。既存の shared Context は compound components が読むままにし、Query、Context、送信処理、業務規則には手を入れない。これは表示整形と他操作を変えない tooltip は View に置ける、というスキルの適用である。

## 凍結済み基準の照合

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 既存 React/TanStack Query とプロジェクト構成を維持する。Effect、Atom、MVP 移行を追加しない。 |
| 2 | ○ | 表示整形と tooltip の局所開閉だけなので Mediator、reducer、global state、実行可能な遷移 model は作らない。 |
| 3 | ○ | shared Context の複数 consumer を維持する。単一 connector や forwarding コンポーネントを要求しない。 |
| 4 | ○ | 合計は既存 formatter を再利用し、tooltip は当該 View のローカル状態で開閉する。 |
| 5 | ○ | 業務可否・送信・submit の既存 owner を変更しない。tooltip 操作はそれらへ event を送らない。 |
| 6 | ○ | 合計の formatter 出力と tooltip の表示・閉じる操作を対象に、既存の画面確認または既存 test があればその範囲で確認する。アプリのコード、起動方法、test command は入力されていないため、未実行の app test を成功と主張しない。 |

## Trace

### Understanding

これは制約付き・非同期フローではなく、既存データの表示整形と独立した補助 UI の変更である。したがって、MVP + Mediator を新設する契機はない。

### Planning

既存 formatter の呼出箇所と合計表示 View だけを変更対象にする。tooltip は既存のプロジェクト部品があれば使い、なければ表示 View 内の最小の開閉状態に留める。Context の購読構造と Query の所有者は保持する。

### Execution

Scenario B の入力に対し上記の責務配置を決定した。アプリコードを変更せず、state model も作成しなかった。これは Scenario B が「最小の変更/検証メモのみ」を要求し、アプリコード不要と明記しているためである。

### Formatting

このメモをローカル `oxfmt` で整形する。整形結果とファイル存在はコマンドで確認する。

## 検証

実行済み: この Markdown の `oxfmt` 整形と、その後のファイル確認。

提案するアプリ確認（未実行）:

1. 既存の合計値で画面を開き、表示値が既存 formatter の期待表記になることを確認する。
2. ヘルプを開き、説明が表示され、閉じる操作で消えることを確認する。
3. tooltip の開閉前後で submit の有効状態、送信結果、Query の取得状態が変わらないことを確認する。

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| formatter の関数名・既存 tooltip 部品・画面の確認手順は未特定 | Scenario B はアプリコードと test command を提供していない | 実装時に対象 View と既存 formatter を先に確認し、既存 tooltip 部品を再利用する。未実行の確認は未実行と記録する。 |

## 裁量で補った点

- 「local tooltip state」は React の当該表示 View に閉じる状態と解釈した。親や global store には昇格させない。
- formatter の仕様を新設せず、既存 formatter の出力を正とした。

## 再試行

なし。このシナリオでは、表示専用の変更に Mediator/state model を加えないという同じ判断を一度で確定した。
