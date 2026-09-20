# MVP Mediator executable evidence R1

入力スキル: `local-skills/mvp-mediator-architecture/SKILL.md`  
SHA256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da`

## E — exclusive device

責務: 親の純粋モデルが排他、最新意図、段階遷移、失敗後の明示再試行、結果採用を裁定する。子の recording/calibration の局所 UI と profile は裁定対象外である。Effect 実行境界は `acquire`/`stop`/`release` command を実行し、型付きエラー、defect、中断、寿命を所有する。

検証: `node docs/evaluations/mvp-mediator-executable/evidence-r1-e.mjs` を実行し、`E self-check: 2 cases passed`。初期状態から recording の取得・完了までの通常ケースと、意図更新、停止・解放、release 失敗、明示 retry、遅延完了、acquire 失敗、profile を別の新規状態で assertion 検査した。`./node_modules/.bin/oxfmt --config oxfmt.config.ts --write ...` は完了し、`./node_modules/.bin/oxlint --config oxlint.config.ts evidence-r1-e.mjs evidence-r1-s.mjs` は exit 0・指摘 0 だった。

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | acquiring/stopping/releasing/blocked の `start` は desired だけを更新し、同一 target へ戻しても既存 pending ID を維持して I/O を重複しない。 |
| 2 | ○ | stop 成功後だけ release を発行し、release 成功後だけ acquire を発行する。stop/release の失敗は blocked とし、`retry` は失敗した段階だけを新 ID で再発行する。 |
| 3 | ○ | state の単調増加 `nextId` が各 command/retry に fresh ID を渡す。pending ID と一致しない success/fail は state 参照をそのまま返す。 |
| 4 | ○ | モデルは plain object の command のみを出力し、I/O、scheduler、Effect runtime を持たない。責務を上記の parent/Effect に分離した。 |
| 5 | ○ | `profile` は state/effects を同じ参照のまま返す。子局所 UI はモデルに置かない。 |
| 6 | ○ | モデル、責務メモ、実行済み assertion の対象が一致する。ブラウザ、React、Effect runtime との統合は未実行である。 |

裁量補完: acquire 失敗時は desired を `null` に戻し、再取得は新しい `start` のみで始める。blocked 中の `start` は最新 desired を更新するが、外部処理を自動再試行しない。

## B — display-only negative control

責務: 既存の React/TanStack Query、共有 Context、compound components、既存 total formatter を維持する。tooltip の開閉だけを表示コンポーネントの局所 state に置く。提出・業務規則の所有者は変更しない。

検証: 要求どおりアプリコードと状態モデルは作成していない。実際の画面が指定されていないため、次の確認は実装時の具体的な確認項目であり、テスト実行済みとは主張しない: 既存 formatter の入力で total 表示が一致すること、help の開閉が total 表示以外・submit に影響しないこと。

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | メモは Query と既存 project architecture を保持し、Effect/Atom/MVP 移行を提案しない。 |
| 2 | ○ | tooltip は表示のみなので Mediator/reducer/global state/transition model を追加しない。 |
| 3 | ○ | 複数 Context consumer を保持し、単一 connector や forwarding を要求しない。 |
| 4 | ○ | 既存 formatter と tooltip の局所 state を使う方針である。 |
| 5 | ○ | 業務・submission の所有者に変更を加えない。 |
| 6 | ○ | formatter/tooltip の具体的な確認を列挙し、未実行の app test を成功と記録していない。 |

裁量補完: tooltip は hover/focus と Escape/blur の既存コンポーネント規約に従う。指定画面がないため実行結果は作らない。

## S — held-out search UI

責務: `SearchResultAcceptance`（`evidence-r1-s.mjs` の純粋モデル）が発行順の request ID で表示結果の採用だけを裁定する。既存 Query binding は request 実行と通常の pending/result を所有する。tooltip は局所表示 state のままで、検索要求の裁定に参加しない。Query cancellation は best effort であり、server 停止を意味しない。

検証: `node docs/evaluations/mvp-mediator-executable/evidence-r1-s.mjs` を実行し、`S self-check: 2 cases passed`。通常の current success と、alpha → beta → alpha の重複検索、stale success/failure、current success、次の pending 中の stale success、current failure を新規 state から assertion 検査した。

| # | 達成 | 理由 |
| --- | --- | --- |
| 1 | ○ | text ではなく `latestId` と event `id` を比較する。再入力した alpha は別 ID なので古い alpha は採用されない。 |
| 2 | ○ | 実行済み assertion が stale success/failure の state 参照不変と、current success/failure の適用を確認する。 |
| 3 | ○ | `query` effect は既存 binding への発行要求を表すだけで、追加状態は `latestId` による採用協調のみである。 |
| 4 | ○ | Effect/Atom/custom scheduler/promise rollback を導入しない。cancel の server 停止保証も主張しない。 |
| 5 | ○ | tooltip はモデル外の局所 state とし、結果採用の named owner は `SearchResultAcceptance` のみである。 |
| 6 | ○ | メモとモデルは ID 採用方針で一致し、self-check は実行済み。React/Query/browser/runtime 統合は未実行である。 |

裁量補完: 新しい検索の開始時は既存 result を保持し、Query binding の表示方針をモデルが再実装しない。current failure は error を更新するが result の保持/消去は binding 側の既存方針に委ねる。

## Trace

| 項目 | 状態 | 記録 |
| --- | --- | --- |
| Understanding | OK | E/B/S のみを読んで実施し、導入部・評価履歴・チェッカーは参照していない。 |
| Planning | OK | E は排他モデル、B は memo、S は結果採用モデルとし、既存実行層を置換しない範囲に限定した。 |
| Execution | OK | E/S の Node assertion はともに `2 cases passed`。指定 `oxfmt.config.ts` で整形し、指定 `oxlint.config.ts` の lint は exit 0・指摘 0。 |
| Formatting | OK | 指定された 3 ファイルだけを作成し、E/B/S ごとに責務、検証、六項目評価を分離した。 |

不明点: なし。  
Issue: なし。  
Cause: なし。  
General Fix Rule: 要件外の既存アプリの挙動を仮定せず、純粋モデルは必要な裁定状態だけを保持し、実行層と表示局所 state は既存所有者へ残す。

作業者の再試行: 0。E の `retry` は検査対象のアプリ event であり、作業者の判断を繰り返した回数には含めない。
