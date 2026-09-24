# MVP評価専用の実行入口

## スキル配布終了後の保存入力（2026-09-24）

[共同判断](evaluations/mvp-mediator-ab-20260924/decision.md)とユーザー承認に基づき、現行スキルの配布元を撤去した。CLIと本文例テストは、[固定保存したv17本文](evaluations/mvp-mediator-ab-20260924/original/skill/SKILL.md)・参照を読む。本文hash、課題、checker、runtime、採点処理は維持する。新しい評価を自動実行する変更ではない。

旧runの`status`は引き続き参照できる。CLIの変更前に作成したrunは既存のimplementation hash照合で書込み再開を拒否し、旧start/auditを更新して再開させない。過去の評価資料・採点は保存する。配備済みhomeへの反映は受入・merge後のlive sourceで行う。

以下の版別記録は各実装時点の履歴であり、配布が現在も有効という意味ではない。

## v17接続（2026-09-24）

現行CLIは[v17契約](evaluations/mvp-mediator-evaluation-v17/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v17/design.md)に従い、要件欄の実装説明と根拠表の検証証拠を分け、報告する検証主張に比較式の短い抜粋を必須とした。正確な統合行・共通参照・要約を許容し、必要な検査の追加・実行条件を維持する。

抜粋の形式不足と検証範囲の過大報告は別判定。通常課題、v10 E/checker、runtime、採点アルゴリズムは維持する。旧runはstatus参照のみ可能で、新CLIでの書込み再開は拒否する。実LLM効果は未検証で、評価開始には別途明示的な依頼を要する。

### v17接続の検証結果

| 対象 | 検証 | 結果 |
| --- | --- | --- |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | v17未登録でred、接続後19/19成功。本文例・純粋性例・固定checker検査を含む |
| 形式・型 | skill validator、`bunx tsc --noEmit`、固定SOURCES照合 | 成功 |
| 本文の境界 | state/effects、helper、期待値変数、統合行、B提案、必要検査の文面レビュー | 合意した境界と一致。実LLM効果の検証ではない |
| Standards / Spec | `323224a`を固定点としてコミット前の6ファイルを独立レビュー | 両軸0件 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 1回完走。760件、735成功・23skip・2失敗、exit1。検査中の実装変更なし |
| 失敗の単独再確認 | 下記2テストをそれぞれfilter指定で実行 | コード変更なしで各1/1成功、exit0 |
| 保全 | SHA-256・履歴検証・旧run status・CLI AST比較 | 旧1539ファイル不変、16runの履歴/status成功。CLI処理はdocstring/SOURCES以外不変 |

全体runで失敗したのは `managed-chrome-owner.bats` の `Windows inspection distinguishes query failure from an absent browser`（期待エラー文言の照合）と、`raw-codex-integration.bats` の `raw return rejects a newly committed gitlink before publishing any result`（期待終了状態の照合）。いずれも今回未変更の処理で、単独再実行は成功した。失敗原因は未確定であり、全体runの失敗を取り消さず、一括実行での全件成功は未確認とする。

ログ、文面レビュー、両軸レビュー、保全記録は `tmp/mvp-v17-implementation/` に保存。実LLM評価・配備は未実施。

## v16接続（2026-09-24）

v16実装時のCLIは[v16契約](evaluations/mvp-mediator-evaluation-v16/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v16/design.md)に従い、抽象モデルを作らない提案は3列の状態説明表、説明対象がなければ一文で完了することを明記した。抽象モデル付きの成果物は従来の5列を維持する。

提案への専用2欄省略の適用を明示・拡張する変更として比較上の制限を記録する。保持状態がある提案の表は引き続き必須。課題・v10 E/checker・runtime・採点アルゴリズム・旧runを維持する。状態なし境界の実LLM効果は既存B課題では測れず未検証。実LLM再評価は別途明示された依頼で行う。

### v16接続の検証結果

| 対象 | 検証 | 結果 |
| --- | --- | --- |
| 本文と設計の一致 | `ec0d612...d53b432` のSpecレビューと追加差分の再レビュー | 既存局所状態の包含を明記する指摘1件を`d85a233`で修正、残り0件。formatterのみの状態なし提案・tooltip状態あり提案・抽象モデル付き提案の3境界を確認 |
| Standards | 初回差分を独立agentでレビュー、追加差分を親が照合 | 文書規約違反・ヒューリスティックとも指摘0件 |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | v16未登録でred、接続後19/19成功。レビュー修正後も19/19成功。本文コード例・checker検査も含む |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、Python AST/source hash、commit hooks | 成功。tscは既存TypeScript対象。Pythonは構文と公開CLIで検証。レビュー修正後の形式・hashも確認 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 最終版`d85a233`で1回完走。760件、737成功・23skip・失敗0、exit0。完走した検査中のコード変更なし |
| 旧記録と実行ロジック | 変更前後のSHA-256照合、15 runの履歴検証・status参照、CLIのAST比較 | 旧評価・runtime・条件付き参照の計1,460ファイル不変。版説明とsource登録以外のCLIロジック不変 |

ログ・red→green・レビュー・保全記録は `tmp/mvp-v16-implementation/` に保存。`d53b432`で開始した全体テストはSpec修正のため途中停止（exit143）し、ログを別保存した。その未完了実行は成功実績へ含めず、最終版で上記の全体テストを実行した。

全体テスト後の変更は設計状態と本書の検証記録のみで、親が実行記録と照合する。実LLM評価・配備・pushは未実施。状態なし境界は文面レビューで確認したもので、実LLM効果の実証ではない。旧未追跡runは今回のcommitへ追加していない。

## v15接続（2026-09-23）

v15時点のCLIは[v15契約](evaluations/mvp-mediator-evaluation-v15/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v15/design.md)に従い、状態分類の比較例を正式な状態表と同じ5列へ揃え、手順3もモデル表現と本実装情報源を「表の別々の欄に記す」と明記した。

v14の役割分類と別欄要件を維持する説明・例の整合であり、要件緩和ではない。形式遵守と説明内容の正確さは分けて評価する。検証範囲の過大報告とBの表省略への対策は別テーマに残し、既存基準で引き続き判定する。

固定配布の版登録を更新し、v10 E/checker・runtime・採点アルゴリズム・旧runを維持する。実LLM再評価は別途明示された依頼で行い、静的整合やfixture成功を行動改善の実証には数えない。

### v15接続の検証結果

