# Empirical tuning continuation

続き: [第7ラウンド以降の追加評価](confirmation.md)。以下は前回セッション終了時の記録。

Baseline: `5bed6d408d70439594626dfaa9d9b869cdd33019`. 前回の [results](results.md) と failure ledger を引き継ぐ。固定課題 A/B/C、6項目の採点と critical 指定は [protocol](protocol.md) のまま。各回に履歴なしの新規 gpt-5.6-terra / high 実行者を使用する。

Iter 0 再確認: description と本文の範囲は一致。表示変更への移行強制を避け、制約のある UI フローだけを明示的に裁定する。静的確認は empirical clear に数えない。

今回の仮説: 「状態の限定を落とした要約が遷移表と衝突する」（iter 2、4）は、整合性という完成条件だけで照合手順がないため再発した。対象段落を、状態別の表からイベント列を追い、検証期待値を導く手順に置換する。C-3 の explicit, consistent policy と C-6 の concrete checks が直接の評価対象。C-2 の successful release before new acquisition も所有状態の追跡で確認する。

停止条件は従来どおり2連続 qualitative clear と未使用 holdout。tool_uses / duration_ms は取得不能なら推計せず、strict quantitative convergence は未確認とする。設計メモの評価であり実アプリのランタイム検証ではない。

## Holdout J — independent upload cards (frozen before dispatch)

A React/Effect screen contains two independent file-upload cards. They may upload concurrently through the same injected transport service; there is no global concurrency limit. Each card already has an operation binding exposing pending/result. Users can cancel one card and retry the same file while its prior completion may arrive late. The other card must continue unchanged. File-name formatting and help tooltip are local. The upload use case owns file-admissibility business rules. Produce a concrete responsibility/event/verification memo without framework API versions or application code.

1. [critical] Each card owns its submit/cancel/result decisions; shared transport does not introduce global exclusion or cancel the other card.
2. [critical] A cancelled prior attempt's success and failure cannot overwrite that card's retry, including the same file; operation identity includes the appropriate card/attempt boundary.
3. The use case owns runtime business validation; formatting and tooltip stay local.
4. Reuses per-card binding state and shared Effect execution/dependencies/lifetime facilities; only adds necessary coordination, not a duplicate scheduler or complete fetch-state model.
5. Distinguishes expected errors, defects and interruption; interruption does not promise remote rollback.
6. Gives concrete checks for simultaneous uploads, cancellation of one while the other continues, and stale success/failure after retry.

## Pre-fix structural review

新規 agent resume_mapping が変更前に C-3 の「Repeated requests during the transition have an explicit, consistent policy; a single owner makes it.」を直接の対応先と確認。C-6 に期待結果の根拠を与え、C-2 は既存の達成を維持する。以前の文は照合方法を欠き、解放後の要求対象を解放前の所有者と取り違えた。推奨された条件付き再生手順で既存段落を置換した。静的レビューは実行数・clear に含めない。

## Iteration 5

