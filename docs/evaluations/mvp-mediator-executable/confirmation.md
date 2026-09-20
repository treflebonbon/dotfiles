# 採用本文の追加確認 — 2026-09-21

後続の構造改訂実験は [evidence.md](evidence.md) を参照。以下は変更前本文での追加確認結果として保持する。

Baseline: `a1afdcf19a264931e3493176adc779e7cd8b1ea3`。対象本文 SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`。Iter 0: description と本文の適用範囲は一致。本文を変更せず、[前回の3連続 clear](structure.md) を引き継ぐ。

[固定 E/B/S](protocol.md) を新規 gpt-5.6-terra/high executor で各1回確認する。過去の成果物と親 checker を渡さない。各6項目、full=1 / partial=0.5 / absent=0、critical が全て full の場合だけ成功○。判定基準と checker は変更しない。tool_uses / duration_ms は提供されないため推計せず、strict convergence に含めない。再発がなければ未使用 holdout U を追加して qualitative plateau を確認する。

## Holdout U — mounted live feed lifetime（dispatch 前固定）

既存 React/Effect の相場パネル。既存 binding が feed ごとの最新値を保持し、Effect Scope が購読を管理する。mount ごとに新しい session ID で subscribe。unmount はその session の購読解除を実行層へ指示し、表示対象をなくす。解除中でも別 session で remount できる。同じ銘柄へ remount した場合も、古い session の値・失敗・解除完了は新 session の表示や購読を変更しない。旧購読の解除完了は実行層が旧資源の終了として処理する。解除指示は session ごとに一度、通常の unmount 重複は no-op。ここでは unsubscribe は最終的に成功し、通信中断はサーバー処理の巻き戻しを意味しない。独立したヘルプ表示は局所状態。

純粋な Node 抽象モデル、自己検査、責務と状態対応表の日本語メモを作る。実 Effect runtime や React integration は作らない。API は自由。

1. [critical] remount は新しい session identity を持ち、同じ銘柄でも旧値・旧失敗が現 session の表示を変えないことを assertion で示す。
2. [critical] unmount が旧 session の解除を一度だけ指示し、旧解除完了を処理しても新 session の購読や表示を失わないことを assertion で示す。
3. 最新値・購読寿命は既存 binding / Effect 実行層の責務として再利用し、抽象フィールドを模擬・追加裁定・検証専用に分類する。
4. UI の結果採用所有者を特定し、Effect Scope に資源終了を委譲する。独自 runtime を作らず、通信中断をサーバー巻き戻しと扱わない。
5. 正常 mount→値→unmount→解除完了を最初に独立 assertion で実行し、反復・遅延失敗・遅延解除の検査と分け、実測とメモを一致させる。
6. ヘルプ状態は局所に残し、実行した抽象モデル検証と未実行の React/Effect integration を区別する。

## 追加確認の親評価

B と S の自己報告は対象 skill ではなく、それぞれ scenario 文・生成モデルの SHA を記録した。診断 follow-up で、両者とも初回に指定 worktree の SKILL.md を `sed -n '1,240p'` で全文読んだと自己履歴から確認。S は条件付き reference も読んだ。再読による評価の補完や成果物の修正はしていない。親測定の対象 hash は冒頭の値で不変。この caller/report 契約の逸脱を、MVP スキルの固定6基準と分けて記録する。

- [B](confirm-b.md): 親 [1,1,1,1,1,1]、成功○、100%。Query と複数 Context consumer を維持し、既存 formatter と局所 tooltip に限定。具体的な確認観点とアプリテスト未実行の区別あり。Retries 0、Trace 全 OK、対象指示の新しい曖昧点なし。
- [S](confirm-s.md): 親 [1,1,1,1,1,1]、成功○、100%。追加裁定は latestRequestId のみ。binding 模擬に通常状態を保持し、採用 owner の ID 判定を completion 適用境界で用いる。親も [モデル](confirm-s.mjs) の通常成功、stale success、同文面の stale failure/current failure の assertion を再実行し PASS。Retries 0、Trace 全 OK、対象指示の新しい曖昧点なし。具体的な Query API の模擬は課題の裁量範囲。
- [U](confirm-u.md): 親 [1,1,1,1,1,1]、成功○、100%。親も [モデル](confirm-u.mjs) の3検査を実行し PASS。session ごとの binding から表示を導出し、旧資源の解除は旧 ID で完了、新 session は保持する。通常経路を最初に独立実行。helpOpen は抽象モデルの検証用局所 View 状態と明記され、feed の判断から参照されない。本番配置を FeedMediator 内とする提案ではない。実 Scope/React integration は未検証。旧 session ごとの解除済み Set を追加する裁量はあるが、固定基準を満たす。自己申告 Retries 0、対象指示の新しい曖昧点なし。親は成果物に対して実設定 oxlint も実行した。

U は E の最終出力待機中に dispatch した。本文や採点基準は変更していない。今後 U は使用済みであり、未使用 holdout として再利用しない。

- [E](confirm-e.md): 親 [1,1,1,1,1,0.5]、成功○（critical は全て full）、91.7%。[モデル](confirm-e.mjs) は独立 checker **52/52**、自己検査も成功。しかし memo の「通常の割込みなし経路を最初の assertion として実行した」は実装と異なる。selfCheck は `start recording → start calibration → start recording → ok 1` であり、独立した通常経路がない。これは E6 の「Model, memo and concrete checks agree」を満たさない。親 checker が通常経路を検査したことでは、実行者自身の報告不一致を救済しない。自己申告 Retries 1（stop と stopping の混同を自己検査で修正）。親が観測した弱い phase は Execution / Formatting、自己報告 all OK とは分ける。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase（親評価） |
| --- | --- | --- | --- | --- | --- | --- |
| E | ○ | 91.7% | 取得不能 | 取得不能 | 1 | Execution / Formatting |
| B | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| S | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| U | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

固定 E/B/S 平均は97.2%。Uは100%で過適合閾値の15ポイント低下はない。ただしEの既知不一致が再発したので、今回の qualitative clear は0。前回3連続 clear の結果は保存するが、今回それを4連続へ延長しない。critical の欠落はない。

## 構造化診断と終了判断

Eへの診断 follow-up は再評価に数えず、成果物も修正しない。

- Issue: 反復要求を含む列を通常経路として実行済みと報告した。
- Cause: 実行者は冒頭要件を読んでいたが、E1の「in-flight targetへ戻る」列に通常経路も兼ねさせ、最初のstartのeffect assertionを完了までの通常経路と誤認した。memo作成時に全イベント列と突合しなかった。
- General Fix Rule（実行者）: 通常経路を他ケースと共有しない独立assertionで先に完結させ、memoには実際のイベント列と期待・実測を転記する。
- 対応する固定判定文言: E6の「Model, memo and concrete checks agree」「report its actual result」。独立checkerの合格で自己報告の誤りを帳消しにしない。

Ledger: 既知の「通常経路の独立assert欠落」「動作・説明・確認の不一致」に今回Eを追記する。新しいパターンとして重複登録しない。前回の構造変更で要件を冒頭へ移しても今回防げなかった理由は、指示の見落としではなく、複数ケースの意味上の同一視と報告時の突合不足だった。表示stateの二重保持、execution ID喪失は今回再発していない。

**今回の終了区分は resource cutoff。追加の収束認定はしない。** 以前の18実行と複数構造候補を経て既に明文化・冒頭配置した内容について、今回4件の新規実行で指示遵守のばらつきが残ると分かった。同じ意味の文言をさらに追加して改善する根拠は得られていないため、対象本文とreferenceは変更しない。これは「問題なし」や「quantitative convergence」を意味しない。現在の推奨は採用本文を保ち、重要な生成物の完了判定には独立した動作検査と報告・コード照合を用いること。今回のように欠落を検出できる評価を、文言追加で代替しない。

実行者のtool_uses/duration_msがないため、速度・コスト改善も主張しない。新規実行4件と診断follow-up3件を区別する。Uを含む実行可能モデルは抽象検証であり、実React/Effect/Query integrationの保証ではない。

## 最終検証

親は3モデルの自己検査、Eの固定checker52/52、実設定oxlint/oxfmt、git diff --checkを確認した。対象本文・reference・checkerは開始時から不変。編集は評価記録と生成証跡だけで、skill配布やアプリ統合の変更はないため、変更のない配布テストの再実行は行わない。タスクworktree内に保存し、HOME配備・push・PR作成は行わない。
