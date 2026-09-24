# MVP + Mediator スキルの配布を終了する

2026-09-24。`mvp-mediator-architecture` の配布を終了する。mainの旧版はReactコンポーネント全般へ単一Root・イベント転送・connector等を一律に要求していた。prototypeで適用範囲を狭めたv17も検討したが、得られた利益に対して指示・検査・文書の負担が大きく、追加調整を続けず撤去する。短縮版や明示呼出し専用版は今回は作らない。

## 判断の根拠と限界

ClaudeとCodexで元資料と反証を確認した。v17あり／なしを各課題2回ずつ比較したA/Bでは、排他デバイスの固定52検査は両群すべて成功し、検索UIと既存フォームの採点合計も各群23.5/24だった。記録上の平均tokensは106530対82193、時間は458対285秒で、スキル群の負担が増えていた。既存機構の確認や限界の説明にはスキル群の質的利益もあった。

これはmainの旧版を直接比較した実験ではない。各群2回・方針を含む課題文・抽象モデル中心・同系列の採点者・advisorの助言内容を分離していないという限界がある。「スキルなしがあらゆる実装で優れる」とは結論せず、現行スキルへの追加投資を止める根拠とする。

## 残す原則

- 業務判断はModel／ユースケースが所有し、UI遷移と区別する。表示のために業務規則を再実装しない。
- 競合する操作では判断の所有者を明確にし、取消・再試行前の古い応答で現在の操作を上書きさせない。
- 既存の設計・実行機構を優先する。Effect等が採用済みなら、その中断・寿命管理を重複実装しない。
- 表示だけの局所状態は局所に置ける。単純なUIにも専用Mediatorや転送層を一律に追加しない。

これらは設計判断の記録であり、新しい自動適用スキルではない。将来、実プロジェクトで具体的な不足が見つかった場合に、必要な範囲を別案として評価する。

## 証拠の保存と実装範囲

一次資料は`prototype/evaluation-input-gate`の固定commit `dd05483f7418482f2b51d28c8dac2d2bb8baa115`に保存してある。

- `docs/evaluations/mvp-mediator-ab-20260924/decision.md`: 共同判断、反証、報告の訂正と限界。
- 同ディレクトリの`original/`と`source-manifest.json`: 原資料72ファイルとSHA-256一覧。
- 同ディレクトリの`implementation.md`: prototype側の撤去と記録保全の検証。
- `docs/adr/0063-scope-mvp-mediator-and-effect-responsibilities.md`: 責務分離と既存設計への適用範囲を検討した履歴。mainのADR-0063とは別文書。

例えば`git show dd05483f7418482f2b51d28c8dac2d2bb8baa115:docs/evaluations/mvp-mediator-ab-20260924/decision.md`で読める。現時点ではローカル保存であり、PR公開時にはprototype branchも別途公開して参照可能にする。prototype branchは保持し、mainへ全体をmergeしない。

main向け変更は配布元2ファイルの撤去、既存`localSkills.retired`への登録、配備回帰テストと本ADRに限定する。専用評価CLIや実験資料の複製は導入しない。旧配布版はmainの基点commit `3686cf61fd1a0370ba2f63f470c548888d630bee`にも残る。受入・merge後、live sourceの既存chezmoi経路で配備先へ反映する。未mergeのtask worktreeからhomeへapplyしない。
