# 実行可能モデルによる評価

続き: [検証手順とbinding再利用の構造変更](structure.md)。以下の過去の採点・不採用判断は保持する。

[事前固定した契約](protocol.md)。既存の [メモ評価](../mvp-mediator-20260920/confirmation.md) とは成果物・課題条件が異なるため、達成率の改善を直接比較しない。現行スキルのまま新契約で評価し、必要性が確認できた場合だけ本文を変更する。

対象 hash: `6ace6b48ea30aaf24a000057524c5a8cb70c972358094bc21446f0a75f062819`、reference: `a446ebe95eb01feddbc8fd30041db60d9b66dcb07e629fcd3e5bbeeaf97a27d8`。本文・description は変更なし、Iter 0 の範囲整合を確認。

チェックリストと検査の意味を実行者 dispatch 前に固定。checker は候補成果物を読む前に repo lint の指摘に従って import、関数形式、キー順、厳密比較を整形した（判定条件は不変）。採点時 checker SHA-256: `72adc7af373705e1324d26c48cec7eec123e5bbbc493f77bf1f34d259eb05ae1`。実行者は checker、他課題、前回報告を参照しない。2回目は同じ本文・同じ契約で、初回 E の結果判定前に dispatch した独立反復であり、適応的な修正ラウンドではない。

```sh
node docs/evaluations/mvp-mediator-executable/check-device.mjs docs/evaluations/mvp-mediator-executable/e1.mjs
node docs/evaluations/mvp-mediator-executable/check-device.mjs docs/evaluations/mvp-mediator-executable/e1.mjs --known-bug
node docs/evaluations/mvp-mediator-executable/check-device.mjs docs/evaluations/mvp-mediator-executable/e4.mjs
```

第2コマンドは取得中の対象への要求を無条件に無視する既知の欠陥を注入する negative control で、非ゼロ終了が期待される。実運用のモデルには適用しない。第3コマンドも保存した不合格モデルの再現なので、51/52成功・非ゼロ終了が期待値。

## Round 1

