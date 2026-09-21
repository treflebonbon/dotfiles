# ケース定義から実行記録を作る例の評価

Baseline: `e86800981736e79800c1e7acf50f680a046ef82d`。対象本文hash `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`。Iter 0: descriptionと本文の適用範囲は一致。前回の[手順化候補](evidence.md)は不採用のまま保持する。

既知ledger: 通常経路を反復ケースで代用する、実際の検査と報告が食い違う、抽象モデルのbinding模擬と追加裁定状態が混ざる。強調・冒頭移動・手順化で安定しなかったため、今回は実行と記録に同じケース定義を使う短い例を条件付き参照に置く一テーマを試す。E固有の遷移解法や失敗fixtureへの修正を本文へ取り込まない。

## 固定評価

[既存E/B/Sの6項目](protocol.md)、critical、full1/partial0.5/absent0の採点を維持。Eには変更しない52ケースchecker、Sにはコードと自己検査の照合、Bには変更範囲と検証主張の照合を用いる。自己申告と親判定は別記。tool_uses/duration_msは提供されなければ取得不能のまま。

新規gpt-5.6-terra/high executorへ1人1課題で渡し、履歴・他の出力・親checkerを読ませない。1組E/B/Sを評価し、同じ候補で3組clearを目指す。通常経路の独立実行とstate分類は対象指示の適用を確かめるqualitative指標として確認し、固定の点数基準を後から追加変更しない。欠落した組はclearを0へ戻し原因に対応する一テーマだけを修正する。

3組clear後は[未使用Holdout O](evidence.md)を初めてdispatchする。前回Oは実行していないので、新規holdoutとして使用できる。3組が揃ってもcanonical usage metadataがなければstrict convergenceとは呼ばず、qualitative plateau; quantitative convergence unverifiedと報告する。

## 適用前の判定文言への対応

構造reviewがE6「model / memo / concrete checksが一致」「実行した実結果」、S6「memo/model一致」「checks実行済み・制約明記」への対応を確認した。今回追加する例は同じ名前付きケースから実測ログを作り、assertionを通した記録からmemoを作る構成。E固有の録音・解放方針の例は使わず、仮の重複送信無視方針を示す。抽象モデルを作る場合だけの参照なのでBには新たなmodelや記録を要求しない。構造reviewは実行評価・clearに含めない。

候補本文hash `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`、新reference hash `b13abd54adefb9f7473f9a4932b7487c5ac589101f89fda6c5e7dc35b383c32b`。例のコードブロックは仮方針に対応する小さいテスト用遷移へ接続して3ケース成功を確認し、successの遷移先を誤らせた負例ではassertion失敗を確認した。これは例の検証でありskillの独立実行評価ではない。

## 第1組

