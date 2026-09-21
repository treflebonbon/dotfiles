# Effect優先・必要なパターンだけを適用する構成の評価

## 変更と判定文言

ユーザーは推奨構成への変更と実証評価を依頼し、「合わない点は無理に取り入れる必要はない」と明示した。baselineは`35c0a4a`。旧実験の検証例追加を再採用するのではなく、適用手順を既存保証の確認→操作間の制約→必要な判断の所有者へ整理した。

適用前に新規agentの構造reviewを実施した。実行評価ではなく、clearには含めない。対応は、責務分離がA1–3/A7・F1–2/F4/F6・B1–2/B5、Mediatorの役割化がA3/F2/B2、binding再利用がA2/F1/F4、CoRとDAGの範囲がA4、Passive Viewの緩和がA5/F3/F6/B3、Effectによる合成がA6。発送競合・古い応答・解放待ちの安全境界は維持した。

既知ledgerは[前回](../mvp-mediator-executable/worked-example.md)から引き継ぐ。状態の用途の誤分類は、追加注意書きの列挙ではなく、実装の判断で必要な情報か、既存機構から供給する情報か、検証の補助かを状態設計の節で判断する手順へ統合した。設計メモだけの依頼には確認案、実装・抽象モデルには実行検査を求める。表示だけの変更にモデルを作らせない。

Iter 0: descriptionは新規設計・MVP変更・競合フローを対象とし、本文の必要時適用と一致。React/Atomを必須化せず、既存構成維持の分岐を保持。Effectの具体的APIは導入版の確認へ委ねる。

