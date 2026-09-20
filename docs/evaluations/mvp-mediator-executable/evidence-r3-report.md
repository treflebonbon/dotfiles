# R3 実行証跡

入力スキル SHA-256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da` (`local-skills/mvp-mediator-architecture/SKILL.md`)。

## E — 排他的デバイス

成果物は [evidence-r3-e.mjs](evidence-r3-e.mjs)。親 Mediator 相当の純粋モデルが排他、最新意図、停止・解放・明示 retry と結果 ID の採否を所有する。子フローと `profile` はこの状態へ介入しない。Effect 実行境界は `acquire` / `stop` / `release` コマンドを受け取るだけで、モデルは I/O、scheduler、runtime を実装しない。

実行済み検査は `node evidence-r3-e.mjs` で、5 ケースすべて assertion を通過した。取得中・停止中・解放中の意図切替と元の対象への復帰、停止/解放失敗の blocked と段階限定 retry、ID 3 の遅延完了除外、取得失敗の idle 復帰、`profile` の不変を確認した。実アプリの Effect、通信中断、リソース解放、React 連携は未実行である。

| 凍結チェック | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | 全待機 phase の `start` は desired のみ更新し、取得中に元の対象へ戻っても重複 I/O を出さない。自己検査で acquiring / stopping / releasing を実行。 |
| 2 | ○ | stop 成功後のみ release、release 成功後のみ acquire。失敗は blocked、`retry` は記録済み failed stage のみを新 ID で再発行する。 |
| 3 | ○ | `nextId` は stage/retry ごとに増加し、現 operation ID 以外の完了は state/effects を不変にする。自己検査に stale ID 3 を含む。 |
| 4 | ○ | 純粋 transition はコマンド出力だけで Effect runtime を持たない。責務分離を上記に明記。 |
| 5 | ○ | `profile` は同一 state と空 effects を返す自己検査を実行。 |
| 6 | ○ | モデル、責務メモ、実行済み assertion が一致し、実 Effect 統合は未実行と明記。 |

## B — 表示専用の負例

変更・実装は不要である。既存 React/TanStack Query、共有 Context の複数 consumer、既存 formatter を維持し、合計だけを既存 formatter で表示する。ヘルプ tooltip は当該 View 内の局所 open/close state にし、送信や他操作へ通知しない。Effect、Atom、Mediator、reducer、グローバル state、単一 connector は追加しない。実アプリが提供されていないため、アプリ検査の成功は主張しない。

| 凍結チェック | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | Query と既存 project architecture を維持し、Effect/Atom/MVP 移行を要求しない。 |
| 2 | ○ | 表示整形と局所 tooltip のため、Mediator/reducer/global state/実行モデルを作らない。 |
| 3 | ○ | Context consumer の複数性を変更せず、forwarding connector を導入しない。 |
| 4 | ○ | 合計は既存 formatter、tooltip は View 局所 state を使う方針。 |
| 5 | ○ | 業務規則と送信は既存 owner のまま。 |
| 6 | ○ | 具体的な確認は formatter 出力と tooltip 開閉が送信状態を変えないこと。未実行の app test は pass と記載していない。 |

## S — 重複する検索

成果物は [evidence-r3-s.mjs](evidence-r3-s.mjs)。名前付きの結果採用 owner は検索 Mediator で、既存 Query binding が request 実行と request ごとの通常 pending/result を持つ。モデルは新しい検索に一意 ID を割り当て、binding に渡す `{ id, text }` と、最新 ID だけの completion 採用を表す。tooltip は View 局所であり、この policy 外である。

実行済み検査は `node evidence-r3-s.mjs` で、2 ケースすべて assertion を通過した。異なる文字列の重複検索で stale success/failure が newer pending/result を変えず current success が反映されること、同じ文字列を再入力しても ID 1 の success を除外し ID 2 の failure を採用することを確認した。Query cancellation、サーバー処理、browser/React runtime との統合は未実行である。

| 凍結チェック | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | 比較は text でなく単調増加 request ID。自己検査に同一 text の ID 1/2 を含む。 |
| 2 | ○ | stale success と stale failure は同一 state を返し、current completion のみ pending/result を更新する assertion を実行。 |
| 3 | ○ | 実行は既存 binding に委ね、追加状態は latest request ID と採用済み結果だけ。 |
| 4 | ○ | Effect/Atom/custom scheduler を追加せず、cancel が server work を巻き戻すとは扱わない。 |
| 5 | ○ | 結果採用 owner を検索 Mediator と明記し、tooltip は局所表示として分離。 |
| 6 | ○ | モデルと memo は一致し、自己検査を実行。browser/runtime 統合を未実行として明記。 |

## Trace

| 項目 | 状態 | 記録 |
| --- | --- | --- |
| Understanding | OK | 指定された E/B/S の凍結チェックリストだけを読み、E/S は実行モデル、B は memo とした。 |
| Planning | OK | E は排他 parent と実行 command、S は最新 ID による結果採用、B は局所表示に限定した。 |
| Execution | OK | Node built-ins だけで E 5 ケース、S 2 ケースの assertion を実行し成功した。 |
| Formatting | OK | `node_modules/.bin/oxfmt --check` と `node_modules/.bin/oxlint --config oxlint.config.ts` を両 MJS に実行し成功した。 |

不明点: Issue なし。Cause: 三つのシナリオは所有者・制約・検証範囲を十分に指定している。General Fix Rule: 実際の binding/runtime に接続する変更では、結果採用 ID を completion 境界まで伝播させ、ここで未実行の統合ケースを追加で実行する。

裁量補完: E は acquisition 成功後に最新 desired と異なるなら必ず stop → release → acquire とし、S は新 request 時に前の採用結果を `null` にして current request の pending を明示した。

実行者の再試行: 初回 `oxfmt --check` の不一致を実設定の `oxfmt` で整形して再確認した。初回 lint 指摘を設定準拠へ修正して再確認した。これは実行者の検証反復であり、E の製品イベント `retry` は数えていない。
