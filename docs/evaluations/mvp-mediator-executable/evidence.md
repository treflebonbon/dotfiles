# 実行ケースから検証記録を作る構造の評価

後続の[検査と記録の実行例の評価](worked-example.md)は別実験として記録した。この手順化候補の不採用判断と成果物は変更していない。

Baseline: `f37f9637e27c53df4c4342f1627ffc6c111d5ac5`。旧本文 hash `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`。[追加確認](confirmation.md) でE6の報告不一致が再発したため、完了成果物の列挙から、独立ケース定義→実行→その記録を用いた報告という手順へ変更する候補を試す。Iter 0: descriptionの適用範囲は本文と一致。

既知ledger「通常経路の独立assert欠落」「動作・説明・確認の不一致」を引き継ぐ。文言の追加と冒頭への移動だけでは、反復ケースを通常ケースと同一視する失敗を防げなかった。変更はこの一テーマに限定し、ADR-0063の責務・Effect優先・既存binding共用は変えない。

## 固定プロトコル

[既存E/B/S](protocol.md) の各6項目、critical、採点（full1 / partial0.5 / absent0）を変更しない。独立checkerも変更しない。今回は新規executorごとにE/B/Sの一組を実行させ、3組を独立反復する。全員 gpt-5.6-terra/high、履歴なし。対象本文・conditional reference・各scenarioだけを渡し、過去成果物・checker・改善仮説は見せない。一組内に複数課題を渡す点は以前の一課題一executorと異なるため、前回との厳密な因果比較や速度比較には使わない。

親は自己検査とEの52ケースを実行し、memoを実際のケースと照合する。3組とも新しい対象指示の曖昧点・既知不一致がなく、全項目達成なら未使用Oを評価する。欠落があればclearをリセットし、既知ledgerから原因を調べる。修正後はfresh executorを使う。tool_uses / duration_msがなければ推計せず、strict convergenceに含めず qualitative plateau と定量未確認を区別する。

## Holdout O — 実行時の業務判定（dispatch前固定）

既存React/Effect注文画面でキャンセル操作を扱う。画面が購読する注文のcached statusと、ユースケースが実行時に取得する最新statusは別で、画面がcancelableを表示した後でも発送され得る。発送済み注文はユースケースが実行時に拒否し、typed business errorを返す。Mediatorはその判定を再実装せず、pending中の二重送信を拒否し、完了後の新しい試行を区別する。古い試行の成功・失敗は現在の試行を完了させない。通常のpending/resultは既存bindingから共用し、独立したtooltipは局所状態。純粋Node抽象モデル（API自由）と実行したassertion・責務メモを作る。実Effect runtimeの実装は不要。

1. [critical] cached statusが未発送でも実行時statusが発送済みならユースケースが拒否するassertionがあり、Mediator/Viewに業務規則を重複しない。
2. [critical] pending中の重複送信を抑止し、同じ注文の別試行を識別して旧成功・旧失敗が現試行を完了させないことをassertionで示す。
3. pending/resultを既存bindingで共用し、ユースケース・bindingの模擬と追加裁定・検証専用状態を分類する。
4. Effectの実行境界とtyped business errorの役割を示し、defect/中断を業務拒否と混同せず、自作runtimeや強制的な新規依存を追加しない。
5. 通常のキャンセル成功と発送競合の拒否、反復要求を別に検査し、memoと実行したケース・結果を一致させ、未実行の実アプリ統合を明記する。
6. tooltipと表示整形は局所、同じ操作判断の所有者は一つとし、注文一覧の取得や他フローを一つのglobal FSMへ集約しない。

## 適用前の判定文言への対応

構造reviewの新規agentがE6/S6への対応を言語化した。従来は成果物を列挙し、最後に一致を確認する構造だったため、部分assertionを通常経路と誤認したまま別建てのmemoを作れた。候補では状態対応→名前付き独立ケース→実行記録から報告の3手順へ置換する。

- E6「concrete checks agree」「report its actual result」: 新しい初期状態からの名前付きケース、実際のイベント列と検査出力を報告元にする。
- S6「Memo and model agree」「checks are actually run and their limitations stated」: 同じケース記録からメモを作り、検査名を対応させ、未実行項目を区別する。
- B: 適用条件は元の「制約＋反復要求または資源所有」のまま。表示専用のためにモデルを作る指示は追加しない。

referenceや他の責務規則は維持する。構造reviewは実行評価にもclearにも数えない。今回の仮説は強調の追加ではなく、検証記録と報告の入力を同一にすることで取り違えを減らすこと。成功を先に仮定しない。

候補hash: `5925bc6c0c7aede1c9b10717fc10d378728c4d51e7bb835992b4b3f4246f38da`。固定checker hash: `72adc7af373705e1324d26c48cec7eec123e5bbbc493f77bf1f34d259eb05ae1`、reference hash: `a446ebe95eb01feddbc8fd30041db60d9b66dcb07e629fcd3e5bbeeaf97a27d8`。3組は候補変更なしで並行dispatch。完了順で都合のよい並べ替えをせずr1/r2/r3順に集計する。定量の逐次round収束とは区別する。

