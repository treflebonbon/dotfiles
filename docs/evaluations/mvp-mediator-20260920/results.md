# MVP Mediator empirical tuning — 2026-09-20

続き: [再開評価（Iteration 5 以降）](resume.md)。以下は初回セッション終了時の記録。

[固定シナリオ・採点基準](protocol.md)。対象 baseline は `7302e42d9012b85027976a5c754aea629c620ce3`。実行者は履歴を継承しない `gpt-5.6-terra` / `high`。各シナリオ・各ラウンドで新しいエージェントを使う。

## 評価の範囲と制約

スキルが対象にする設計・変更メモの作成を実行し、成果物を親が固定基準で採点する。実アプリの動作・生成コードのコンパイル・自動発火率の評価ではない。チェックリストは実行者にも提示するため、測るのは明示された要件下での適用能力である。

この実行基盤の subagent 戻り値には `tool_uses` と `duration_ms` がない。steps・duration は取得不能とし、自己申告や壁時計から補完しない。全ラウンドを strict convergence の判定から除外する（`runtime/skill-harness.md` のローカル契約）。

Baseline の SHA-256:

- SKILL.md: `e6eac542e9f54054b295a5b6e4b92b6e0d6ffbf9f2f48c6a109a95259e45ba9f`
- references/tanstack-effect.md: `a446ebe95eb01feddbc8fd30041db60d9b66dcb07e629fcd3e5bbeeaf97a27d8`

## Iteration 0

Description の新規 UI 設計・既存 MVP の変更・競合フローの裁定・既存設計尊重・ROP への委譲を本文と照合した。各分岐に説明があり、Effect の参照も採用済みスタックに限定されている。不整合なし、変更なし。静的確認のため実行ラウンドの clear には数えない。

## Failure pattern ledger

既存の本対象の ledger は見つからなかった。実行結果から更新する。

## Iteration 1 — baseline execution