| 対象 | 検証 | 結果 |
| --- | --- | --- |
| 本文と設計の一致 | `aaa18d1...0f51ac6` のSpecレビュー | 指摘0件。5列の見出し・順序と4例の意味、手順3、既存要件の維持を確認 |
| Standards | 同差分を独立agentでレビュー | 文書規約違反・ヒューリスティックとも指摘0件 |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | v15未登録でred、接続後19/19成功。既存の本文コード例・checker検査も含む |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、Python AST/source hash、commit hooks | 成功。tscは既存TypeScript対象。Pythonは構文と公開CLIで検証 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `0f51ac6`で1回実行。760件、737成功・23skip・失敗0、exit0。検査中のコード変更なし |
| 旧記録と実行ロジック | 変更前後のSHA-256照合、14 runの履歴検証・status参照、CLIのAST比較 | 旧評価・runtime・条件付き参照の計1,344ファイル不変。版説明とsource登録以外のCLIロジック不変 |

ログ・red→green・レビュー・保全記録は `tmp/mvp-v15-implementation/` に保存。全体テスト後の変更は設計状態と本書の検証記録のみで、親が記録との一致を確認する。実LLM評価・配備・pushは未実施。静的整合やfixture成功を行動改善の実証に数えない。旧未追跡runは今回のcommitへ追加していない。

## v14接続（2026-09-23）

v14時点のCLIは[v14契約](evaluations/mvp-mediator-evaluation-v14/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v14/design.md)に従い、状態説明を使い道の確認、情報の役割による分類、モデル表現と本実装の情報源の分離という3手順と比較例へ置き換えた。4分類と全保持フィールドの説明を維持する。

操作IDを発行するモデル内の連番は、既存のID発行機構を模擬する役割として説明する。追加の採用判断、View局所、検査だけの補助との違いを使用箇所から確認する。既存の保証で足りる場合は状態を重複保持しない。

評価契約と固定配布を更新し、v10 E/checker・runtime・採点アルゴリズム・v13の正確な統合行の許容を維持する。旧runは再採点しない。実LLM評価は別途明示された依頼で行い、今回の実装検証を分類精度の実証には数えない。

### v14接続の検証結果

| 対象 | 検証 | 結果 |
| --- | --- | --- |
| 本文と設計の一致 | `aa496e7...0a31828` のSpecレビュー | 指摘0件。4分類、全保持フィールドの使い道・表現・情報源、未確認の扱い、例の非強制が設計と一致 |
| Standards | 同差分を独立agentでレビュー | 文書規約違反・ヒューリスティックとも指摘0件 |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | v14未登録でred、接続後19/19成功。既存の本文コード例・checker検査も含む |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、Python AST/source hash、commit hooks | 成功。tscは既存TypeScript対象。Pythonは構文と公開CLIで検証 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `0a31828`で1回実行。760件、737成功・23skip・失敗0、exit0。検査中のコード変更なし |
| 旧記録と実行ロジック | 変更前後のSHA-256照合、13 runの履歴検証・status参照、CLIのAST比較 | 旧評価・runtime・条件付き参照の計1,260ファイル不変。版説明とsource登録以外のCLIロジック不変 |

ログ・red→green・レビュー・保全記録は `tmp/mvp-v14-implementation/` に保存。全体テスト後の変更は設計状態と本書の検証記録のみで、親が記録との一致を確認する。実LLM評価・配備・pushは未実施。静的検証やfixture成功を分類精度の実証に数えない。旧未追跡runは今回のcommitへ追加していない。

## v13接続（2026-09-23）

v13時点のCLIは[v13契約](evaluations/mvp-mediator-evaluation-v13/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v13/design.md)に従い、根拠表の観測時点ごとの行分割を推奨へ変更した。統合行でも、各時点の対象値・比較相手・assertion・実行結果の対応と、未実装／未実行の区別は必須とする。表の列構成とコード例は維持する。

正確な統合行だけを形式違反として減点・再発停止へ数えない。要件緩和によるclear増加と報告精度の改善は区別し、旧runを再採点しない。E課題と親checkerはv10のまま、runtimeと採点アルゴリズムも維持する。

検証は既存の `bats tests/mvp-evaluation.bats` と本文コード例のNode検査を再利用する。報告生成器や表パーサーは追加しない。実LLM再評価は実装完了後の明示的な依頼で開始する。

### v13接続の検証結果

| 対象 | 検証 | 結果 |
| --- | --- | --- |
| 本文と設計の一致 | 最終本文とv13設計のSpecレビュー | 指摘0件。正確な統合行と分割行を許容し、各検証主張の根拠・結果・未確認の区別を維持 |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | v13未登録でred、接続後19/19成功。v10 E/checker、旧run参照と書込み再開拒否を維持 |
| 本文コード例 | `node --test tests/mvp-reporting-example.mjs tests/mvp-purity-example.mjs` | 既存2件成功。報告例のstate/effects照合と、不正な旧通知effectsの拒否、純粋性比較の検出を維持 |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、oxlint、Python AST/source hash、commit hooks | 成功。tscは既存TypeScript対象で、Pythonは構文と公開CLI、JS例は実行とlintで検証 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `f1169bb`で760件、737成功・23skip・失敗0、exit0。1回実行し検査中のコード変更なし |
| Standardsレビュー | `bfcdcbd...f1169bb` | 文書状態表記2件を指摘。設計の実装完了状態と旧v12節の「現行CLI」を修正。ヒューリスティック指摘なし |
| 旧記録の保全 | 変更前後のSHA-256照合 | 旧評価ファイル1,212件の変更なし。旧契約・checker・run・採点を保持 |

ログ・red→green・レビュー・保全記録は `tmp/mvp-v13-implementation/` に保存。全体テスト後の変更は設計状態と本書の検証記録のみ。実LLM再評価・配備・pushは未実施。行分割要件の緩和やfixture成功を報告精度の改善として扱わない。旧未追跡runを今回のcommitへ一括追加していない。

## v12接続（2026-09-23）

v12時点のCLIは[v12契約](evaluations/mvp-mediator-evaluation-v12/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v12/design.md)に従い、根拠表を最終assertionの観測時点・対象値・比較相手から作る手順へ整理した。短いコードと対応表でstate維持とeffects空、別時点の未検査effectsを区別する。v11の純粋性比較順序、状態分類、課題・checker・runtime・判定基準は維持する。

