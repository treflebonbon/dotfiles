# Additional confirmation

続き: [実行可能モデルを使う別実験](../mvp-mediator-executable/results.md)。以下の既存採点と終了判断は変更しない。

Baseline: `c77a50d0f6e422fcc31acdcd4f72299f6653430f`。ユーザーの再実行依頼により [前回の評価](resume.md) を継続する。Iter 0: description と本文の適用範囲に差分なし。本文の SHA-256 は `6ace6b48ea30aaf24a000057524c5a8cb70c972358094bc21446f0a75f062819`。変更を先に加えず、[固定 A/B/C](protocol.md) の第7ラウンドで3連続 clear を確認し、新しい holdout K を実行する。前回の2連続結果を引き継ぐため、問題がなければ余分な反復はしない。

モデル、fresh executor、親の独立採点、critical 指定、達成率計算、metadata 取得不能の扱いは既存 protocol と同じ。既存 ledger 2件を継続監視する。採点基準は変更しない。

## Holdout K — library-independent VSA UI

A Svelte frontend already uses vertical feature slices and hexagonal application use cases. It has no React, TanStack or Effect. In a document editor, an existing save binding provides pending/result and rejects duplicate saves. Filename draft/format validation is local. A navigation request while saving must wait for that save to finish: success navigates to the latest requested destination; failure remains in the editor and clears the queued destination. Repeated navigation while saving replaces only the queued destination. The save must not restart or be cancelled. Document write permissions are enforced by the application use case at execution. Produce a responsibility map, event transitions and concrete checks, without framework API code.

1. [critical] Preserves Svelte, VSA slices and hexagonal use cases without introducing React/TanStack/Effect or centralizing business logic.
2. [critical] A named UI owner queues navigation during save; success uses the latest destination, failure stays and clears the queue; repeated navigation does not restart/cancel the save.
3. Keeps execution-time write permission in the use case and filename draft/format local, without duplicating permission rules for disabled UI.
4. Reuses existing save pending/result and duplicate-save protection, adding only navigation coordination.
5. Preserves the in-flight save identity across destination changes and handles its matching completion consistently in prose/table/checks.
6. Gives concrete checks for repeated navigation during save, success to the latest destination, and failure followed by a later save without stale navigation.

## Iteration 7