## 追加の切り分け（dispatch前記録）

複数課題を束ねた出力で、2つのEは52/52だがr3-Eは解放phaseの契約違反で35/52だった。検索にも通常状態と裁定状態の分類が曖昧な出力が見える。最終memoの採点は完成後に行う。候補の効果と一executorへの課題集約の影響を混同しないため、本文・判定基準をそのままに、以前と同じ一課題一executorでSとEを追加実行する。この切り分けは欠落した組を除外したり、後から成功だけで3clearを数えたりするためには使わない。

## 集約した3組の親評価

自己報告は全項目○だったが、親評価では以下の差がある。成功○はcritical全fullのみで判定する。steps/durationは全件取得不能。

| 組 / scenario | 成功 | 達成率 | 親の6項目スコア | retries（自己申告） | 弱いphase（親評価） |
| --- | --- | --- | --- | --- | --- |
| r1 E | ○ | 100% | 1,1,1,1,1,1 | 組全体0 | — |
| r1 B | ○ | 100% | 1,1,1,1,1,1 | 組全体0 | — |
| r1 S | ○ | 91.7% | 1,1,0.5,1,1,1 | 組全体0 | Planning / Formatting |
| r2 E | ○ | 100% | 1,1,1,1,1,1 | 1 | Execution / Formatting（本文手順の欠落） |
| r2 B | ○ | 100% | 1,1,1,1,1,1 | 0 | — |
| r2 S | ○ | 91.7% | 1,1,0.5,1,1,1 | 2 | Planning / Formatting |
| r3 E | × | 66.7% | 0.5,1,0.5,0.5,1,0.5 | 組全体2相当（明示数なし） | Execution / Formatting |
| r3 B | ○ | 100% | 1,1,1,1,1,1 | 同上 | — |
| r3 S | ○ | 91.7% | 1,1,0.5,1,1,1 | 同上 | Planning / Formatting |

- [r1](evidence-r1-report.md): Eは52/52、通常経路は最初に独立実行。ただし名前付きケース記録から報告を組み立てる新手順の完全実行は確認できない。Sは通常pending/error/resultを一体stateで更新し、説明の「追加状態はlatestIdのみ」に対して既存bindingの模擬との明示的対応がない。S3はpartial。固定項目とは別に、状態対応表や各ケース記録の欠落も候補の遵守結果として残す。
- [r2](evidence-r2-report.md): Eは52/52。通常・失敗・反復の独立ケースは作らず一続きだが、メモは実際の列を報告し、前回のような通常経路の虚偽記載はないためE6を事後に厳格化しない。候補手順の欠落はclearに数えない。Sはstateのpending/results/errorを更新するモデルをidentity-onlyと記述。観測用だという説明はあるが、既存bindingとの対応がないためS3はpartial。
- [r3](evidence-r3-report.md): **critical E1がpartial**。固定checker35/52、`release`から`releaseping`を生成し指定phase契約に違反する。E3もacquire failureでinitial()へ戻して次回IDを再利用する。E4は実行境界を置く一方、typed error/defect/interruptionの分担が不明示でpartial。E6はphaseとIDについての説明が実装と合わない。S3は「追加状態はlatest request IDと採用済み結果」と明示しており、既存bindingにあるresultの再利用を満たさない。自己検査の成功を動作正当性と混同しない。

r3-EのID再利用は固定checkerを変えず、親が別に次の再現列を実行した。`start recording(id=1) → fail(1) → start calibration(id=1)`。`assert.notEqual(firstId, nextId)`は実際に失敗。固定チェックリストE3の「fresh / IDs not reused」の検査であり、事後の基準追加ではない。失敗成果物は修正しない。

既知ledger「表示stateの二重保持／模擬と追加状態の不明示」「ケースと報告の不一致」に今回r1/r2/r3を関連付ける。新たに観測した機械的なphase名生成とcounter resetは、抽象モデルの契約を自己検査で照合しきれていない例として扱う。現時点のclearは0。

## 単独課題での反復方針

単独S/Eに加えBもfresh executorへ渡して一組とする。完成版の親採点が全てfullで候補手順の既知欠落もなければ、その後に同じ一課題一executorでさらに2組を反復する。この新しい3組のclearのみを数え、先の集約失敗組は別の観測として残す。本文は同じhashを維持する。3組が揃った場合だけ未使用Oで過適合を確認する。

## 単独課題の親評価

| Scenario | 成功 | 達成率 | 親の6項目スコア | steps / duration | retries |
| --- | --- | --- | --- | --- | --- |
| [E](evidence-single-e.md) | ○ | 100% | 1,1,1,1,1,1 | 取得不能 | 1（自己申告） |
| [B](evidence-single-b.md) | ○ | 100% | 1,1,1,1,1,1 | 取得不能 | 0 |
| [S](evidence-single-s.md) | ○ | 100% | 1,1,1,1,1,1 | 取得不能 | 0 |