本文の例は `node --test tests/mvp-reporting-example.mjs` で直接実行する。旧通知のeffects空を確認し、不正なeffectsを拒否する。現通知のeffectsを確認しない例であることと根拠表の対応は別途レビューする。公開CLI fixtureは `bats tests/mvp-evaluation.bats`。例やfixtureの成功は実LLMの報告精度の証明ではなく、実評価は次の明示的な依頼で開始する。

### v12接続の検証結果

比較起点 `eba6b83`、実装 `bae95ec`。全体検査は同コミットで1回実行し、検査中のコード変更なし。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| assertion起点の手順と表の対応 | 最終本文とv12設計のSpecレビュー | 指摘0件。旧通知のstate比較とeffects空を個別に記録し、現通知のeffectsは未実装。正確な要約、全assertion転記不要、必要検査の追加を維持 |
| 本文のコード例 | `node --test tests/mvp-reporting-example.mjs tests/mvp-purity-example.mjs` | 2/2成功。新例は実際の本文を実行し、正常な旧通知と誤った旧通知effectsの拒否を確認。現通知effectsは非空でもこの例の検査対象外。既存の純粋性例と5つの不正例検出も維持 |
| 固定配布・旧版境界 | `bats tests/mvp-evaluation.bats` | 19/19成功。v12を固定し、E課題/checkerはv10のまま。旧実装はstatus参照だけを許可し書込み再開を拒否 |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、oxlint、Python AST、commit hooks | 成功。tscは既存TypeScript対象。新JSは実行/lint、Pythonは公開CLIと構文確認で検証 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `bae95ec`で760件、737成功・23skip・失敗0、exit0 |
| Standardsレビュー | `git diff eba6b83...bae95ec` | 指摘0件、baseline smellなし |
| Specレビュー | 同差分とv12確定設計 | 指摘0件。変更範囲、コード/表の対応、実LLM改善未検証の区別を確認 |
| 既存記録とsource pin | SHA-256照合、v11 status/監査履歴確認 | 旧1145ファイル不変、source pinと履歴hash一致。v11純粋性手順・条件付き参照・runtime維持 |

red→green、全体ログ、レビュー、保全記録は `tmp/mvp-v12-implementation/` に保存。全体検査後の変更は設計完了状態とこの検証記録のみ。実LLM再評価は明示依頼後に行い、静的検査・fixture成功から報告精度の改善を主張しない。配備・pushは未実施。旧未追跡runは今回のcommitへ一括追加していない。

## v11接続（2026-09-23）

v11時点のCLIは[v11契約](evaluations/mvp-mediator-evaluation-v11/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-evaluation-v11/design.md)に従い、スキルの純粋性段落へ各呼出し直後の入力比較と初回結果snapshotを示す例を置いた。snapshot/equalityは既存表現へ合わせ、比較不能は未確認として扱う。E課題と親checkerはv10を維持し、状態分類・根拠表・runtimeは変更しない。

本文の例は `node --test tests/mvp-purity-example.mjs` で直接実行する。正常例の成功と、初回入力変更を再呼出しで戻す不正例、再呼出し時の入力変更、非決定的な結果、返却object再利用を検出する。公開CLI検査は `bats tests/mvp-evaluation.bats`。S/Lへの比較順序の明示化と、実行者の行動改善は区別して次の実評価で確認する。実LLM再評価は別の明示依頼で開始する。

### v11接続の検証結果

比較起点 `0e21bbc`、実装 `0262bf2`、レビュー修正 `9d9b898` / `2875994`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 比較順序の具体例と検出感度 | `node --test tests/mvp-purity-example.mjs` | 1/1成功。本文の純粋性節を直接実行し、正常例と5つの不正例を確認。初回入力変更を復元前に検出、再呼出し時の入力変更、非決定性、初回結果だけの書換え、同じ返却object再利用を検出 |
| 新本文・契約の配布と旧版境界 | `bats tests/mvp-evaluation.bats` | 18/18成功。v11を固定し、E課題・checkerはv10を維持。旧実装のstatus参照と書込み再開拒否を確認 |
| 型・形式・構文 | `bunx tsc --noEmit`、skill `quick_validate.py`、oxlint、Python AST、commit hooks | 成功。tscは既存TypeScript対象。新しいJSは直接実行とlint、Pythonは公開CLIと構文確認で検証 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `2875994`で759件、736成功・23skip・失敗0、exit0。1回実行、実行中のコード変更なし |
| Standardsレビュー | `git diff 0e21bbc...HEAD` | 例の抽出対象が曖昧という指摘1件を修正し、再レビュー残件0 |
| Specレビュー | 同差分とv11確定設計 | 初回結果保持の独立した検出感度の指摘1件を修正し、再レビュー残件0 |
| 既存記録・凍結source | SHA-256照合、v10 runのstatus・監査履歴確認 | 既存1081ファイル不変。v10 E/checker・条件付き参照・runtimeを維持し、新しいsource pinも一致 |

red→greenと全体ログ・保全記録は `tmp/mvp-v11-implementation/` に保存した。全体検査後の変更は設計状態とこの検証記録のみ。実LLM評価・配備・pushは未実施。旧評価記録は今回のcommitへ一括追加していない。S/Lへの手順明示化や実行者の行動改善はfixture成功では証明せず、次の明示的な評価へ残す。

## v10接続（2026-09-23）

v10時点のCLIは[v10契約](evaluations/mvp-mediator-evaluation-v10/protocol.md)へ接続する。[確定設計](evaluations/mvp-mediator-checker/design.md)に従い、E課題の状態を明示的なデータに限定し、新版checkerで全入力stateの非破壊性と同入力結果の決定性を検査する。機能ケースは従来の52件を維持する。

親のE検査は `node docs/evaluations/mvp-mediator-evaluation-v10/check-device.mjs <model.mjs>` を使う。JSONのstatus、executed、completed、notRun、failuresを保存し、契約違反・モデル検査失敗・検査未成立を区別する。状態外の判断用可変データは親のコード監査でも確認する。旧checkerのhashは新版監査で拒否される。

スキル本文はv9のままで、B/S/L課題・共通テンプレート・runtime・採点・停止条件も維持する。新旧契約とcheckerをhash固定し、旧runはstatus参照だけを許可する。APIと検査条件が変わるため、旧版との単純な改善率比較は行わない。実LLM再評価は別の明示依頼で開始する。