最初のB executorは指定したB以外を含むprotocol全文を読んだと申告した。[出力](example-1-b.md)を保持するが、入力隔離違反として採点とclearから除外する。失敗結果の選別ではなく、事前の入力契約違反による除外である。新規executorにはBの課題と同じ6基準を直接渡し、評価ファイルの読取りを禁止した。

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](example-1-e.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 0 | — |
| [B 再実行](example-1-b-valid.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 0 | — |
| [S](example-1-s.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 0 | — |

親はSの全コードとメモを照合し、4つの名前付きassertionを再実行して成功を確認した。通常成功、現在失敗、同じtextの反復と古い成功、古い失敗を別々の初期状態で実行している。binding.requestsが通常pending/result/errorを所有し、latestRequestIdだけが追加裁定、nextRequestIdは検査用の採番という区別も記録されている。実際のQueryがどのIDを提供するかはアプリ未指定のため、この抽象モデルから実装APIの保証は導けない。

Bはformatter・tooltipに限定し、アプリの検査は未実行としている。メモのoxfmt行は「実行予定」のままで最終回答の実行成功と時制が異なるが、B6が要求するアプリ検査の過大主張ではない。caller向け報告の不一致として別記する。Sの自己申告は新規不明点なし。

Eの完成後、親が全コードとメモを照合し、自己検査6件と固定checker 52/52成功を確認した。取得失敗後の再開始でもIDを再利用せず、旧成功・旧失敗を無視することを追加でassertion確認した（E3の既存文言の確認であり固定checkerは変更しない）。通常経路は独立した2イベントのケースで、反復・失敗・資源切替は別ケース。全状態フィールドが分類され、failedStageを含む操作方針の状態が検証専用と混ざっていない。自己申告の「取得失敗後のdesired保持」は課題が許す補完であり、新しいskillの曖昧さには数えない。

第1組: qualitative clear 1。metadataがないためstrict convergenceのroundには数えない。第2組と第3組は同一候補の再現性を確かめる独立実行であり、dispatch順の組を維持する。

## 第2組

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](example-2-e.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 2 | caller向け入力記録 |
| [B](example-2-b.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 0 | — |
| [S](example-2-s.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 2 | 状態説明の網羅性 |

Bは既存formatterと局所tooltipの変更提案だけで、未実行アプリ検査と実行済み文書検査を分けている。未提示のimport/APIは課題側の補完事項でありskillの新規曖昧さではない。

Eは自己検査5件と固定checker 52/52成功。親は全コード・メモを照合し、取得失敗後にIDを再利用しないことと旧成功・旧失敗の除外も追加assertionで確認した。状態フィールドは分類され、通常・失敗・反復のケースも独立している。INPUT hashはtarget skillではなくprotocol全文のhashだった。完成後、成果物を編集させず初回作業記録だけを確認し、Git確認直後にSKILL.md全文、protocolはE節だけ、条件付きreferenceを読んだと回答を得た。他の評価内容/checkerは未読。対象候補はdispatch期間中変更していない。入力隔離違反とは扱わず、caller向け入力記録の誤りとして残す。YOUR Traceも作業phaseでなくモデルのphaseだがallOK表記はあり、skillの責務基準へ転嫁しない。

Sは親の再実行で7件成功。通常・失敗・反復要求の独立ケースとbindingの通常状態再利用はできている。一方、状態対応表は`nextRequestId`、bindingの`effects`、`cancelRequested`を個別に分類していない。表の「取消要求」からcancelRequestedの役割は推測できるが、全フィールドを分類する指示を満たしたとは扱わない。モデルは局所オブジェクトとモジュール変数を更新する模擬実行であり、純粋なstate/event関数としての検証ではない。`serverRollback: false`はケース内で作った定数の照合で、実サーバーの取消挙動の証拠ではない。tooltip検査も独立した表示値の生成のみで、アプリのtoggle実行ではない。browser/runtimeの検証を主張していないため、これらを新しい固定減点基準にはしない。

固定6項目の成功と、対象指示の適用漏れは区別する。第2組は状態分類のqualitative指標が未達のためclearを0へ戻す。既知ledger「抽象モデルのbinding模擬と追加裁定状態が混ざる」の網羅性不足が再発した。例は検査ケースと記録の対応には効いたが、本文にある全状態の分類までは保証しなかった。指示の位置・強調を繰り返して安定したと解釈せず、第3組も同じ候補のまま完了させる。

## 第3組

| Scenario | 自己申告 | 親判定 | Accuracy | steps / duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E](example-3-e.md) | 全6項目○ | ○、E6 partial・他full | 91.7% | 取得不能 | 2 | 状態説明・caller向け入力記録 |
| [B](example-3-b.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 0 | — |
| [S](example-3-s.md) | 全6項目○ | ○、全6項目full | 100% | 取得不能 | 1 | — |

Bはアプリやモデルを作らず、formatterとtooltipの局所変更、複数Context consumer、業務・送信所有者の維持、未実行アプリ検査の明示を満たした。Traceのphase名はcallerが指定した4phaseと異なるが、許可したallOK表記もあり、対象skillの基準や新たな曖昧さとは混同しない。

Sは親の再実行で4件成功。最新IDでbindingを選び、同じtextを3回送った後の旧成功・旧失敗は新pendingを変えず、新成功だけを表示する。通常・失敗・反復が独立し、tooltipの操作もモデルにある。bindingの模擬は可変Mapを使うため、純粋なtransition関数を検証した成果物とは区別する。実binding/APIの統合は未検証。

Eは自己検査4件と固定checker 52/52成功。取得失敗後のID再利用防止も親の追加assertionで確認した。しかしメモは`pendingTarget`と`failedStage`を「検証専用」に分類する。コードは取得成功時のownerをpendingTargetから決め、retryの実行段階をfailedStageから決めるため、この情報は実際の操作方針に必要である。本実装で他の型や既存bindingに置き換える説明もなく、検証だけに使う状態という説明とは一致しない。E6「model/memo/checkの一致」をpartialとした。critical E1/E2はfullなのでbinaryは○を維持する。第3組もclearではなく、連続clearは0。

EのINPUT hashはtarget skillでなく抽出したScenario E節だった。完成後の読取り記録確認では、Git確認後にSKILL.md全文、次に条件付きreferenceとE節のみを読み、他の評価内容/checkerを読んでいないと回答した。メモは修正させずcaller契約の不一致を保存する。

## 構造化振り返りと判断

- Issue: ケース名・実測記録は改善したが、実装で必要な裁定情報と検証専用状態の分類漏れ・誤分類が残った。
- Cause: 実行記録の例はassertionと報告をつなぐが、状態の用途を確認する手順までは具体化しない。本文の状態表と条件付きの検査例が別々に適用された。
- General Fix Rule: 状態の分類は名前や抽象モデル内にあることではなく、実装の判断でその情報を必要とするか、既存機構から供給されるか、検査だけで使うかを根拠にする。
- Ledger: 既知の「抽象モデルのbinding模擬と追加裁定状態が混ざる」を第2組S・第3組Eで再観測。新しい個別注意書きやEの解法を追加して再試行を重ねず、今回の候補を不採用にする。

有効な独立実行9件のbinaryは全件○、固定基準の平均は99.1%。入力隔離に失敗したB1件は別途保存・除外。親の再実行はE/S計6モデルの自己検査30件、Eの固定検査は各52/52。高い固定スコアだけでは対象指示の全適用や報告の正確さを保証しない。qualitative clearは1→0→0で、3連続を満たさない。

今回の停止は **resource cutoff**。前回の強調・手順化に続き、実行例を追加する構造変更でも既知の説明不一致を解消できなかった。追加の文言を重ねる費用に対して安定した改善を示せず、metadataも取得不能でstrict convergenceを検証できない。qualitative plateauも宣言しない。Holdout Oはdispatch条件に達しなかったため未実行のまま残す。ユーザーのEffect優先方針やADR-0063の責務分担を変更する根拠にはしない。

スキル本文はbaseline hash `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`へ戻す。候補referenceは削除せず[原文](model-verification-candidate.txt)を評価資料として移動保存する。候補を再構成する差分は、baselineの「説明と遷移表がこの記録に一致することを確認して完了とする。」の直前に、次の同一段落の文を挿入し、保存原文を`references/model-verification.md`に置くものだった。

```text
抽象実行モデルを作る場合は [検査と記録の例](references/model-verification.md) を読み、ケース定義を実行と報告で共用する。
```

## 保存時の検証

6モデルの自己検査30件、Eの固定checker各52/52、取得失敗後のID再利用とstale成功・失敗の追加assertionは成功。repo設定のoxlintとoxfmt、skill quick_validate、git diff --checkも成功した。このturnで実施した`bats tests/local-skills.bats`は18/18成功。候補referenceの例は正常3件と誤った遷移先を検出する負例で確認済み。復元後のskill hashと保存reference hashが記録値に一致することも確認した。実React/Effect/Atom/Queryの統合やbrowser検証は行っていない。
