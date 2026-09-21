# 必要時適用スキルの実行記録再評価

ユーザーの再起動により前回の未解決点を継続評価する。対象baselineはe7b3d5a、本文SHA256 `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`、reference `110b25b8ba320ac61ceb38c19142f5028aabfcc28a27cfd6b7a51b0eef288cca`。作業treeは同じvalidated checkout。未配備。

Iter 0: descriptionは必要時の責務設計と既存構成維持を示し、本文の適用手順・分担と一致する。Effect/Atomは採用済みの場合で、他スタックへ強制しない。実行モデルの検査規則はその成果物を作る場合に限る。

[固定プロトコル](protocol.md) SHA256 `ce4fe0c46a15f96cfd842c0c50c9310fb77f8b5118130c3fed42fd02b3a17664`。E/O/Fの既存文言・criticalを維持。新規holdout Lを初回dispatch前に固定した。前回Oは既使用なのでholdoutとして再利用しない。実行回数や点数を前回へ合算せず、本実験の組順を維持する。

## 引き継いだfailure ledger

- **通常経路が反復要求に埋もれる**: 最初の検査が切替・失敗を含むまま正常成功も検査済みと記す。General Fix Rule: 単独の正常ケースと反復ケースの実行記録を区別する。Seen in: executable/evidence、worked-example、recommended/E。
- **実装範囲と記録の不一致**: tooltipを実装・検査しても未モデル化と記す。General Fix Rule: 未実装という否定も成果物と範囲を照合する。Seen in: recommended/O、既存検証記録の不一致群。
- **状態の用途・本実装での取得元が抜ける**: 判断に必要な情報を検証専用とする、または説明を省く。General Fix Rule: 情報が何を決めるか、何が供給するかを根拠に分類する。Seen in: worked-example/S/E、recommended/E。

既知の再発は3回以上あり構造上の問題として扱う。強調、冒頭への移動、列挙、一般的検証例だけを再追加しない。現行構造での新規実行を先に観測する。親の旧dispatchのTrace略記も修正し、Understanding/Planning/Execution/Formattingを明示した。これは対象skillの変更とは分離する。

## Iteration 1 — 現行版の再実行

| Scenario | 自己申告 | 親判定 | Accuracy | tool_uses / duration_ms | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](r1-e.md) | 全6○ | ○、全full | 100% | 取得不能 | 3 | Planning: 状態説明の省略 |
| [O](followup/r1-o.md) | 全6○ | ○、全full | 100% | 取得不能 | 0 | Formatting: 別lint実行 |
| [F](r1-f.md) | 全6○ | ○、全full | 100% | 取得不能 | 0 | — |

親はすべての完成版を読んだ。Eは52/52、Oは4ケース成功。Eは最初に割込みなしでrecordingのactiveまで進み、その後の切替命令を確認するため、前回のような通常成功の過大主張はない。しかし用途・所有者・本実装の取得元の状態説明がなく、qualitative clearは0。Oは通常、発送競合、反復、tooltipを別に検査してメモと対応した。Fは既存bindingだけで表示を導出した。

Oは出力先に余分なfollowup/を作り、PATH上のNix oxlint1.65.0を使ったと完成後に確認できた。親のworktree-local oxlint1.82.0では実行でき、スタイル違反を報告した。これは対象skillの責務判断と別のcaller/tooling問題で、成功したlintとは記録しない。Eには完了前に正しい実行パスを明示した。Eのlint抑制も原成果物のまま記録する。

Issue: 状態情報の説明が実装から抜ける。Cause: 実装後の独立メモへ説明を集める方式では、基準の一般的責務説明だけで終われる。General Fix Rule: 実際の宣言と検査結果を説明の原本にし、別メモで再構成しない。既知ledgerの再発であり新パターン扱いしない。

## 構造変更の対応