専用検査は `bats tests/mvp-evaluation.bats`。この中でcheckerの公開コマンド入口を `node --test tests/mvp-checker.mjs` により検査し、通常／freeze、入力破壊、非決定性、返却object再利用、不正形式、エラー分類と旧52件のnegative controlを確認する。CLI fixtureは配布と証拠の版を検査し、実モデルを起動しない。

### v10接続の検証結果

比較起点 `e14efb8`、実装 `b0d8154`、検査中断・例外分類の修正 `bb6b133` / `6b03b02` / `951a56f`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 明示データ契約、入力非破壊性、決定性、失敗分類 | `node --test tests/mvp-checker.mjs` | 最終修正後7/7成功。通常／freezeで旧52件成功、negative controlは失敗。準備失敗・検査中断・表示不能なモデル例外も区別 |
| E配布・checker hash・旧版境界 | `bats tests/mvp-evaluation.bats` | 最終修正後17/17成功。旧checker hashを拒否し、旧runのstatus参照と再開拒否を確認 |
| 型・構文・形式 | `bunx tsc --noEmit`、Node公開入口、Python AST、oxlint、commit hooks | 成功。tscの対象は既存TypeScriptで、新JS/Pythonの型保証ではない |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | `6b03b02`で758件、735成功・23skip・失敗0、exit0。検査中の編集なし |
| 既存記録・凍結source | SHA-256照合、v9 runのstatusと監査履歴確認 | 既存990ファイル不変、source pin一致。v9スキル・runtime・旧評価を保存 |

Standardsレビューは指摘0件。Specレビューで見つかった検査中断時の集計とモデル例外の分類を修正し、最終再レビューの残件は0件。

全体検査は1回実行した。その後の `951a56f` は表示不能なモデル例外の分類と回帰検査・hashを修正し、専用Node検査7件・CLI検査17件・型／lintを再実行した。全体suiteを最終HEADで再実行したという主張はしない。検証ログと保全記録は `tmp/mvp-v10-implementation/` に保存した。実LLM再評価・配備・pushは未実施。過去の未追跡評価記録は今回のcommitへ一括追加していない。

## v9接続（2026-09-22）

v9時点のCLIは[v9契約](evaluations/mvp-mediator-evaluation-v9/protocol.md)へ接続する。状態表と根拠表の変更、受入条件、形式遵守と内容の正確さを分ける比較条件は同契約を参照する。新規runは新本文とv2〜v9契約を固定する。CLIの変更は版登録とhashのみ。実LLM評価は次の明示的なempirical-prompt-tuning依頼で行う。

### v9接続の検証結果