Changes: 状態別条件の整合性を要求する1段落を、条件付きのイベント列再生手順に置換。Pattern applied: 状態の限定を落とした要約が遷移表と衝突する。対象 SHA-256: `6ace6b48ea30aaf24a000057524c5a8cb70c972358094bc21446f0a75f062819`。reference は変更なし。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r5-a.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [B](r5-b.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [C](r5-c.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親の全項目評価は各 [1,1,1,1,1,1]。自己報告も全項目達成・Trace 全 OK。C は反復要求で pending を更新し、解放後は同じ録画でも Starting(recording) として再取得する。表と確認例の以前の矛盾は再現しなかった。停止・解放失敗から他方を取得する遷移もない。B は表示修正を局所に保った。

Structured reflection: 新しい instruction ambiguity なし。C の失敗後 Active 復帰は所有状態を確認できるという仮定であり、自己報告が未確認なら取得禁止の復旧状態が必要と限定している。実装時に確定すべき契約として残す。A の binding 契約・成功後 close、B の tooltip 文言、C の同一フロー再要求の意味もアプリケーション側の未指定事項。C の表・検証は再取得という選択で一致している。

Discretionary fill-ins: A は即時取消と試行 ID、C は latest-wins と解放後の再取得を選択。C は資源所有者・効果の列を出力したが、A は通常の遷移表と確認項目にまとめた。固定チェックリスト達成と手順形式の完全な遵守は同義ではない。

Ledger: 新規追加・再発なし。次の修正なし。平均100%（前回+2.8ポイント）、qualitative clear 1回。独立した新規実行者で同じ本文を再評価する。

## Iteration 6

Changes: なし。対象 hash と固定チェックリストは iteration 5 と同一。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r6-a.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | Formatting（評価依頼の言語） |
| [B](r6-b.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [C](r6-c.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親の全項目評価は各 [1,1,1,1,1,1]、自己報告も全項目達成・Trace 全 OK。A は取消終了待ち後に再送信し、古い成功・失敗の除外と解放完了を分離。B は既存構成を維持。C は shutdownId を保持して希望先だけを更新し、成功後に同じ録画も再取得する。失敗は ShutdownFailed に留める。状態表・反復要求の説明・確認例は一致した。

Structured reflection: 新しい対象スキルの曖昧点なし。A は日本語という評価依頼に対し英語の成果物を出したため Formatting の逸脱を記録する。原文を改変せず保存し、固定済みのアーキテクチャ採点へ言語項目を後付けしない。これは指示の不明瞭さではなく実行上の不遵守であり、対象スキルへの言語規則追加は行わない。

Discretionary fill-ins: A は binding の単一実行枠を解放後に再送信する保守的方針、C は latest-wins と停止・解放の両成功を統合通知する契約を選択。実装前には実際の binding / device API で確認する。

Ledger: 新規追加・既知パターン再発なし。次の修正なし。平均100%（前回差0）、対象スキルの qualitative clear 2回。手順の逐次再生記録は常に独立した表としては出力されておらず、完全な手順遵守は主張しない。未使用 holdout J で汎化を確認する。strict quantitative convergence は metadata 不足で未確認。

## Holdout J

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [J](holdout-j.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親の評価 [1,1,1,1,1,1]。カードごとの裁定と共有 transport の依存を分け、全体排他を作らなかった。cardId / attemptId で古い成功・失敗を除外し、終了通知の処理も維持した。Effect の実行基盤、既存 binding、局所表示、業務検証の責務も分離されている。自己報告は全項目達成・Trace 全 OK。未指定事項は binding の結果照合 API で、実装前の確認事項として記録されている。新しい指示の曖昧点なし。

直近2回平均100%から低下なし。今回の未使用課題では15ポイント以上の過適合シグナルは出なかった。

## 結果と終了判断

- 今回は独立実行7件（A/B/C × 2回 + J）。構造レビュー1件は実行数に含めない。初回と合わせて20件の設計メモ評価。
- 変更は SKILL.md の1段落の置換のみ。ADR-0063 の責務分担・Effect 優先・小修正の適用範囲は維持し、reference と既存採点基準は変更していない。
- Ledger: 「継続中の実行まで要求世代で無効化する」は iter 1 以来再発なし。「状態の限定を落とした要約が遷移表と衝突する」は iter 2、4 で観測、今回の iter 5、6 と J では再発なし。
- **qualitative plateau; quantitative convergence unverified**。固定3課題で2連続 clear と未使用 holdout 通過を確認。tool_uses / duration_ms が取得不能のため strict convergence は宣言せず、ローカル harness の上書きに従いこの時点で終了する。
- 限界: 架空アプリの設計メモに対する固定6項目評価で、実コード・ランタイム・自動発火の検証ではない。同時対照もなく、変更の因果効果や時間短縮を主張しない。A の出力言語逸脱、再生手順の出力形式のばらつき、実 binding 契約の未確認は残る。100% はこのチェックリストの達成率であり、完全性の保証ではない。
- 検証: skill frontmatter validator 成功、`bats tests/local-skills.bats` 18件成功。整形・相対リンク・差分のチェックも実施。前回報告済みの全体テストの環境由来失敗は、この文書変更で再実行・修正の対象にしていない。