別agentの構造review（実行・clearには含めない）が、一つの変更テーマ「証拠を実装箇所に置く」を提案した。状態宣言の直近に用途・所有者・本実装の取得元を記し、メモはその説明と実行済み名前付き検査を参照する。E6のmodel/memo/check一致、O3のbinding模擬と裁定状態の分類、O5の通常/拒否/反復の実測とメモ一致に対応する。状態分類を要求するO3そのものは固定採点で評価し、Eに新たな点数項目を追加しない。Fはモデルを作らないので追加作業を要求しない。

過去の別referenceへの実行例追加と異なり、新しい参照やテンプレートを追加せず、既存の状態説明と検証記録の生成元を変更する。アーキテクチャ・課題・固定基準・checkerは変更しない。候補の有効性は後続の独立実行で確認する。

候補本文SHA256は`6253f70613454fca7d5dd2c98a3bdab7c3053956651f62e89bf7ab4701cd4211`。referenceは変更なし。quick_validateとtracked diff checkは成功。Iteration 2からlint/formatのworktree内パスもdispatchに明記し、lint抑制を使わないよう指定した。このcaller側の修正もあるため、実行時間や検査の手間の変化をskill本文だけの因果効果とは解釈しない。固定の機能/責務基準は変更していない。

O1の未整形コードは[原本](followup/r1-o.original.txt)へそのまま保存した。保守する.mjsには採点後に関数式・key順・波括弧・未使用変数・採番表記だけのstyle修正を施した。原本と整形版は同じ4ケースを通過する。原メモと上表は原本への評価のままで、lint失敗を遡って成功扱いしない。

## Iteration 2 — 宣言と証拠の近接化

| Scenario | 自己申告 | 親判定 | Accuracy | tool_uses / duration_ms | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](r2-e.md) | 全6○ | ○、全full | 100% | 取得不能 | 0 | Planning: 状態説明の適用漏れ |
| [O](r2-o.md) | 全6○ | ○、全full | 100% | 取得不能 | 0 | — |
| [F](r2-f.md) | 全6○ | ○、全full | 100% | 取得不能 | 1 | caller: Git呼出規則 |

Eは52/52、独立normalPathが先頭で成功する。ただし状態宣言に説明は一切なく、メモにも本実装との対応がないためqualitative clearは0。Oは通常/競合/重複/旧成功/旧失敗/tooltipを別ケースで実行し、binding状態の宣言にも模擬の説明を置く。Fは表示導出だけ。Eの取得失敗後desiredの補完、Fの表示優先順位未指定は課題の裁量で、対象指示の不明点と分ける。

完成後にEの実行者へ変更なしで診断を求めると、状態説明の段落は認識したが「private state名は自己説明的なので短い責務メモで足りる」と考え、fixed criteriaに明示されない説明要件を落としたと回答した。検査名も出力を短くするため集約した。読めなかったのではなく、採点基準を指示の代替として扱ったことが確認できた。

親のdispatchは「Read target」「Execute that scenario and frozen criteria」であり、メタskillの契約「Follow the target prompt to execute the scenario」を明示していなかった。既存基準は採点軸であり、対象skillの規則を排除する契約ではない。このcaller側の不足を本文への追記で補うのは切り分けにならない。候補は[原文](declaration-evidence-candidate.txt)に保存し、採用済みbaselineへ戻す。候補の有効性を確認したとは扱わない。

次組から、対象本文に従って実行すること、チェックリストが対象の他の指示を置き換えないことを明示する。課題・固定基準・重要判定・採点方式は変更せず、caller修正後の結果を本文改善の効果とは呼ばない。正常経路/状態対応など個別の過去失敗をdispatchに追記しない。

## Iteration 3 — 実行契約の明示による切り分け

採用済み本文に戻した状態で、E/Oを新規executorへdispatchした。Fの新規起動は`agent thread limit reached`で拒否された。先行agentの完了後に一度再試行しても同じ拒否となり、一時的な完了通知待ちでは解消しなかった。既存agentを使い回さず、実行できた課題を記録する。起動失敗を課題の不合格や成功として採点しない。この時点で3課題の組は成立していない。