実装 `e7523fd`、比較起点 `10c19e6`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 状態の情報源の分離・観測時点ごとの根拠行 | Standards/Specレビュー、skill quick_validate | 形式検証成功。Standards指摘0件、Spec指摘0件。行動改善は未検証 |
| 新本文・v2〜v9固定と配布 | `bats tests/mvp-evaluation.bats` | v9未登録でred、接続後14/14成功 |
| 型確認 | `bunx tsc --noEmit` | 成功 |
| 全体回帰 | `bun run test` | e7523fdで755件、731成功・23skip・1失敗、exit1。失敗は起動PATHにwith-envがない既存human-validation検査 |
| 環境検査の再確認 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bats tests/human-validation.bats` | 1/1成功、exit0。テスト内容は変更していない |
| 既存記録・凍結source | SHA-256照合、v8 runのstatus参照 | 既存評価899ファイル不変、凍結hash一致。runtime・条件付き参照も不変、v8の停止状態を参照可能 |

全体検査は1回実行し、実行中のコード・テスト変更はない。失敗した1件は環境を補って個別再検証したため、全体の単一runがgreenだったとは扱わない。全体検査後の変更はこの案内・検証記録のみ。検証ログと保全記録は `tmp/mvp-v9-implementation/` に保存した。実LLM評価・配備は未実施。過去の未追跡評価記録は今回のcommitへ一括追加していない。

## v8接続（2026-09-22）

v8時点のCLIは[v8契約](evaluations/mvp-mediator-evaluation-v8/protocol.md)へ接続する。本文の変更・受入条件・比較上の制限は同契約を参照する。新規runは新本文とv2〜v8契約を固定する。CLIの変更は版登録とhashのみ。実LLM評価は次の明示的なempirical-prompt-tuning依頼で行う。

### v8接続の検証結果

実装 `aa183eb`、比較起点 `093bf81`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 検証主張とassertionの対応・状態区分・適用範囲 | Standards/Specレビュー、skill quick_validate | 形式検証成功。Standards指摘0件、Spec指摘0件。行動改善は未検証 |
| 新本文・v2〜v8固定と配布 | `bats tests/mvp-evaluation.bats` | v8未登録でred、接続後14/14成功 |
| 型確認 | `bunx tsc --noEmit` | 成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | aa183ebで755件、732成功・23skip・失敗0、exit0。検査中の編集なし |
| 既存記録・凍結source | SHA-256照合、v7 runのstatus参照 | 既存評価811ファイル不変、凍結hash一致。v7の停止状態を参照可能 |

全体ログと保全記録は `tmp/mvp-v8-implementation/` に保存した。全体検査後の変更はこの検証記録のみ。実LLM評価・配備は未実施。過去の未追跡評価記録は今回のcommitへ一括追加していない。

## v7接続（2026-09-22）

v7時点のCLIは[v7契約](evaluations/mvp-mediator-evaluation-v7/protocol.md)へ接続する。本文の変更と、要件緩和を品質改善として数えない比較条件は同契約を参照する。新規runは新本文とv2〜v7契約を固定する。CLIの変更は版登録とhashのみ。実LLM評価は次の明示的なempirical-prompt-tuning依頼で行う。

### v7接続の検証結果

実装 `71a1d5d`、レビュー修正 `9b48214`、比較起点 `2393b59`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 状態説明・根拠表への集約・適用範囲 | Standards/Specレビュー、skill quick_validate | 形式検証成功。Standards指摘0件。Specの達成欄作成指示1件を明確化し、再レビューで解消。行動改善は未検証 |
| 新本文・v2〜v7固定と配布 | `bats tests/mvp-evaluation.bats` | v7未登録でred、接続後14/14成功。レビュー修正後も `--filter 'freezes only'` で1/1成功 |
| 型確認 | `bunx tsc --noEmit` | 実装時・レビュー修正後とも成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 71a1d5dで755件、732成功・23skip・失敗0、exit0。検査中の編集なし |
| 既存記録・凍結source | SHA-256照合、v6 runのstatus参照 | 既存評価744ファイル不変、最終本文・契約とCLI固定hash一致。v6の停止状態を参照可能 |

全体検査後の9b48214は達成欄の作成指示1文と対応hashだけを変更し、対象CLI・型・形式検査を再実行した。未解消指摘はStandards 0件、Spec 0件。全体ログと保全記録は `tmp/mvp-v7-implementation/` に保存した。実LLM評価・配備は未実施。過去の未追跡評価記録は今回のcommitへ一括追加していない。

## v6接続（2026-09-22）

v6時点のCLIは[v6契約](evaluations/mvp-mediator-evaluation-v6/protocol.md)へ接続した。対象本文の変更内容と受入条件は同契約を参照する。

CLIの変更は新版の登録と本文hashだけ。新規runは新本文とv2〜v6契約を固定し、評価手順・採点・配布テンプレート・runtimeを維持する。公開CLI fixtureの成功は報告内容の意味的な正しさや行動改善の証明ではない。実LLM評価は別の明示的なempirical-prompt-tuning依頼で行う。

### v6接続の検証結果

実装 `717a529`、比較起点 `e326e5e`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 本文の作業順序・報告構成・適用範囲 | Standards/Specレビュー、skill quick_validate | 形式検証成功。Spec指摘0件。行動改善は未検証 |
| 新本文・v2〜v6固定と配布 | `bats tests/mvp-evaluation.bats` | v6未登録でred、接続後14/14成功 |
| 型確認 | `bunx tsc --noEmit` | 成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 717a529で755件、732成功・23skip・失敗0、exit0。検査中の編集なし |
| 既存記録・凍結source | SHA-256照合、v5 runのstatus参照 | 既存評価671ファイル不変、凍結hash一致。v5の再発停止状態を参照可能 |

Standardsレビューの指摘は、この文書と契約の手順説明の重複1件。契約への参照に整理した。全体検査後の変更はこの文書の説明と検証結果のみ。全体ログと保全記録は `tmp/mvp-v6-implementation/` に保存した。実LLM評価・配備は未実施。過去の未追跡評価記録は今回のcommitへ一括追加していない。

## v5接続（2026-09-22）

v5時点のCLIは[v5契約](evaluations/mvp-mediator-evaluation-v5/protocol.md)へ接続した。対象本文の検証メモ指示を、最終編集後にケースと操作列、保持状態と説明、検証主張とassertion・実行結果を照合する完了手順へ組み替えた。新規runは新本文とv2〜v5契約のpath/hashを固定する。課題・配布テンプレート・採点・runtime・停止条件は維持する。

既存の公開CLI fixtureでv5未登録のredを確認し、新版の固定・配布を検証する。過去runは保存し、新版での再開は認めない。実LLM評価は次の明示的なempirical-prompt-tuning依頼で実施する。fixtureの成功は行動改善の証明ではない。

### v5接続の検証結果

実装 `eae71cf`、レビュー修正 `31fd56f`。比較起点は `a2150ee`。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 最終成果物との照合 | 本文差分、Standards/Specレビュー、skill quick_validate | 3照合と修正後の更新を明記。提案のみは未実行とする。形式検証成功。行動改善は未検証 |
| 新本文・v2〜v5固定と配布 | `bats tests/mvp-evaluation.bats` | v5未登録でred、接続後14/14成功。レビュー修正後も `--filter 'freezes only'` で1/1成功 |
| 型確認 | `bunx tsc --noEmit` | 実装時・レビュー修正後とも成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | eae71cfの内容で755件、732成功・23skip・失敗0、exit0。実行中のコード・テスト変更なし |
| 既存記録・凍結source | SHA-256照合 | 既存評価525ファイル不変。最終版本文・v5契約とCLI固定hash一致 |

全体検査後の31fd56fは提案の完了条件と対応hashだけを変更し、影響する公開CLI・型・形式検査を再実行した。全体ログは `tmp/mvp-v5-implementation/full-test.log`。実LLM評価と配備は未実施。既存の未追跡評価記録・v2契約は保持し、今回のcommitへ一括追加していない。

#### Standards

独立レビューで規約違反0件、smell指摘0件。task worktree、ローカルskillの配置、既存定義を参照する完了手順、最小の版更新を確認。

#### Spec

初回1件: 提案のみでも末尾の完了条件が検査成功を要求し得た。31fd56fで提案と実装の完了条件を分け、同じレビュー担当が解消を確認。未解消0件、新たなscope creepなし。

## v4接続（2026-09-22、履歴）

v4時点のCLIは[v4契約](evaluations/mvp-mediator-evaluation-v4/protocol.md)へ接続する。対象本文の状態説明を、保持状態・目的/所有者・区分・本実装の取得元の欄へ具体化した。新規runは新本文とv2/v3/v4のpath/hashを固定する。配布テンプレート・課題・採点・停止条件はv3を維持し、実行者には新本文として変更を渡す。

公開CLIのinit/prepare fixtureで、v4登録前の失敗と、新版の固定・配布後の成功を確認する。旧runの記録は保持し、新版による再開は認めない。今回の実装では実LLM評価を開始しない。本文の適用効果は次のempirical評価で確認する。

この変更のcommitには、新本文の前提となる既存の未コミット本文改善も保持して含める。実装開始時の本文からの変更は状態説明段落のみ。v2契約と旧runは既存ローカル依存として保持し、一括でcommitしない。

### v4接続の検証結果

実装commit: `1098fa0`。`3e6ad30...1098fa0`をStandards／Specの独立した2軸でレビューした。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 状態説明の具体化 | 実装開始時の固定本文との差分と2軸レビュー | 状態説明段落だけを変更。保持フィールドの対応と未確認の取得元を明示。適用効果の実測は未実施 |
| 新本文・契約の固定と配布 | `bats tests/mvp-evaluation.bats` | 14/14成功。v4未登録でredを確認後、startの契約hashと配布本文hash・記入欄を確認してgreen |
| 既存ゲート・旧記録の保持 | 同じ14件、旧v3 runのprepare/status、437ファイルのSHA-256照合 | 隔離・承認・監査・再発停止・上限を維持。旧runの変更はimplementation changedで拒否、status成功、旧ファイルすべて不変 |
| 型・構文 | `bunx tsc --noEmit`、Python AST parse | 成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 755件、732成功・23skip・失敗0、exit0。実行中にコード・テスト変更なし |

全体ログと保存照合の作業記録は `tmp/mvp-v4-implementation/`。opt-inの実モデル・プラットフォーム検査は既存のskip条件に従う。今回の新しい実LLM評価は0件。

#### Standards

規約違反0件、設計スメル0件。状態説明を一箇所へ集約し、既存の意味を保持したこと、固定hashとCLIの一致を確認。

#### Spec

未達・scope creep・誤実装0件。新本文/v2/v3/v4固定、Bのモデル不要条件、課題・採点・停止条件の維持を確認。既存未コミット本文改善と今回の差分を区別してレビューした。

## v3接続（2026-09-22）

v3接続時のCLIは[v3差分契約](evaluations/mvp-mediator-evaluation-v3/protocol.md)へ接続する。新規runの`start.json.sources`には基礎v2と差分v3の両path/hashを保存し、配布promptへv3のケース別実行出力要件を挿入する。Bにはその条件が適用されず、提案確認のままである。以下のv2初期実装・診断の記録は経緯として保持する。

親は監査確定時に残る未解決条件だけを`issues`・`failure_patterns`へ入れる。復帰済みの任意の探索エラーは、当該attempt内の`environment.md`等に失敗・代替手段のcall/resultと復帰根拠を記録し、監査の`references`と`reason`から参照する。CLIは参照先をhash固定し、次回操作でも照合する。新しい採点エンジンやエラーの自動分類は導入しない。

たとえば、必要な探索結果をrgで取得したfind不在は環境記録へ残し、未解決条件がなければ`issues: []`・`failure_patterns: []`とする。同じ復帰が2実行で発生しても停止せず、他のclear条件を満たせばLの投入判定を妨げない。禁止入力混入・承認境界違反や必須手順の省略は復帰済みへ分類しない。

監査JSONの`references`へ追加する例:

```json
{ "path": "environment.md", "locator": "失敗・代替実行のevent IDと復帰根拠" }
```

既存runは再開・再採点しない。旧runの実装hashは新CLIと一致しないため変更操作が拒否され、`status`で保存状態だけを確認できる。契約v3本文の「接続前」は契約固定時点の状態であり、接続状況は本節を参照する。

検証は`bats tests/mvp-evaluation.bats`の公開CLI fixtureで行う。v2/v3固定・配布要件、復帰証拠を残した3組clearとL投入、未解決失敗の再発停止、既存の隔離・監査・証拠・上限ゲートを対象とする。実LLM評価は開始していない。

### v3接続の検証結果

実装commit: `a314d8c`。`b9449a0...a314d8c`をStandards／Specの2軸でレビューし、未解消指摘は各0件。Bへの条件付き指示に関する初回指摘は、v3の適用条件と全文を再照合して撤回された。

- `bats tests/mvp-evaluation.bats`: 14/14成功。配布・契約固定の追加検査は修正前にv3未登録で失敗し、接続後に成功した。
- `./node_modules/.bin/tsc --noEmit`: 成功。変更Pythonの構文検査も成功。
- `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test`: 755件、732成功・23skip・失敗0、終了コード0。`with-env`はこのcheckoutの`nix build .#with-env --no-link --print-out-paths`で取得。全体実行中にコード・テストは変更していない。
- 対象本文・契約・既存評価・prototype・監査補足を含む既存352ファイルはhash不変。追加LLM評価は0件。