Changes: 対象本文は変更なし。Pattern monitored: 既知の状態別方針の不一致と、要求更新による実行識別の無効化。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E1](e1.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 未申告（整形1） | — |
| [B1](b1.md) | ○ | 100% (6/6) | 取得不能 | 取得不能 | 0 | Formatting（Trace） |

親の各項目評価 [1,1,1,1,1,1]。E1 は独立 checker 52/52 pass、known-bug 注入時47/52 passで期待どおり exit 1。失敗した5件は取得待ちで calibration の要求後 recording に戻す列を含む。自己チェックだけの green と区別して記録する。

B1 自己評価は formatter の実名未提示を理由に B-4 partial。課題は変更メモで、既存 formatter の再利用と局所状態の方針を明示すれば達成するため親は full。API の実名は架空アプリ側の未指定であり、対象指示の曖昧点ではない。

E1 の未指定事項は acquire 失敗後の desired 保持／消去で、idle から自動再試行しないという要件に影響しない。実行者は保持を選択。独立検査もこの未指定部分を採点しない。新しい対象指示の曖昧点・ledger 再発なし。qualitative clear 1回、次の本文修正なし。

B1/B2 の呼出しで Trace を単に「four phases」と略したため、実行者は作業フェーズではなくアプリ動作等に分類した。親の invocation contract の省略として記録し、対象スキルへ規則を追加しない。事後補足で両者とも Understanding（範囲把握）/Planning（最小メモ）/Execution（メモ作成）/Formatting（指定構成）を OK と回答。元メモを置換せず補足として保持する。

## Round 2 と初回 holdout

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E2](e2.md) | ○ | 91.7% | 取得不能 | 取得不能 | 0 | Execution / Formatting |
| [B2](b2.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | Formatting（Trace、親の指示省略） |
| [S](search.md) | ○ | 91.7% | 取得不能 | 取得不能 | 0 | Planning / Formatting |

E2 親評価 [1,1,1,1,1,0.5]、B2 全1、S [1,1,0.5,1,1,1]。critical 全達成。E2 のモデル自体は独立検査52/52成功。

- E2 Issue: 同梱assertに停止失敗がないのにメモの基準6で確認済みと述べた。Cause: 実装可能な遷移と実際に実行した検査を混同。General Fix Rule: 実行結果に裏付けられた範囲だけを実施済みとして報告する。実行者も事後に E-6 partial と認めた。
- S Issue: memo はbinding再利用を述べるが SearchMediator が pending/results/error を持ち、検証用の模擬状態なのか追加状態なのか不明瞭。Cause: 抽象モデルと本実装の所有境界を明示しなかった。General Fix Rule: 模擬したbinding状態と本実装に必要な追加coordinationを分ける。実行者は模擬する意図だったと回答し、S-3 partial を認めた。

Ledger: 既知の状態遷移の反例はモデルでは再発なし。今回の新規パターンは「検証用の表現を実装・実施済みの証拠と混同する」。見かけの自己評価は両者全達成だった。対象は Execution/Formatting にある検証記録の境界であり、状態遷移そのものへの注意文追加とは分ける。

### 変更前の対応付け

E2 実行者が提案文「既存の実行手段で遷移をassertし、実行した検査と未実行の確認を分け、実行結果に裏付けられた範囲だけを報告する」を E-6 の実行済み検査という判定へ対応付けた。S 実行者も S-3 の既存binding再利用を判断するため模擬状態と追加状態の区別が必要と述べた。この一つのテーマに限り、skillの再生段落末尾を実行・報告・模擬境界の指示へ置換する。前回の不採用構造変更は復活させない。

S は使用済みなので以降は固定回帰課題へ加え、holdout扱いしない。E/B/S の各6項目を変えず、新規実行者で2回再評価する。qualitative clear は0に戻る。

提出形式の補足: E1 の post-evaluation formatting retries は1（初回本体は未申告）。E2 の空設定 lint 成功は repo 検証として採用しない。親の環境では実設定を読み込めたため、キー順・関数形式・start分岐の同等な関数抽出を行い、同梱自己検査と独立52件を再実行して成功した。候補出力の意味・assertの内容は変更していない。

## 修正版の評価前提

対象 hash は `4adf2c8419fe95142dea64761eaa4e045df9a0d4d8ef16e7e0867d02acff2459`。E/B/S の固定採点基準と checker は不変。新しい [holdout T](holdout.md) を事前固定した。ここからの2回は修正版だけを使い、前回の低評価を後付けで改善しない。

## Round 3 — 修正版

Changes: 検証用表現と実際の実装・実施済み検査を区別する指示へ末尾を置換。Pattern applied: 検証用の表現を実装・実施済みの証拠と混同する。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E3](e3.md) | ○ | 100% | 取得不能 | 取得不能 | 未申告 | — |
| [B3](b3.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | Formatting（Traceの意味） |
| [S2](s2.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

親評価は各 [1,1,1,1,1,1]。E3 独立検査52/52成功。同梱assertにstop失敗とrelease失敗があり、メモの実行範囲と一致。S2 は SearchBinding を既存bindingの模擬と明示し、Mediator は最新IDだけを持つ。成功・失敗の採用検査を実際に実行。B3 は実行モデルを追加しない。新たな対象指示の曖昧点・ledger再発なし、qualitative clear 1回。

E3 の retries 記述はモデル内のstop/release retry回数で、実行者の判断やり直し回数ではないため、運用メトリクスとして採用しない。B3/B4 の Trace は memo作成をExecutionとして扱わず、アプリ実装の未実行をskippedとした。指示の自己報告契約への不遵守として残し、対象アーキテクチャの6項目へ後付け採点しない。

裁量: E3 は取得失敗後 desired を消去、S2 は取消要求を記録するmock bindingを使用。どちらも固定方針に合う。S2 の模擬bindingクラスをオブジェクトfactoryへ、E3 の start 分岐を関数へ抽出する等、親が repo lint のための意味を変えない整理を実施し、自己検査／独立検査を再実行した。生成時の判定と提出形式の整理を混同しない。

次の修正なし。同じ本文の独立反復を先行dispatchしており、判定後に都合よく課題や検査を変えていない。

## Round 4 — 独立反復と holdout T

Changes: Round 3 と同じ候補本文。判定前に独立 dispatch した反復であり、同じ実行者のやり直しではない。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| [E4](e4.md) | × | 83.3% | 取得不能 | 取得不能 | 0 | Execution |
| [B4](b4.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | Formatting（Traceの意味） |
| [S3](s3.md) | ○ | 91.7% | 取得不能 | 取得不能 | 0 | Planning / Formatting |
| [T](t.md) | ○ | 100% | 取得不能 | 取得不能 | 0 | — |

E4 親評価 [0.5,1,1,1,1,0.5]、B4 と T は全1、S3 は [1,1,0.5,1,1,1]。自己評価は各全達成だった。E4 自己checkは成功するが、独立checkerは51/52成功に留まる。

- **E4: [critical] E-1 partial**。idleから最初のstartでdesiredがnullのままになり、反復要求なしで取得を完了すると不要なstop/release後にacquire(null)を発行する。自己checkは完了前の反復要求でdesiredを更新するため、この通常経路の欠落を隠した。Issue: 繰り返し要求の検査が通常経路の初期化漏れを隠す。Cause: 通常・失敗・反復要求をそれぞれ独立に再生する既存指示が、実際のassert集合へ完全に反映されなかった。General Fix Rule: 初期状態からの通常経路を独立したassertとして実行した後、待機中の介入を検証する。E-6もpartial。実行済み範囲の記述は正しいが、メモの宣言方針と実装の通常経路が一致せず、その差を具体checkが捉えない。事後診断で実行者もE-1/E-6の未達を認めた（実行者は両方×と回答）。親は他の待機遷移と実行済み範囲の正確さを部分達成として各0.5点とした。
- S3: 既存bindingの再利用とlatest IDだけの追加を述べるが、モデル内view.pending/result/errorやnextRequestIdの所有区分を明示しない。実行者は事後に、その区別を示す箇所が元メモにはないと確認した。Issue/Cause/General Fix RuleはSと同じ。候補の「模擬状態と追加状態を明示」だけでは、実フィールドとの対応が抜ける。実行者の次案は、各stateフィールドを既存bindingの模擬／本実装の追加状態／検証専用に対応付けること（S-3の判定文に対応）。今回は未適用。
- T: refreshで選択を保持し、click時のsnapshotを後続選択から隔離、権限をuse caseで判定するassertを親も実行。模擬bindingとproduction追加stateなしを明示。具体API未指定は課題の抽象化によるもので、対象指示の曖昧さとは扱わない。Tは使用済みholdoutとなる。

Ledger更新: 「検証用の表現を実装・実施済みの証拠と混同する」はS3で再発。「状態別規則と宣言方針の不一致」はE4で再発し、従来の反復要求の枝とは異なる初期化の欠落を独立検査が検出した。検査不足をすべて指示の曖昧さへ帰属せず、指示への実行不遵守も含む観測として保持する。qualitative clearは0へ戻る。

## 採否と停止判断

**Resource cutoff、収束未達。候補本文は不採用。** 今回は12実行（E×4、B×4、S×3、T×1）。検証報告を改善した例はあるが、同じ候補の独立反復でcritical失敗と既知パターン再発があった。少数標本なので候補が失敗の原因だとは断定しないが、本文を長くするだけの安定した改善も確認できない。対象スキルを開始時の本文（hash `6ace6b48ea30aaf24a000057524c5a8cb70c972358094bc21446f0a75f062819`）へ戻し、ADR-0063に従った既存の責務分担は維持した。

不採用候補は、再生段落の末尾「確認項目の期待結果は同じ再生から導き、説明・遷移表・確認項目をその記録に一致させる。」を次で置換したもの。他の本文・reference・descriptionは変更していない。

> 利用できる既存のテスト手段で同じ遷移を assertion として実行し、説明と確認項目をその結果に照合する。実行済みと未実行の確認を分け、実行結果で裏付けた範囲だけを報告する。抽象モデルを使う場合は、検証用に模擬した binding／実行層の状態と、本実装で追加する状態を明示する。

停止根拠はempirical-prompt-tuningのResource cutoff条項。旧メモ評価を含む反復で指示追加の限界が見え、今回の成果は独立checkerで自己評価の誤判定を再現可能にしたことにある。新たな文言の継ぎ足しを続けず、再開時は通常経路からのassert集合とフィールド所有区分を成果物に対応付ける構造案を別候補として検証する。既存チェックリスト・52件のoracle・失敗成果物は緩めない。S/Tは回帰課題へ移し、次のholdoutは新規に事前固定する。

`tool_uses` / `duration_ms`は未取得。推測値を補わず、strict convergenceもqualitative plateauも宣言しない。元の自己報告は保持し、親の補正採点を本ファイルで分離する。失敗モデルE4を正しい実装例として流用してはいけない。

## 提出時の検証

評価後、E4/S3の関数形式・キー順・分岐抽出、Tのmock classから同じ操作を持つobject factoryへの整理を含め、repoの実設定でlint/formatに適合させた。memoの自己評価とassert内容、E4の初期化漏れ、S3の所有区分の不明瞭さは修正していない。メモ中の生成時クラス名は整理前の表現として保持する。

- 全8モデルの同梱assertは成功。E1/E2/E3は親の独立検査52/52成功、E4は51/52で同じ通常経路の失敗を再現。
- E1へのknown-bug注入は47/52成功・exit 1。失敗を検出できることを確認。
- 評価ディレクトリ全体の実設定oxlint・oxfmt、ローカルMarkdownリンク、git diff --checkは成功。
- この作業中の `bats tests/local-skills.bats` は18件成功。最終の本文は開始時hashと一致し、追加候補の配備はしていない。アプリのReact/Query/Effect統合テストは対象外。