Changes: なし。A/B/C は固定課題、採点基準は不変。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r7-a.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [B](r7-b.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [C](r7-c.md) | ○ | 91.7% | 取得不能 | 取得不能 | 0 | Planning / Execution |
| [K](holdout-k.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親の評価 A/B/K = [1,1,1,1,1,1]、C = [1,1,0.5,1,1,1]。C の critical は全達成、固定3課題平均97.2%。自己評価はすべて全達成。Trace は説明形式で OK/stuck の明示タグを省略していたが、対象スキルの評価項目には後付けしない。

- Issue: C の取得待ちで録画→較正→録画を要求すると、同じ取得先への再要求を無視する行により desired=calibration が残る。冒頭の last request wins と一致しない。
- Cause: 停止待ちの反復列だけを確認し、取得待ちへ展開しなかった。実行の重複防止と最新要求の更新が混ざった。
- General Fix Rule: 各待機状態で要求採用と I/O 発行を分け、別要求から元へ戻る列も確認する。

実行者も事後確認で C-3 の「明示的で一貫した方針」違反と認め、desired 更新と I/O 重複防止を独立させる状態モデルを提案した。元成果物は改変していない。

Ledger: 「状態の限定を落とした要約が遷移表と衝突する」が iter 2、4、7 で再発。3回目なので同義の注意文を加えず、状態遷移節の再生指示と実行識別段落を3段階の手順へ統合・再構成する。対応先は C-3 explicit consistent policy と C-6 concrete checks。事前の実行者診断もこの判定文言と対応する。各待機状態の列挙→要求と実行の分離→各状態から反復列を再生する順にする。

A は取消終了後再送信、C は latest-wins と明示再試行を選択。K は既存 Svelte/VSA/hexagonal を維持し、SaveId を変えず目的地だけ更新、失敗時に待機先を消去した。K の未指定は binding の ID 契約。過適合の15ポイント低下はないが、C の再発で qualitative clear は0に戻す。K は使用済みなので次の収束用 holdout に再利用しない。

## Holdout L — confirmation before discarding a draft (frozen)

An existing React/Effect editor has a local form draft and format validation, plus a separate independent help panel. When the draft is dirty, navigation opens a discard-confirmation dialog. Further navigation requests while confirmation is open replace the pending destination; returning to the original destination must update that intention too. Confirm discards the draft and navigates once to the latest destination; dismiss stays and clears the destination. Navigation does not save or call a remote service. Produce a responsibility map, transition memo and concrete checks without framework APIs or code.

1. [critical] One editor UI owner arbitrates navigation/confirm/dismiss; Views do not independently navigate or discard the draft.
2. [critical] Pending destination follows the latest request including A→B→A; confirm navigates once to it; dismiss clears it and stays.
3. Draft/format state stays in the form; the owner consults its dirty signal without duplicating the form model or inventing business rules.
4. Does not invent remote operations, Fiber cancellation, a scheduler or mirrored async state for this synchronous UI decision.
5. Help panel remains independent and ordinary display state stays local.
6. Concrete checks cover confirm, dismiss followed by a new request, repeated requests returning to the original target, and absence of save/network calls.

## Iteration 8 — 構造変更後

Changes: 再生指示と実行識別を3段階の手順へ統合し、各待機状態を網羅する確認へ変更。Pattern applied: 状態の限定を落とした要約が遷移表と衝突する。SHA-256: `ddaa34b32e58dee29689287b3e724e6a8b6149c7a9ecd138663da259f82d7097`。reference、description、固定採点基準は変更なし。Iter 0 の scope 整合も維持。

### 評価した候補本文（後に不採用）

```markdown
反復要求や資源所有の変化を含むフローは、次の順で設計・確認する。

1. **状態を分ける**: 取得・終了待ちなどの各待機状態について、採用した利用者要求、継続中の実行とその識別子、資源所有者を区別して遷移表を作る。
2. **要求と実行を別々に裁定する**: 各状態の要求採用方針を適用してから、I/O を発行するかを決める。同じ実行先への要求でも、待機先を変更する必要があれば更新する。I/O の重複を防ぐことと要求を無視することを同一視しない。継続する実行の識別子を保持し、表示結果が不要でも解放や次操作に必要な終了通知を処理する。
3. **各待機状態から再生する**: 通常完了・失敗に加え、要求の重複と「要求先を変えて元に戻す」列を各待機状態から追う。`前状態 / イベント / 後状態 / 資源所有者 / 実行効果` を記録し、最終要求の扱いと I/O の発行回数が選んだ方針に合うか確認する。説明と確認項目の期待結果は、この記録から導く。
```

R8-A 初回は実行者が指定外の後続課題まで読んだと申告したため、[元報告](r8-a.md)を保管して正式採点・clear 判定から除外。同じ A と6項目を本文に直接渡した新規実行者で置換する。対象スキルの問題と評価 harness の抽出失敗を混同しない。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A replacement](r8-a-replacement.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | Formatting（Trace の分類） |
| [B](r8-b.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |
| [C](r8-c.md) | ○ | 91.7% | 取得不能 | 取得不能 | 0 | Planning / Execution |
| [L](holdout-l.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親の評価 A/B/L = [1,1,1,1,1,1]、C = [1,1,0.5,1,1,1]。critical failure なし。固定3課題平均97.2%（前回差0）。自己報告は全達成。A は Trace に指定4フェーズではなく対象スキルの工程名を使ったため、評価形式の不遵守として分けて記録する。

- Issue: C の Acquiring(recording, desired=recording)→Start(calibration)→Start(recording) は、同じ Start(target) を無視する行で desired=calibration が残る。C-3 partial。
- Cause: 各待機状態から要求先を戻すという指示を記載しても、その列を実際には再生していない。対象 target と最新 desired を同一視する分岐が残った。
- General Fix Rule: 宣言した要求採用方針を、実際の遷移表へのイベント列適用で照合する必要がある。自然言語での確認要求だけでは遵守を保証できない。

事後確認で実行者もこの反例を再生し C-3 partial と認めた。「各待機状態から再生していれば検出できた」と回答した。元成果物は維持する。

Ledger: 同じパターンが iter 2、4、7、8 で再発。構造変更でも防げなかったため、新しい注意文や例外をさらに積まない。候補は同じ accuracy・同じ欠陥のまま指示量を増やしたため不採用とし、対象本文を評価開始時の c77a50d 版へ戻した。より短い既存版を維持する判断であり、既存版の正しさを主張しない。

Discretionary fill-ins: A は取消後の即時再送信、C は latest-wins と取得失敗後の明示要求待ちを選択。L はフォーム dirty を参照する局所的な確認フローだけを設計し、保存や Effect runtime の処理を追加しなかった。L に新しい曖昧点・15ポイント以上の低下はないが、固定課題の再発を打ち消すものではない。

## 終了判断

**Resource cutoff。qualitative plateau は今回確認できず、quantitative convergence も未確認。** 前回の plateau は有限サンプルでの観測であり、今回の再発で継続性が否定された。

根拠: `empirical-prompt-tuning` の “Resource cutoff: stop when importance and improvement cost no longer balance”。適用元は `/home/ubuntu/.agents/skills/empirical-prompt-tuning/SKILL.md`。既知の同一パターンに対して構造変更でも改善せず、同義の指示追加を続ける費用に見合う根拠がないため終了する。

- 今回は有効8件（A/B/C × 2回 + holdout K/L）、抽出範囲違反で除外1件。診断 follow-up は別扱い。累計有効28件、除外込み29件。
- スキル本文・reference・ADR は最終的に変更なし。評価記録と既存報告への継続リンクのみを保存する。
- 残存問題: 複数の待機状態で、I/O 重複防止と最新要求の更新を混同する成果物が出る。自己採点はこの欠陥を見逃す。今回 critical は全達成だが、全体の正しさは保証しない。
- 次に検証するなら、指示文を増やす前に、遷移表を実行可能な形へ変換して状態別のイベント列を検査する評価契約が必要。これは今回の固定された設計メモ課題とは別実験として事前設計する。
- canonical tool_uses / duration_ms がないため定量収束は計算しない。設計メモのみの評価であり、実アプリの動作・発火率・因果効果を測ったものではない。
- 候補の形式検証と配布テスト18件は成功したが、C-3 の意味的な問題を検出するテストではない。最終差分の整形・相対リンク・git diff check を実施し、本文の復元後 hash が開始時と一致することも確認する。