## Contract

目的は、固定した評価契約v2を、実証済みの隔離起動へ接続すること。本文・既存評価・prototypeは変更しない。本評価の開始は別の明示依頼で行う。

受入条件:

- E/B/Sを3組、条件成立時にLを1回。各実行へ担当課題・本文・条件付き参照・明示した実行指示だけを渡す。
- 永続する書込みは、その実行の `memo.md` と、B以外の `model.mjs` に限定する。
- 配布内容・hash、実行条件、tool call/resultを含むstdout、stderr、終了状態、成果物hashを親側へ保存する。
- 親が証拠を参照して入力監査と採点を確定するまで、次の実行を拒否する。監査は該当証拠のhashへ結び付ける。
- 入力invalid/unknownだけを明示置換でき、最大2件。機能・遵守failを置換理由にしない。同じ失敗パターンが独立した2実行で再発すれば停止する。全dispatchは12件以内、3組を超えて追加しない。
- Lは3組clearと親による未使用確認が必要。canonical metadataは取得できなければN/Aのまま保存する。
- 合成workerを使い、公開CLIを通して隔離・監査・停止を検証する。本評価もモデル通信もテストでは開始しない。

非目標は汎用agent基盤、採点・意味的入力監査の全自動化、全runtimeの別起動経路の禁止、既存成果物の再採点。

関連する一次資料は `docs/evaluations/mvp-mediator-evaluation-v2/protocol.md` と `docs/evaluations/prototype-input-isolation/llm-run/`。実装ではprototypeをimportしない。既存のmodel gatewayを再利用し、実行入口自身が評価用の起動前条件を検査する。

判断済みのtradeoff: 契約が許す組内並列は使わず直列実行する。監査の意味判断・失敗パターンの分類・採点は親が行う。ホストの同一ユーザーによる悪意あるstate改変は対象外だが、二重CLI起動と証拠の変更は拒否する。

## CLIと状態の境界

`init` で実行条件と入力を固定し、`prepare` で次の課題を隔離用に抽出する。親が `approve` で配布内容を確認した後にだけ `dispatch` できる。完了後は `audit` で入力有効性・6項目・C1〜C4・失敗パターン・証拠参照を確定するまで次の `prepare` を拒否する。`status` は状態と停止理由を読むだけで、モデルを起動しない。

入力不良の置換には `prepare --replace` を使う。同じ課題slotに新しい実行IDを割り当て、元実行の証拠を残す。監査レコードは上書きしない。Lの配布前には、親が履歴を確認した証拠を渡す。

通常runと合成fixture runは初期化時に区別し、途中で切り替えない。fixture runはgatewayを起動せず、Codexのnative sandboxを経由して合成workerを隔離内で動かす。通常runは明示した `dispatch` だけがモデルを起動する。

## 操作

入口は `python3 scripts/mvp-evaluation.py`。以下は操作例であり、この実装作業では通常runを作成・dispatchしない。

初期化には次のJSONを `conditions.json` として用意する。`instructions` だけが実行者への追加指示となる。過去評価や正解を含めない。`effective_context` には実効system/developer/AGENTS・Ponytail等のログ参照と、見えない部分のunknownを記録する。`runtime_notes` にはツールや隔離環境の条件を記録する。親側の2項目は実行者へ渡さない。