候補本文SHA256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`。条件付きreference SHA256: `02190f7b944084b388f20c978ffe1bf5659da7249df149a8954b2f4499b02d2e`。

[凍結プロトコル](protocol.md)のA/F/Bを独立executorで実行する。旧E/B/Sの採点や失敗記録を変更しない。対象はagent向け設計指示であり、設計メモの実行評価と実アプリの検証を区別する。tool_uses/duration_msはこのruntimeが提供しない場合、取得不能と記録する。

## Iteration 1

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r1-a.md) | 全7項目○ | ○、全項目full | 100% | 取得不能 | 0 | Planning: 依存図の意味 |
| [F](r1-f.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [B](r1-b.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |

全成果物と入力hash/reference読了を親が確認。Fは既存bindingの確認済み保証を根拠に、新たなclass/store/操作IDを追加しない。BはQueryと局所表示を維持。Aは業務検証、Effect実行、追加制約だけの親裁定、緩和/厳密Passive View、再試行循環を区別した。実装版が未指定なことによるbinding保証の確認事項は課題の補完であり、指示の不明点とは別に扱う。

Aの「View→Mediator→usecase→Service→Adapter」を依存と呼び、後段で同じ方向をimportのDAGに結び付けた表現は曖昧だった。成果物を修正させず意味だけ確認したところ、主に実行時の呼出経路であり、ServiceはPort契約、ユースケースは具体AdapterをimportせずRootで供給する意図と回答した。固定基準を新たな減点項目で拡張せずfullを維持するが、独立した読者が静的依存と誤認できるためqualitative clearは0とする。

- Issue: 実行時の呼出順を静的import依存と同じ矢印で説明した。
- Cause: referenceはService/Layerの分担を示すが、PortとAdapterの静的な依存方向を示していなかった。
- General Fix Rule: 依存の説明では、契約に向かう静的依存と実装へ到達する実行時の経路を区別する。
- Ledger: このターゲットの依存方向の混同を追加。状態分類の旧失敗と同一視しない。

適用前の構造reviewが、referenceへの依存方向の追記をA4「DAGを依存関係に適用」と課題の「依存方向」に対応付けた。変更はその一テーマだけ。本文と基準は変更せず、referenceへ「ユースケース→Port、Adapter→Port、具体Adapterは組立箇所で選択」を追記して再評価する。

## Iteration 2

本文hashは維持、referenceは`110b25b8ba320ac61ceb38c19142f5028aabfcc28a27cfd6b7a51b0eef288cca`。以後この候補を固定する。

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r2-a.md) | 全7項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [F](r2-f.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [B](r2-b.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |

親は全メモを読み照合した。Aはユースケース→Port、Adapter→Port、RootでのLayer選択を明示し、時間上の再試行循環と静的依存を区別した。追加裁定は古い結果の採用と共有資源の解放待ちに限定し、bindingの既存保証がある場合は追加状態も省く。Fは課題で確認済みの保証を使い、新たな操作ID・store・CoRなどを設けない。Bは既存Queryと表示変更だけを維持した。

自己申告の不足情報は、導入版bindingの保証、資源の完了通知、既存component名など、課題で未指定の実装情報。新たな指示不明点は0。任意補完も実装時の確認へ限定されている。qualitative clear 1。後続の独立実行を開始した順序で組を固定し、結果を見て都合よく並べ替えない。

## Iteration 3

候補はIteration 2と同一。親は完成後の全メモを独立に照合した。

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r3-a.md) | 全7項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [F](r3-f.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [B](r3-b.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |

Aは静的依存をPortへ向け、イベント経路との区別を明記。業務の実行時検証、bindingからの導出、必要な資源解放待ち、厳密/緩和Passive Viewを維持した。Fは確認済みbindingの保証に依拠し、送信状態や操作IDを複製しない。Bは局所変更に限定した。Bの具体的なファイル名・API未指定は課題の実装情報不足であり、指示の不明点ではない。全入力hashとreference読了を確認。新たな指示不明点・適用漏れ0、qualitative clear 2。

## Iteration 4

候補は変更なし。親は完成後の全成果物と入力hash/referenceを照合した。

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [A](r4-a.md) | 全7項目○ | ○、全項目full | 100% | 取得不能 | 1 | Formatting: 検査コマンド呼出し訂正 |
| [F](r4-f.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |
| [B](r4-b.md) | 全6項目○ | ○、全項目full | 100% | 取得不能 | 0 | — |

Aは実行時業務検証、Effect/Atomからの導出、追加制約だけの共通親裁定、静的依存と時間上の循環、Passive Viewの緩和を区別した。F/Bは既存所有者と局所表示を保ち、パターンの形式的追加を求めない。具体的な検査は未実行の提案として記録している。Aの再試行は整形コマンドの訂正であり、設計指示の不明点ではない。新たな指示不明点・適用漏れ0、qualitative clear 3。

Iteration 2–4の9独立実行は全基準full。未使用の実行課題Oと既存E回帰を、新規executorへ初めて/改めてそれぞれdispatchした。設計メモAと注文領域を共有するOは、未知領域全般への一般化ではなく、未使用の実行課題への適用確認である。

## 再現と検証の境界

実行者はすべて履歴forkなしの新規gpt-5.6-terra/high。各自には対象skill・適用referenceと担当課題だけを渡し、他の成果物と親checkerを読ませていない。固定プロトコルのSHA256は`77527792cb13b3e872e1fbf4a615bf5ac6b1ad83dbaaeb1c5ab04748cfff8672`。既存52ケースcheckerは`72adc7af373705e1324d26c48cec7eec123e5bbbc493f77bf1f34d259eb05ae1`のままである。

スキル形式のquick_validate.pyは成功、`bats tests/local-skills.bats`は18/18成功。後者は配布用fixtureの検証であり、task worktreeからlive環境へ配備していない。設計メモは実アプリの検査結果ではなく、実行モデルも実Effect/React/Atom統合の検証を代替しない。

正式なtool_uses/duration_msは取得不能で、ログから推定しない。runtime/skill-harness.mdのローカル上書きに従い、3連続clearをstrict convergenceには数えない。速度・ステップ数の改善を主張しない。

## 未使用Holdout O

[実行モデル](holdout-o.mjs)と[実行者メモ](holdout-o.md)を完成後に親が全文照合し、`node docs/evaluations/mvp-mediator-recommended/holdout-o.mjs`を再実行した。4 assertion groups passed。実行時発送拒否、pending中の重複拒否、同一注文の別試行と旧成功・旧失敗の除外が成立した。モデルは既存bindingを模擬し、追加の裁定状態・独自runtimeを要求しない。

| 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- |
| 全6項目○ | ○、O1–4/O6 full、O5 partial | 91.7% | 取得不能 | 1 | Formatting: メモと実装の不一致 |

O5をpartialとしたのは、メモの「tooltipはモデル化していない」がcreateOrderView/testLocalViewStateと矛盾するため。検査表と実装では局所Viewモデルを検証している。編集させず意味だけ確認したところ、実行者は誤記と認め、「業務/binding状態に含めていない」意図だったと回答した。固定成果物を修正して点数を救済しない。critical O1/O2はfullでbinary○。直近の設計評価100%からの低下は8.3ポイントで、固定された15ポイント以上の過適合判定には該当しない。ただし設計メモと実行モデルは課題形式が異なり、この数値を一般化性能の統計的保証には使わない。

- Issue: モデル化した局所表示を「モデル化していない」と説明した。
- Cause: 実装全体と業務/bindingの範囲をメモで区別せず、実装後の説明照合を取りこぼした。
- General Fix Rule: 「ない／未実装」の記述も、実際の成果物と対象範囲を照合する。
- Ledger: 既知の説明と実行内容の不一致を再観測。実行時業務規則・非同期安全性の失敗ではない。単一のメモ誤記を理由に新しい必須テンプレートをスキルへ追加しない。

親のdispatchにも欠陥があった。U/P/E/Fを展開せず略記したため、実行者は別の責務トレースとして解釈したと回答した。これはターゲットskillの不明点とは分離し、初回には4フェーズの自己報告を取得できなかったと記録する。後から意味を明示して再実行なしで確認すると、実行者はUnderstanding/Planning/Execution/Formattingを当時すべてOKと認識しており、誤記とトレース誤読は後から判明したと回答した。この補足を初回トレースと混ぜない。上表のWeak phaseは親が不一致から分類したものである。E側にも完了前に4フェーズの意味を明示した。

## E回帰

[実行モデル](regression-e.mjs)と[実行者メモ](regression-e.md)を親が全文確認した。実行者の6検査グループは親の再実行でも成功し、固定checkerは52/52成功（failures: []）。追加で、初期状態→recording取得→正常完了の割込みなし経路と、取得失敗→再要求時の新ID、および旧IDの成功・失敗が現試行を変えないことを親のNode assertionで検査して成功した。成果物やcheckerは変更していない。

| 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- |
| 全6項目○ | ○、E1–5 full、E6 partial | 91.7% | 取得不能 | 1 | Planning / Formatting: 通常経路と状態分類の記録 |

E6は、memoで正常成功も確認済みとする一方、最初の検査が取得中の要求反転を含み、skillが求める「割込みのない通常経路を最初に独立検査」と一致しないためpartialとする。親が追加した正常検査で実装の動作は確認できても、executorの適用点数を救済しない。critical E1/E2はfull。実行モデルには継続ID、最新意図、失敗したstageが分かれており、52ケースで操作方針に回帰は検出されなかった。

また、memoは親とEffectの責務を説明するが、内部状態の分類と本実装での取得元を明示していない。desired/failedStage/ownerなど判断に必要な情報を「検証専用」と誤分類してはいないものの、スキルの状態説明手順の適用漏れとして残す。追加の採点軸を後付けせず、質的な制限として記録する。

- Issue: 正常経路と反復要求を分離せず、状態情報の本実装との対応も記録しなかった。
- Cause: 実行者が固定6基準を満たす検査へまとめ、対象skillの成果物確認手順をすべて出力へ伝播しなかった。
- General Fix Rule: 基準チェックと、実行した経路・保持する状態の説明を独立に照合する。
- Ledger: 既知の「正常経路が反復要求に埋もれる」「状態説明の適用漏れ」を再観測。必要な指示は今回候補にも存在しており、末尾への注意書き追加では解決を保証できない。

## 採用判断

Effect優先で必要な責務だけを採用する設計変更を採用する。最終候補の設計課題A/F/Bは3連続の組・9独立実行で全基準full（新たな指示不明点0）。O/Eの重要基準も満たし、実行上の回帰検査は成功した。実行成果物の説明・検証手順には上記の取りこぼしが残るため、すべての適用で完全な検証記録を生成するスキルになったとは判断しない。

判定は **qualitative plateau; quantitative convergence unverified**。これは設計課題の安定と実行回帰成功に基づく限定的な採用である。未使用Oの低下は固定閾値未満だが、O/Eの記録品質を含む全課題での無欠陥・strict convergenceを主張しない。改善範囲を再び検証テンプレート全般へ拡張せず、今回依頼された必要時適用の変更として完了する。

完成後のOメモにあったMarkdown行末空白は、最終の差分検査に合わせて空行へ置換した。これは整形だけで、誤記・モデル・固定基準・採点は変更していない。