変更なし。Pattern applied: なし。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A: 在庫予約](r1-a.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [B: Query 小修正](r1-b.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [C: デバイス排他](r1-c.md) | × | 75% (4.5/6) | 取得不能 | 取得不能 | 0 | Planning / Execution（親の評価） |

親による項目別評価: A = [1,1,1,1,1,1]、B = [1,1,1,1,1,1]、C = [1,0.5,0,1,1,1]。各実行者の自己評価は全項目 ○、Trace all OK、曖昧点なしだった。成果物を読む採点では C の矛盾を検出したため、自己採点をそのまま採用していない。

### Structured reflection

C の **[critical] 項目2が partial**: 停止・解放待ちは表現したが、反復要求後に完了通知を受けられず、正常な切替を完遂できない。項目3の「explicit, consistent policy」は ×。項目6は要求された確認ケースを列挙しているので ○ とし、その期待動作の矛盾は項目2・3で採点した。

- Issue: `Switching` 中の追加要求で `requestId` を更新し、実行済みの停止・解放は継続する。その実行が返す旧 ID の `stopped` / `released` は捨てるため、状態が進まない。
- Cause: Planning で利用者の要求の世代と、継続して実行中の処理の識別を同じ ID にした。スキルは古い結果を除外する方針を述べるが、資源解放に必要な完了通知との違いが明示されていない。
- General Fix Rule: 利用者の最新要求と継続中の実行の寿命を区別し、実行を継続する間は完了通知との対応を保持する。表示結果の採用と、終了・解放の確認を同じ除外規則にしない。

実行者への事後確認でも不具合を認め、固定した teardown の ID と変更可能な待機先の識別を分ける案が返った。事後確認は baseline の成功率や retries を上書きせず、次ラウンドも新しい実行者を使う。

### Discretionary fill-ins

- A: 試行 ID の発行、取消直後の再送信許可、成功後の表示方針。UI 取消と物理的終了の待合せ要件はシナリオ固有の選択。
- B: 既存 tooltip 部品の優先利用、既存テストまたは手動確認の選択。
- C: latest-wins、同一所有者への要求は no-op。これらの選択自体は許容するが、選択した方針の整合性は成果物の責務。

### Ledger update / next fix

追加: **継続中の実行まで要求世代で無効化する**。

- Example: 追加要求で新しい ID を発行し、継続する停止処理の完了を古い結果として除外した。
- General Fix Rule: 上記のとおり、要求世代と実行の寿命・完了確認を区別する。
- Seen in: iter 1 / C。

次の修正はこの1テーマのみ。C 項目2の正常な終了・解放待ちと、項目3の一貫した反復要求方針を満たすために行う。連続 qualitative clear は 0。定量的収束は計測不能。

## Iteration 2 — 実行の寿命と要求の識別を分離

### Changes

SKILL.md「状態遷移と非同期処理」に1段落を追加。新しい要求で待機先だけを変更する場合、継続する停止・解放の完了通知との対応を維持する。表示に使わない結果でも、資源解放・次操作に必要な終了通知は処理する。

- Pattern applied: 継続中の実行まで要求世代で無効化する。
- 対応する判定文言: C-2「successful release before new acquisition」、C-3「explicit, consistent policy」。修正前に実行者もこの対応を説明した。
- 新しい SKILL.md SHA-256: `d1ed26c3efe4c8eeed9b820d9f047c33a09c20f79afa983396e80b0bfb5ad64d`。reference とチェックリストは変更なし。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r2-a.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [B](r2-b.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [C](r2-c.md) | ○ | 91.7% (5.5/6) | 取得不能 | 取得不能 | 0 | Formatting（親の評価） |

親の項目別評価: A/B = [1,1,1,1,1,1]、C = [1,1,0.5,1,1,1]。C は critical 項目を満たすので成功は ○ だが、通常項目3に部分達成がある。

### Structured reflection

前回の停止・解放 ID の問題は再発しなかった。新しい問題は C の条件記述の不整合。

- Issue: 説明は「現在の所有者への開始要求は無視」、遷移表と確認項目3は停止待ちの現在所有者への要求を解放後の再取得予約として受理する。
- Cause: Formatting で Active 状態に限る no-op 条件を、状態の限定なしにまとめた。実行者は曖昧点なし・全項目 ○ と自己評価したが、成果物中の方針は表と prose で一致していない。
- General Fix Rule: イベントの受理・無視条件を状態ごとに明示し、説明・遷移表・検証ケースの条件を一致させる。

B は具体的な formatter 名・コンポーネント名・テスト位置が未指定という Understanding の自己報告を返した。コード実装ではなく変更メモが成果物であり、これは対象スキルの曖昧さではなくシナリオの抽象度に由来する。識別子を捏造せず適切なメモを出しており、減点・スキル修正の対象にしない。

### Discretionary fill-ins / ledger / next fix

- A: cancelling 中は次の送信を受け付けず、終了後に再送信する方針。ID の生成方法と defect の観測先。
- B: tooltip の局所状態と既存構成を維持。
- C: latest-wins、失敗時は保留要求を破棄して明示再試行。

追加パターン: **状態の限定を落とした要約が遷移表と衝突する**。

- Example: Active での no-op を状態無指定で書き、Stopping の受理条件と矛盾。
- General Fix Rule: 上記のとおり、状態別の受理・無視条件を説明・表・確認で一致させる。
- Seen in: iter 2 / C。

次の修正は C-3「explicit, consistent policy」に対応する1テーマ。前回パターンとは異なり、ID の追加説明を増やす修正はしない。新たな曖昧点があるため qualitative clear は 0。

C 実行者の事後確認も項目3を partial とした。実行者は起点を Planning（Active と Stopping の通常の適用判断を整合させ損ねた）と診断し、スキル自体の意味の曖昧さとは区別した。親の Formatting 診断と併記する。追加する指示は誤った方針の訂正ではなく、成果物の整合確認を促すもの。少数試行なので文言変更と改善の因果は断定しない。

## Iteration 3 — 状態別の条件を整合させる

### Changes

本文に、イベントの受理・無視条件を状態別に記述し、説明・遷移表・検証ケースで一致させる1段落を追加。Pattern applied: 状態の限定を落とした要約が遷移表と衝突する。修正前に C 実行者が C-3 の判定文言との対応を説明した。固定シナリオと採点基準は変更なし。

SKILL.md SHA-256: `ff26c2fde2573f5bceca4e2352194d9689be2d2c5740e42478360a140c53b1aa`。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r3-a.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [B](r3-b.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [C](r3-c.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |

親の全項目評価は [1,1,1,1,1,1]。自己報告は全フェーズ OK、指示の曖昧点なし。C は `Owned` の同一所有者要求を no-op とし、`Draining` では `desired` の更新だけを行い `drainId` を維持する。過去2パターンの再発なし。

Discretionary fill-ins: A は取消終了後に再送信、B は既存 tooltip 部品とその標準操作、C は latest-wins と明示再試行を選択。いずれも固定要件の範囲でアプリケーション方針を具体化したもの。

Ledger 更新なし。次の修正なし。qualitative clear 1回。平均 accuracy は 100%（前回から +2.8ポイント）。同じ本文で次ラウンドを実行し、再現性を確認する。steps/duration がないため strict convergence は未判定。

## Iteration 4 — 同じ本文で再実行

Changes: なし。Pattern applied: 追加なし。対象 hash は iteration 3 と同一。新しい実行者に同じ固定課題だけを渡す。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r4-a.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [B](r4-b.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |
| [C](r4-c.md) | ○ | 91.7% (5.5/6) | 取得不能 | 取得不能 | 0 | Planning / Formatting（親の評価） |

親の項目別評価: A/B = [1,1,1,1,1,1]、C = [1,1,0.5,1,1,1]。critical 項目はすべて ○。平均 accuracy は 97.2%（前回から -2.8ポイント）。

### Structured reflection / discretionary fill-ins

C は遷移表で `ReleaseSucceeded` 後の最新要求を取得する一方、確認例「停止待ちに較正開始、次に録画開始」では、解放後の録画要求を同一所有要求として局所処理へ委ねる余地を残した。解放後は以前の所有者も取得が必要で、表と確認例が一致しない。C-3 の一貫性は partial。

- Issue: 完了済みの解放をまたいで、以前の所有者と現在の所有者を混同した検証記述。
- Cause: 状態別条件を表に書けても、確認例を各遷移に沿って照合し切れていない。
- General Fix Rule: 状態・現在の資源所有をイベントごとに追跡し、説明・表・検証ケースの条件を一致させる。

Ledger 再出現: **状態の限定を落とした要約が遷移表と衝突する**（iter 2、iter 4）。既存修正は条件の一致を要求したが、iter 4 の検証例への適用を保証できなかった。新規パターンとして増殖させない。

A は UI binding の試行 ID／終了通知契約と、取消要求直後か終了後かという再送信時点の未指定を報告。B は formatter の具体名・空値表記・tooltip の API 未指定を報告。いずれも架空アプリの未指定事実・製品方針であり、対応が必要な実装前提として保持する。対象スキルの新しい矛盾や達成項目の欠落とはみなさない。A は即時再送信を選び、終了待ちの旧試行を別管理する。C は latest-wins を選ぶ。

### Stopping decision

qualitative clear は 0 に戻る。2連続 clear は未達、strict quantitative convergence も metadata 不足で未確認。12回の独立実行で1件の critical failure を検出・解消し、2テーマを修正したが、成果物内の状態記述の不整合が再発した。追加の例外を積み重ねる費用と過適合リスクを考え、今回のチューニングは **resource cutoff** とする。現在版を保持し、残存問題を隠さない。これは `qualitative plateau` の宣言ではない。

未使用の H を最後に実行し、汎化の診断材料を追加する。この追加評価は収束ゲートの通過を意味しない。C の残存パターンに次回取り組むなら、同義の注意文追加より、遷移表とイベント列を実行検証する出力形式を別実験として評価する。

C の事後確認も partial に同意した。実行者は起点を Execution と診断し、「待機中の要求の採用規則を全状態遷移へ適用・照合しなかった」と報告した。親の Planning / Formatting 診断と併記し、元の自己報告を改変していない。

## Holdout H — 未使用シナリオの診断

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [H: 住所編集と背景更新](holdout-h.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | — |

親の項目別評価 = [1,1,1,1,1,1]。保存済みデータと下書きを分離し、既存 binding の単一送信制約と pending/result を再利用した。第二の状態機械・単一 connector・新規同期機構を追加していない。想定内エラーと defect/interruption の区別、成功後の下書き保持という仮定も明示した。

自己報告の未指定事項は成功後の UX、binding API、query 更新契機、実コード不在で、いずれも本課題の抽象度・製品方針に由来する。新しい instruction ambiguity なし。直近2ラウンド平均 98.6% からの低下はなく、今回の holdout では15ポイント以上の過適合シグナルは出なかった。ただし1件の設計メモで一般的な汎化を保証するものではない。

## 最終結果

| Round | A    | B    | C     | 平均  | critical failure |
| ----- | ---- | ---- | ----- | ----- | ---------------- |
| 1     | 100% | 100% | 75%   | 91.7% | C-2 partial      |
| 2     | 100% | 100% | 91.7% | 97.2% | なし             |
| 3     | 100% | 100% | 100%  | 100%  | なし             |
| 4     | 100% | 100% | 91.7% | 97.2% | なし             |

- 実行数: 固定3シナリオ × 4ラウンド + holdout 1件 = 13。原因確認の follow-up は再実行数に含めない。
- 採用した変更: SKILL.md に2段落（実行と要求の識別、状態別条件の整合確認）。reference・採点基準は不変。
- Ledger: 「継続中の実行まで要求世代で無効化する」は iter 1 に出現、iter 2〜4 では再発なし。「状態の限定を落とした要約が遷移表と衝突する」は iter 2 と iter 4 に出現し、残存。
- 終了理由: **resource cutoff**。2連続 qualitative clear は未達。`tool_uses` / `duration_ms` が取得不能のため quantitative convergence も未確認。qualitative plateau と報告しない。
- 限界: 成果物は設計メモで、アプリの実行検証や発火率測定ではない。自己報告は一貫して楽観的で、親の成果物採点が不具合を検出した。各条件1試行、同時対照なしのため、修正による因果効果・時間短縮・完全な正しさは主張しない。
- 次回: 残存パターンには、状態と資源所有をイベント列で追う実行可能な検証を別実験で導入する。定量的な収束判定には公式 usage metadata を返す実行基盤が必要。