```json
{
  "instructions": "今回の実行者へ適用するAGENTS等の指示全文",
  "effective_context": "実効指示のログ参照。モデル基本指示の非公開部分はunknown",
  "runtime_notes": "Linux/Nix、専用bubblewrap境界、評価用ツールセット"
}
```

```sh
python3 scripts/mvp-evaluation.py init /absolute/new-run --conditions conditions.json
python3 scripts/mvp-evaluation.py prepare /absolute/new-run
python3 scripts/mvp-evaluation.py status /absolute/new-run
```

runは存在しないディレクトリを指定する。`init` は入力元・実装・ツール・Git情報を固定する。`prepare` は担当節を抽出し、Sのheld-out表記と投入時期の一文だけを除く。`attempts/01/inputs/` と `prompt.txt` の配布内容を親が確認する。承認JSONは、statusにある最新attemptの `bundle_sha256` と具体的な確認理由を持つ。

```json
{
  "bundle_sha256": "statusに表示されたhash",
  "reason": "担当節・6基準・指定版・追加指示を確認。他課題と親checkerは配布に含まれない"
}
```

```sh
python3 scripts/mvp-evaluation.py approve /absolute/new-run --record approval.json
python3 scripts/mvp-evaluation.py dispatch /absolute/new-run
```

dispatchは同期実行し、run単位のlockを終了まで保持する。stdout/stderrは逐次保存する。900秒でtimeoutし、証拠を残して監査待ちにする。再dispatchは禁止する。通常runだけが既存のChatGPT gatewayを起動し、空のHOMEで新規Codex `gpt-5.6-terra/high` を動かす。認証情報はgatewayから隔離側へ渡さない。

永続成果物は `artifacts/memo.md`、E/S/Lのみ `artifacts/model.mjs`。親が用意した既存ファイルへ直接上書きする。ディレクトリへの追加・削除・renameは許可しないため、実行者はatomic renameを使う編集方式を避ける。内部のHOMEと/tmpは使い捨て領域で、返却対象ではない。Codexの保護処理が参照する `.git`・`.codex`・`.agents` の空ディレクトリをreadonly側に事前作成し、内側sandboxがmount先を作成できず停止することを防ぐ。実行コードとツールのNix依存closureも隔離内から読めるが、repo・過去成果物・checkerはmountしない。

## 親の監査

親は `stdout.jsonl` の実読取りと返却内容、実行者の報告、成果物を照合する。通常のexecイベントに加え、子の終了後に使い捨てHOMEのnative sessionからtool call/resultを `runtime.tool_record` として同じstdoutへ出力する。各レコードはnative sessionの相対path・行番号・原レコードを持つ。system本文・推論記録は転記しない。`--ephemeral` は使わないが、セッション自体は隔離内だけに保存され終了時に失われる。強制終了や破損で必要なcall/resultが取れなければ親はunknownを維持する。契約の独立検査も親側で行い、そのログを当該attemptの `parent-checks/` 以下へ保存する。生成コードを無条件にホストで実行せず、別の隔離境界で検査する。親の検査結果は実行者の実績へ加えない。

監査JSONの例（数値は例示であり、実採点ではない）:

```json
{
  "evidence_sha256": "statusに表示された最新attemptの証拠hash",
  "input": "valid",
  "scores": [1, 1, 1, 1, 1, 1],
  "compliance": ["pass", "pass", "pass", "pass"],
  "issues": [],
  "failure_patterns": [],
  "reason": "各基準とC1〜C4の根拠、および自己報告との差を参照記録に記載",
  "parent_checks": "parent-checks/checks.json",
  "references": [
    { "path": "stdout.jsonl", "locator": "入力読取りと実行結果のevent ID" },
    { "path": "parent-checks/review.md", "locator": "採点根拠と親検査の節" }
  ],
  "decision_retry": "自己報告の回数・理由・出典。未報告ならunknown",
  "mechanical_retry": "親がログから集計した回数と対応イベント"
}
```

```sh
python3 scripts/mvp-evaluation.py audit /absolute/new-run --record audit.json
```

入力判定は `valid/invalid/unknown`、6項目は `0/0.5/1`、C1〜C4は `pass/fail/unknown`。clearでなければ再発照合用の `failure_patterns` を必須とする。同じ原因には同じ名称を使い、入力不良と機能・遵守失敗を区別する。CLIは意味判断を代行せず、証拠の存在・hash・値域と停止条件を検査する。unknown確定後の置換と、監査レコード自体が未提出の状態は異なる。

監査・証拠・返却成果物は上書きしない。既存ログ・成果物に加え、全attemptのbundle・入力・promptの変更があれば次操作を拒否する。入力invalid/unknownのときだけ `prepare --replace` を使う。3組clear後のLには `prepare --unused-evidence unused.json` を使い、JSONに `{"unused":true,"reason":"履歴照合の参照と理由"}` を記す。

入力validの監査には `parent_checks` を必須とする。E/S/Lは `self_check`、Eはさらに `fixed_checker` を含むJSONを用意する。各項目は `status`（executed/not-run）、`reason`、`artifact_sha256`（証拠のmodel.mjs hash）を持ち、executedなら `command`・`expected`・`exit_code`・`output` も保存する。固定checkerには `checker_sha256` を付け、契約の値と一致させる。未実行・失敗の検査ではclearを拒否する。Bは `proposal_review` に `status: "not-run"` と提案確認の `reason` を記し、未実行アプリ検査を成功と扱わない。これらの記録もhashで固定する。検査の意味的な十分性は親が判断する。

失敗再発・置換上限・3組終了・L終了後は `status` の `stop` に理由を残す。4組目や上限を超えた追加試行は作らない。モデル内部の複数HTTP応答は1セッションに含め、dispatch数とは分ける。起動失敗も予約したattemptを消費する。

## 検証と限界

```sh
bats tests/mvp-evaluation.bats
```

テストは `init --fixture` で固定し、同じmount境界の合成workerでCLIを検証する。fixture runをliveへ変更できない。モデル評価は開始しない。実LLMとgatewayの接続実証は既存prototypeを参照し、今回変更した書込み境界はfixtureで確認する。

