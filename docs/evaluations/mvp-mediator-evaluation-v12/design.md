# MVPスキルの検証報告改善設計

状態: 設計確定。Q1は「1: 手順を整理＋短い完成例」、Q2は「確定」とユーザーが回答。本文変更・実装・新規評価は未開始。

## 起点と範囲

[v11評価](../mvp-mediator-evaluation-v11/run-20260923-01/results.md)と[台帳](../mvp-mediator-evaluation-v11/run-20260923-01/failure-ledger.md)を根拠とする。純粋性の比較順序はE/Sで成立した。今回の設計テーマは、実行検証済みとする主張とassertionの対応。状態分類・削除試行は別テーマに残す。

確認済みの例: Eは現acquire失敗直後のeffects空を検証済みと報告したが、effects assertionは後続の旧成功通知直後。Sは旧応答直後のstate/effectsを開始直後と同一と報告したが、assertionはstate維持とeffects=[]であり、開始直後のeffectsは空ではない。

既存要件は維持する: 成果物説明必須、事前整理推奨、根拠表が検証報告の本体、正確な要約・重複は許容、実行検証済みの観測は1時点1行、未実装・未実行を区別する。全assertionの転記や新たな報告ツールは前提としない。

## 設計の分岐

1. Q1（合意済み）: 既存説明をassertionから根拠表を書く手順へ整理し短い完成例を添える。ユーザー回答「Q1:1」。完成例だけを追記する代案は採用しない。
2. Q2（合意済み）: 下記の変更内容・受入条件・評価条件で設計全体を確定。ユーザー回答「Q2:確定」。

## 用語と文書

ここでの根拠表は対象MVPスキルのケース別検証報告であり、PRのAC別Verification Matrixとは区別する。「観測時点」は操作直後の値を照合する時点、「比較相手」はassertionの期待値または比較対象を指す。本件の説明に使い、repo全体の新しい語彙としてCONTEXT.mdへ追加しない。局所的で可逆的な指示変更なので現時点でADRは不要。

## 次の段階

次のimplementは本書の変更内容と受入条件を使う。評価条件の変更を意図しない。v11成果物・入力・採点を保持し、本文修正後の実LLM評価は別途明示されたempirical-prompt-tuningで行う。

## Q2 — 具体案と受入条件（合意済み）

### 変更する手順

対象は `local-skills/mvp-mediator-architecture/SKILL.md` の「最終編集後」の手順3と根拠表の説明。既存の重複する説明を次の作成手順へ整理し、その直近に短いコード・対応表を置く。

1. 最終コードのassertionから、その値がどの操作で得られたか、何を照合したか、比較相手は何かを拾う。ケースの名前や実装の読み取りだけから検証主張を作らない。
2. その対応を既存の根拠表へ記録する。同じ観測時点のstate/effectsは一行にまとめてよいが、各値の期待値・比較相手は別々に書く。異なる操作で得た値を一つの観測へ移し替えない。全assertionの転記は要求しない。
3. 実際のケース出力と終了結果を対応付けて成功・失敗を記す。ケース全体が成功してもassertしていない値の確認実績へ広げない。根拠不足なら、必要な検査を追加・実行するか、要件上必須でない確認を未実装／未実行として明示する。要件上必須の検査を記述だけ弱めて省略しない。

表の列構成は維持し、「照合する値と期待値」欄の記入例で比較相手を具体化する。新しい必須列・検査ツール・報告生成器を追加しない。表外の正確な要約も許容し、同じ根拠へ対応付ける。コード読解による確認、実行検査、未確認の区別を保つ。

### コードと表の対応例

以下は報告手順の説明用抜粋。実際の名前・assertion形式は既存プロジェクトに合わせる。遷移の純粋性は既存の別手順で確認し、この抜粋で代替しない。

```js
const stale = transition(pending, oldCompletion);
assert.deepEqual(stale.state, pending);
assert.deepEqual(stale.effects, []);
const current = transition(stale.state, currentCompletion);
assert.deepEqual(observe(current.state), expectedCurrent);
```

| ケース | 観測時点 | 照合する値と期待値 | assertionの所在 | 実行結果 |
| --- | --- | --- | --- | --- |
| completionCheck | 旧通知直後 | stale.stateはpendingと同値、stale.effectsは空配列 | stale.stateとstale.effectsの2つのdeepEqual | 実際のケース結果への参照 |
| completionCheck | 現通知直後 | observe(current.state)はexpectedCurrentと同値 | observe(current.state)のdeepEqual | 実際のケース結果への参照。current.effectsの検査は未実装 |

この表は説明用で、未実行の例へ実績として「成功」を与えない。旧通知直後について「state/effectsとも開始直後と同じ」と一括要約すると、effectsの比較相手を変えてしまう。現通知直後については、stale.effectsの検査をcurrent.effectsの根拠にできない。effects空などの確認が今回の要件上必須なら、該当時点のassertionを追加して実行する。

### 維持する範囲

通常経路の独立性、v11の純粋性比較順序、表示導出、状態説明・分類、責務分担を維持する。事前整理推奨・成果物説明必須・正確な要約の許容・提案のみのBの扱いを維持する。新規の検査網羅要件を追加しない。状態分類と削除試行への修正を混ぜない。

### 受入条件

1. 本文と例が、観測時点・対象値・比較相手・assertion・実行結果を一貫して対応付ける。正しい対応として「state維持/effects空」、未確認として「現通知のeffectsにassertionなし」を区別できる。
2. 別時点のassertionやケース全体の成功を未検査値の証拠にせず、必要検査の追加と任意の未確認記録を区別する。正確な要約・一時点内での複数値の同居・全assertion転記不要を維持する。
3. 具体例と表の対応は最終本文を対象にレビューする。コード例は最小の前提を補ってNode標準assertで実行確認できる形とし、既存の検査手段を優先する。文章中のキーワード一致だけで報告の正確さを検証したとしない。専用の報告検査フレームワークは作らない。
4. v12契約・公開CLIの版登録とhash・対応fixtureを更新し、新本文の配布、v10 E/checkerの維持、旧run参照と書込み再開拒否を確認する。スキル形式検査・型確認・変更に適した既存テスト・Standards/Specレビューを行う。
5. 旧本文snapshot・契約・checker・run・採点を保持する。静的検査や例の成功を実LLMの報告改善の証拠にしない。

### 次回評価条件

本文だけをこのテーマで変更し、E課題と親checkerはv10、B/S/L課題・共通配布テンプレート・6基準/critical・C1〜C4の枠組み・実行者model/effort・隔離・直列親監査・再発停止・実行上限・L投入条件・canonical metadata規則は維持する。観測時点の形式遵守と報告内容の正確さを分けて記録し、clear数だけで改善を主張しない。旧runを再採点しない。

設計全体は合意済み。次のimplementで本文変更・版管理・受入検証を行う。実LLM再評価は実装完了後の明示的なempirical-prompt-tuning依頼で行う。