Sは別のbinding模擬とlatest IDのみのMediatorに分かれ、currentSuccess/currentFailure/staleOutcomesAndRepeatedTextを新規状態から実行。親の再実行も全成功。検査名・実際のイベント列・実測がmemoに対応し、今回の構造仮説がこの一件では反映された。

Bは既存formatterと局所tooltipのみ。具体的な表示・送信状態・取得状態の確認を提案として区別し、実アプリ試験を成功扱いしない。アプリの関数名や起動方法がない点は入力の未指定で、対象skillの曖昧さではない。

Eは親checker52/52。memoは実際の反復要求・失敗を含む列を記載し、前回の「割込みなしの通常経路を実行済み」という虚偽の主張はない。固定E6はfullとして維持する。一方、候補が要求する最初の独立通常ケースはなく、複数assertion群を4 scenariosと呼んでいる。通常・失敗・反復を名前付き独立ケースにする手順やフィールド分類表は反映されていない。固定基準の100%と、変更した指示が意図どおり適用されたことを区別する。候補の既知欠落が残ったため、この組をqualitative clearとせず、予定していた追加2組の開始条件は成立しない。

## 候補の再現と採用判断

今回試したセクション全文。baselineの同名セクションをこれに置き換えると候補hashを再現できる。その他の本文・referenceは変更していない。

```markdown
## 制約のあるフローの成果物

状態間の制約があり、反復要求または資源所有の変化を含むフローを扱うときは、次の順で成果物を作る。

1. **状態対応表**: 状態名と所有者を列挙する。抽象モデルでは全フィールドを「既存 binding／実行層の模擬」「本実装で追加する裁定状態」「検証専用」に分類し、既存状態の再利用箇所を示す。
2. **独立した検査ケース**: 操作方針から、実行前に各ケースの期待する `前状態 / イベント列 / 後状態 / 資源所有者 / 実行効果` を定める。通常・失敗・反復要求を名前付きの別ケースにし、各ケースを新しい初期状態から始める。最初の通常ケースは、初期状態から完了まで割込みなく assertion で実行する。
3. **実行記録からの報告**: 各ケースで実際に与えたイベント列、検査出力、期待結果との照合結果を記録する。遷移表と検証メモはこのケース記録から作り、対応する検査名を示す。実行できない項目は未実行と書く。
```

**候補は不採用とし、対象本文をbaselineへ戻す。収束は認定しない。** 実行した12 scenario（集約3組=9、単独3件）で、新しい検証手順が安定して実行される証拠は得られなかった。単独Sでは手順・責務とも改善が見えたが、単独Eにも手順欠落が残った。集約実行ではcriticalな生成モデル不具合と既知のbinding責務不明示も観測した。ただし課題集約が原因とも、候補本文が悪化原因とも断定しない。

既知パターンが追記・冒頭移動・今回の手順化でも残るという構造的な再発を記録する。今回行った構造変更自体を採用できない以上、さらに同義の文言を足して試行を続ける根拠はない。停止区分は、構造変更の不採用を伴う **resource cutoff**。`qualitative plateau` や `strict convergence` の達成とは扱わない。tool_uses/duration_msも取得不能で、時間・費用の改善は主張しない。

Oは収束後に実行するためのholdoutとして事前に固定したが、実行条件に到達しなかったため **未実行・未使用** のまま残す。未使用holdoutの合格や過適合なしを主張しない。追加2組も条件未成立のためdispatchしていない。対象本文は `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6` に復帰した。

判断: 現行のUI/Effect責務分担を維持し、実装や検証の自己申告だけで品質を保証しない。今回得た確実な知見は、手順化した指示でも自己検査は契約違反を見逃し得ること、固定された独立検査と本文・コード照合でそれを検出できること。モデル出力のエラーをE専用の文字列修正规則としてarchitecture skillへ取り込まない。

r3診断: phase文字列生成ではstopの規則をreleaseへ一般化、失敗後idleへの遷移ではrun全体の初期化と混同した。Sでは検証を自己完結させるためにbinding stubと裁定stateを混ぜたと実行者が確認。複数課題の一括提示が原因かは推測であり、確認できるのは成果物の分類・検査手順より小さいコードとlint通過を優先したこと。構造review1件と診断follow-up1件は12 scenarioの件数に含めない。

## 最終検証

- 候補のquick_validate、local-skills.bats 18/18成功。
- 親が全8モデルの自己検査を再実行して成功。独立checkerは4つのEに適用し、r1/r2/single各52/52、r3は35/52。r3は失敗証跡として保存し、修正して評価を上書きしない。
- 実設定oxlint/oxfmt、Markdown参照先、git diff --checkを確認。候補セクションを記録から復元したSHAも実行時hashと一致した。
- 本文はbaselineへ復帰し、referenceとcheckerのhashは不変。実アプリ統合・HOME配備・push・PR作成は行っていない。