親による監査が意味的に正しいか、指定されたログ位置が採点を実際に裏付けるかは親の責務。ホストの同一ユーザーは別の起動経路を使えるため、全runtime共通の強制とは呼ばない。親プロセスが強制終了した場合はrunningのままfail-closedとなる。自動再開・状態書換えによる救済はせず、残った証拠を調査する。

契約・対象本文の未コミット状態を勝手に取り込まないため、このcommitは既存のローカル評価文書を依存として参照する。別checkoutへ移す際は、固定hashに一致する契約・本文が揃っている必要がある。

## Verification Matrix（2026-09-21）

| AC | 検査 | 結果・限界 |
| --- | --- | --- |
| 課題別入力・承認・変更拒否 | `bats tests/mvp-evaluation.bats` | 指定課題抽出、承認前拒否、入力／承認／証拠変更拒否が成功 |
| 隔離・指定成果物 | 同上の実bubblewrap fixture | 入力外読取り、入力書込み、未指定ファイル作成を拒否。指定成果物への書込み成功 |
| 監査・停止・上限 | 同上 | 未監査停止、明示置換、2件上限、再発停止、3組終了、L条件、12件経路、13件目拒否が成功 |
| 親検査の必須化・metadata | 同上 | 親検査なしのclear拒否、固定checker hash、N/A記録を確認 |
| 型・構文 | `bunx tsc --noEmit`、Python AST parseとCLI実行 | 成功 |
| 既存成果物の保持 | 作業開始時255ファイルのSHA-256と終了時を照合 | 本文・既存評価・prototypeすべて不変 |
| 本評価を開始しない | テストは全てfixture mode | 新しい実LLM評価は0件。変更した実行入口での実LLM統合は未実行 |

最終コードを固定した専用テストは **11/11成功**。全体の `bun run test` は750件を実行し、723成功・23skip・4失敗（exit 1）だった。うち新規テスト3件は全体実行中にレビュー修正を並行したことで旧fixtureと新実装が混在したためで、固定後の11件で再確認した。残る既存 `human-validation.bats` 1件は起動シェルに `with-env` がなかったため。repoの `nix build .#with-env --no-link --print-out-paths` で提供するバイナリをPATHに加え、同ファイル1/1成功を確認した。全体の単一runがgreenだったとは扱わない。opt-inの実モデル／プラットフォーム検査は実行していない。

## Standards

規約違反・追加のsmell指摘なし。task worktree、既存prototype保持、専用CLIへの限定、fixtureからのモデル起動禁止を確認。固定hashの既存ローカル文書に依存する点は前記の配布上の制約である。

## Spec

初回指摘2件を修正し、仕様レビュー担当が解消を確認した。

- P1: 親の独立検査記録なしでもclear可能だった。課題別の構造化した親検査記録を必須化し、成果物・固定checkerのhash、実行状態、コマンド、期待値、終了値、出力へ結び付けた。
- P2: canonical metadataの取得不能をnullで記録していた。literal `N/A` とsource・reasonへ修正した。

未解消指摘はStandards 0件、Spec 0件。レビュー比較の起点は `94e283a346eaf12edece45bb7a5ca94295340faa`。

## Runtime障害の診断・修正（2026-09-21、b782437以後）

`run-20260921-02` の失敗とレビューP1の2件を対象にした。本文・評価契約・既存評価run・prototypeは変更していない。本評価は再開せず、`tmp/debug-mvp-runtime/live` に実LLM実行者1回の診断記録を保存した。

根因と修正:

- 外側readonly artifactsと、内側Codex sandboxの保護用mount先作成が衝突していた。`python3 tmp/debug-mvp-runtime/repro.py` で `bwrap: Can't mkdir /artifacts/.codex: Read-only file system` を再現。空の `.git`・`.codex`・`.agents` をreadonly側へ事前作成した比較だけで、同じ読取り・更新コマンドが成功した。ディレクトリ全体へのwrite権限は追加していない。実LLMの `apply_patch` も成功し、別の編集方式障害という仮説は今回の更新経路では棄却した。
- 通常の `codex exec --json` は一部のtool失敗を出さない。使い捨てHOMEのnative sessionからcall/resultを追加保存する。診断で `touch /artifacts/unlisted` の失敗がcompact側に欠け、native側のcall/result（session行50/52）には存在することを照合した。
- 過去attemptの入力は `verify_history` の照合対象外だった。全attemptへ `verify_bundle` を適用し、本文・prompt・bundleの改変を次のprepareより前に拒否する。

回帰検査は修正前の失敗を確認してから追加した。fixtureもCodex native sandboxを経由するようにし、モデル通信なしでmount衝突と指定ファイル更新を検査する。native tool記録の検査は `tests/mvp-evaluation-records.py` をBatsから実行する。

| 確認 | 結果 |
| --- | --- |
| `bats tests/mvp-evaluation.bats` | 13/13成功。履歴検査は本文・prompt・bundleの各変更を拒否 |
| 実LLM診断 | gpt-5.6-terra/high、新規1セッション。入力全文読取り、指定2成果物更新、self-check4ケース成功 |
| 親の隔離再実行 | self-check4ケース成功、固定checker52/52成功 |
| 入力と証拠 | native22レコード＝11call/result対を照合。入力valid、診断用Eの6項目とC1〜C4を親確認 |
| 起動ゲート | 診断実行の未監査時prepareをexit1で拒否。監査後も後続dispatchは実施しない |
| 書込み境界 | 実LLMの `touch /artifacts/unlisted` はreadonlyエラー。指定ファイルの既存更新は成功 |
| 読取り境界 | fixtureは実在するhost側bundleの読取りを拒否。実LLMのcanaryは不存在pathのENOENTだけで、単独の隔離証明とは扱わない |

診断の証拠: `tmp/debug-mvp-runtime/live/attempts/01/` の `evidence.json`、`stdout.jsonl`、`audit.json`、`parent-checks/`。model.mjs SHA-256は `9cf3dd6f66a9408717cd448f3ce7ba382093fbf5119c16e66eacc5bb181ad355`、stdout SHA-256は `d4ab946b7645f49a6e131e2e2f02289e42c54107db9954c9caa6b2a626f4c6b1`。native記録の件数は独自集計であり、canonical tool_uses/duration_msはN/Aを維持する。診断1回から評価の収束は主張しない。

限界: native sessionの回収は子終了後であり、強制終了時の未回収区間はunknown。fixtureはCodex native sandboxを通すが、実モデルの全tool選択を網羅しない。診断用ファイルは明示したdebugディレクトリに保持し、既存prototypeを削除・編集しない。