O3は親の再実行で5ケース成功。通常、発送競合、重複、旧成功、旧失敗が独立し、pending/resultはbinding模擬、currentAttemptは追加裁定、検査名配列は検証補助とメモに対応する。実行者の最終報告は全6○、4フェーズOK、Retries1（lint対応）。親も全full・binary○・100%と判定した。分類は採用済み本文でも可能だが、一例だけでcaller変更の因果効果を断定しない。

E3も固定checker52/52、自己検査成功。割込みなしの取得成功が最初に独立した初期状態から検査され、メモと実行内容は一致するため固定6基準は全full・binary○・100%。実行者は全6○、4フェーズOK、Retries1と報告した。しかし状態の用途と本実装の取得元の説明は今回もない。実行契約の明示だけで説明漏れが解決するという仮説も支持されなかった。F未実行に加え、この適用漏れがあるため第3組はclearではない。

| Scenario | 自己申告 | 親判定 | Accuracy | tool_uses / duration_ms | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](r3-e.md) | 全6○ | ○、全full | 100% | 取得不能 | 1 | Planning: 状態説明の省略 |
| [O](r3-o.md) | 全6○ | ○、全full | 100% | 取得不能 | 1 | — |
| F | 起動不能 | 未評価 | — | — | — | 環境上限 |

## 採用判断と停止理由

**今回の追加候補は不採用。採用済み本文050c8704…を維持する。** 状態説明と検査証拠を宣言箇所へ寄せる候補でもEの説明漏れが残り、caller契約を明示したbaselineでも再発した。読み取り・言い換え・記録場所の変更だけで改善を保証する証拠は得られなかった。必要時適用、Effect優先、既存binding共用、業務/裁定/実行の責務分担を変える根拠にはしない。

停止区分は **resource cutoff（新規executorの環境上限）**。`agent thread limit reached`が繰り返され、メタskillが要求するfresh executorを追加できない。既存agent再利用や親の自己再読を独立評価として代用しない。3連続clearは0、Lは未使用。qualitative plateauもstrict convergenceも宣言しない。canonical tool_uses/duration_msも取得不能のまま推定しない。

有効な独立実行は8件（E3/O3/F2）で、固定基準は全件full・binary○。しかしEは3件とも状態説明の適用漏れがあり、固定スコア100%を指示遵守100%とは扱わない。構造review1件と診断follow-upは独立実行件数へ加算しない。

## 検証と再開情報

- Eの3モデルは固定checker各52/52、自己検査も成功。親の追加assertionでは、3モデルとも取得失敗後の新IDと旧成功・旧失敗の除外が成功した。
- Oの3モデルはそれぞれ4/6/5ケース成功。O1の原本と保存用style修正版も同じ4ケースを通過した。
- 候補のquick_validateは成功。採用済み本文とreferenceは実験開始時のhashに戻っており、配布ファイルの変更は残していない。
- 実React/Effect/Atom統合やbrowser検証は未実行。実行モデルの検査だけでこれらを保証しない。
- 完成後のMarkdown行末空白と整形のみ正規化した。メモの意味・誤記・自己申告・採点は救済していない。

続ける場合は、新規executorを起動できる新しいセッションで同じworktreeを検証し、まずこの記録と引継ぎledgerを読む。採用済み本文、固定E/O/Fと未使用L、52ケースcheckerを維持し、clearは0から始める。既存の状態説明指示が省略される原因を新しい仮説で切り分ける必要があり、同義の注意書きや同じ候補を再追加する根拠はない。

保存時の検証: 全6モデルの自己検査を親が再実行して成功。保存用ファイルはworktree-local oxlintとoxfmt --checkを通過した（E1原成果物のstyle抑制は記録どおり保持）。protocolと既存checkerのhashは凍結値と一致する。
