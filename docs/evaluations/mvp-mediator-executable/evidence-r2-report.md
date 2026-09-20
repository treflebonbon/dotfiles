# MVP Mediator executable evidence R2

入力 skill の SHA256: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da` (`local-skills/mvp-mediator-architecture/SKILL.md`)

## E — exclusive device

成果物は `evidence-r2-e.mjs`。親 Mediator 相当の純粋 `transition` が排他、最新意図、停止・解放、失敗した段階だけの明示 retry、結果 ID の採用を所有する。`profile` は独立した子フローとして状態も effect も変えない。Effect 実行層は `acquire`、`stop`、`release` command を受けて I/O、エラー分類、中断、寿命管理を所有する。Model は業務上のデバイス可否を所有するが、この抽象モデルには含めない。

検証は `node evidence-r2-e.mjs` を実行して `E self-check: ok` を得た。検査は、取得中に `recording → calibration → recording` と意図を戻して取得を重複発行しないこと、停止・解放中の意図更新、遅延した failure の無視、停止 failure 後に `retry` が stop だけを新 ID で出すこと、profile no-op を assertion で確認した。最終的に `oxfmt --write` と `oxlint --config oxlint.config.ts` も対象二ファイルで成功した。

| # | 達成 | 根拠 |
| --- | --- | --- |
| 1 | ○ | acquiring / stopping / releasing / blocked で `start` は desired だけを最新化し、in-flight ID と effect を変えない。自己検査は取得中および停止・解放中に元 target へ戻す列を実行した。 |
| 2 | ○ | stop success は release、release success は次 acquire にだけ進む。各失敗は blocked にし、`retry` は `blockedStage` の command だけを新 ID で再発行する。 |
| 3 | ○ | `nextId` は stage / retry ごとに増加し、completion は現在の `id` と一致した場合だけ採用する。id 3 の stale failure は state 参照同一・effects 空を assertion した。 |
| 4 | ○ | モデルは command を返すだけで I/O、Promise、scheduler を持たない。実行層との境界と Effect の所有責務を上記に明記した。 |
| 5 | ○ | `profile` は `noop` であり、自己検査で結果全体が `{ effects: [], state: result.state }` と一致することを確認した。 |
| 6 | ○ | 実行済み assertion の結果を記録し、実行していない React/Effect 統合検査を通過したとは主張しない。 |

Issue: 未解決の仕様不明点はない。Cause: protocol が target、段階、結果採用条件を明示している。General Fix Rule: 新たな外部完了通知は、現在 stage の ID 照合を通すまで状態を進めない。

Trace: YOUR Understanding=OK（親の排他と子の局所性を分離）、Planning=OK（純粋 command model と独立 case を先に決定）、Execution=OK（Node assertion 実行済み）、Formatting=OK（oxfmt 実行済み）。裁量による補完は `blockedStage`、`stageTarget`、単調増加 `nextId` の三つだけ。自身の判断の再試行は 1 回（最初の lint の complexity / brace 指摘を責務別関数へ修正）。これは製品の `retry` event 回数ではない。

統合上の限界: 実際の Effect runtime、デバイス API、React View、Model の業務判定、実行層の中断・resource release は実行していない。この model はその境界に出す command と採用規則だけを検査した。

## B — display-only negative control

変更メモのみ。既存 React/TanStack Query と shared Context のまま、既存 total formatter を呼び、表示用コンポーネントに局所 tooltip open state を置く。tooltip は送信、他操作、Query 状態を変えない。Mediator、reducer、Atom、Effect、単一 connector、transition model は不要である。

比例した確認は、既存 formatter で total の表示値が変わらないこと、tooltip を開閉しても total・submit enabled 状態・Query request が変化しないこと、複数の既存 Context consumer がそのまま描画できること。この worktree には対象アプリを実装していないため、これらは提案した確認であり、アプリ試験を実行・成功したとは記録しない。

| # | 達成 | 根拠 |
| --- | --- | --- |
| 1 | ○ | Query と既存 project architecture を維持し、Effect / Atom / MVP 移行を提案しない。 |
| 2 | ○ | 表示整形と tooltip だけなので局所 View に留め、Mediator / reducer / global state / model を追加しない。 |
| 3 | ○ | Context consumer 数は裁定所有者の条件ではなく、既存の複数 consumer を維持する。 |
| 4 | ○ | 既存 formatter を再利用し、tooltip open は他操作に影響しない局所状態にする。 |
| 5 | ○ | submission と業務 logic の所有者を変えない。 |
| 6 | ○ | 上記の具体的な表示・開閉確認だけを提案し、未実行アプリ試験を pass と主張しない。 |

Issue: 未解決の仕様不明点はない。Cause: change は表示のみで、操作許可・取消・進行を変えない。General Fix Rule: 局所状態が他操作を変え始めた時点で、その操作の既存所有者へ裁定を戻す。

Trace: YOUR Understanding=OK（negative control の非追加要件を確認）、Planning=OK（コード不要と判断）、Execution=OK（メモのみという指定に一致）、Formatting=OK（report へ記録）。裁量による補完なし。自身の判断の再試行は 0 回。

統合上の限界: 対象の React screen、formatter、tooltip 実装はこの評価では与えられていないため、browser / Query integration の実行証跡はない。

## S — held-out search UI

成果物は `evidence-r2-s.mjs`。名前付きの結果採用 owner は純粋 `transition` で、入力 text ではなく単調増加 `latestId` により success / failure を採用する。既存 Query binding は request 実行と通常の pending / result を所有し、この model は追加の「どの completion を表示へ採用するか」だけを調整する。tooltip は View の局所状態で、search event を送らない。Effect、Atom、custom scheduler、取消が server を巻き戻すという仮定は導入しない。

検証は `node evidence-r2-s.mjs` を実行して `S self-check: ok` を得た。`cat` の id 1 の後に `dog` の id 2 を発行し、id 1 の success と failure が id 2 の pending state を変えないこと、id 2 の success は適用されること、同じ `dog` でも id 3 を発行し current failure が適用されることを assertion で確認した。最終的に `oxfmt --write` と `oxlint --config oxlint.config.ts` は対象二ファイルで成功した。

| # | 達成 | 根拠 |
| --- | --- | --- |
| 1 | ○ | `search` ごとに text にかかわらず新 ID を払い、`latestId` 一致だけで success / failure を採用する。自己検査は `dog` の再入力で id 3 を確認する。 |
| 2 | ○ | id 1 の stale success / failure が id 2 の pending state を変えないことを state 参照同一で assertion し、id 2 success と id 3 failure は実際に適用した。 |
| 3 | ○ | `query` effect は既存 binding への実行要求を表すだけで、model が持つ追加状態は latest identity と表示採用だけである。 |
| 4 | ○ | Effect / Atom / scheduler を置かず、取消を server rollback の証拠と扱わない。 |
| 5 | ○ | tooltip は event set に含めず局所 View の責務とし、結果採用 owner を `transition` と名付けた。 |
| 6 | ○ | Node assertion の実行結果を記録し、browser / Query runtime 統合を通過したとは主張しない。 |

Issue: 未解決の仕様不明点はない。Cause: repeated identical text の区別には値でなく request identity が必要である。General Fix Rule: 表示へ結果を反映する前に、completion ID が現在の request ID と一致することを確認する。

Trace: YOUR Understanding=OK（Query の実行と結果採用を分離）、Planning=OK（identity-only model を選択）、Execution=OK（Node assertion 実行済み）、Formatting=OK（oxfmt 実行済み）。裁量による補完は `error`、`pending`、`results` を観測可能にしたことだけ。自身の判断の再試行は 2 回（最初の lint 指摘の修正、続く destructuring 構文の修正）。これは検索 request やアプリ retry の回数ではない。

統合上の限界: 実 Query binding、network cancellation、server の継続、React render、tooltip は実行していない。model の assertion は request identity による結果採用規則だけをカバーする。
