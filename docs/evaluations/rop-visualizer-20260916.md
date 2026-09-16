# rop-visualizer empirical evaluation — 2026-09-16

対象: `local-skills/rop-visualizer/`。開始時 HEAD: `408ca61d4769ddb89147e56dc93d94c55e8b0cc3`。

## 評価契約

過去の評価を上書きせず、現行の `flowchart TB` 版を新規実行者で評価する。既存の凍結 fixture を使用し、旧 prompt の表示方式だけをフローチャートに合わせる。各シナリオの既存6項目に生成・検証契約を1項目追加し、実行前に固定した。critical は各ケースの第1項目のみ。○=1、partial=0.5、×=0 として7項目の達成率を計算する。成功は critical の完全充足で判定する。

実行者: `gpt-5.6-terra` / `high`、履歴なしの新規サブエージェント。ブラウザーの競合を避け、同じ worktree のブラウザー使用を直列化する。過去の評価記録・他の実行者の出力を渡さない。

`tool_uses` / `duration_ms` の native usage metadata が返らない場合は未取得とし、壁時計や自己申告で代用しない。その round を strict convergence に数えない。

成果物: task worktree の `tmp/empirical-rop-20260916/`。固定した `evals.json`、対象ファイルの `baseline-sha256.json`、各回のモデル・HTML・自己報告・検証証跡を保持する。

## Iteration 0

description と本文の対象言語（TypeScript Effect / Rust Result）、既存実装を説明する範囲、対話式 HTML 出力に不一致なし。変更なし。依存する型・エラー変換・未知境界は参照文書に説明されている。

## 固定チェックリスト

### 0: effect-checkout.ts.fixture

`inputs/effect-checkout.ts` の `checkout` を入口に、呼ばれる実装を読んで、レビュー用の単一 `railway.html` を作ってください。Effect v3 の成功・失敗チャネルを Mermaid のフローチャート として説明し、ステップ選択、詳細の折りたたみ、実行トレースを装わない実現可能な 1 経路の強調を操作できるようにしてください。

1. [critical] [意味] `checkout` から `validate → reserve → catchTag(OutOfStock) → charge → tap(auditReceipt) → map(renderConfirmation) → mapError` の順序を、コードに対応するノードと有向エッジで表す。catchTag の回復ハンドラは `OutOfStock` 失敗に一致した場合だけ実行し、`Inventory` は reserve の Requirement R を示す依存関係として詳細に示すが、失敗エッジとして描かない。
2. [意味] `ValidationError` は reserve 以後を通らず、`CatalogUnavailable` は `catchTag` に一致せず charge・audit・render を迂回し、`PaymentDeclined` と `AuditUnavailable` はそれぞれ後続を迂回する失敗経路を表す。
3. [意味] `OutOfStock` だけが backorder の成功値へ回復して charge に進み、`mapError` は残った失敗を `CheckoutFailed` に変換するだけで成功へ回復しないことを表す。
4. [共通HTML] クリックまたはキーボード操作で各ステップを選択でき、選択中ステップに対応するコード上の意味・成功出力・失敗出力を表示する。
5. [共通HTML] 各ステップの補足を個別に開閉でき、最初は概要だけでグラフの全体経路を読める。
6. [共通HTML] 利用者が選ぶ 1 つの実現可能な経路だけを強調し、その表示を「実行結果・実行トレース」と称さない。各グラフのノード意味とエッジには対応するソース抜粋を添え、説明文だけで済ませない。
7. [実行契約] bundled renderer の HTML と flow.json/.mmd を残し、デスクトップ・狭幅・オフラインで操作と図形を検証する。Effect は syntax helper を試し evidence と status、失敗時の limitations を保存する。

### 1: rust-checkout.rs.fixture

`inputs/rust-checkout.rs` の `checkout` を入口に、必要なヘルパーを追って、レビュー用の単一 `railway.html` を作ってください。Rust `Result` の `?`、`From`、`or_else`、`map_err` を Mermaid フローチャート で正確に説明し、ステップ選択、詳細の折りたたみ、実行トレースを装わない実現可能な 1 経路の強調を操作できるようにしてください。

1. [critical] [意味] `checkout → load_price → parse_sku → catalog_price` の入れ子と、`catalog_price` の `CatalogError` が `From<CatalogError> for CheckoutError` により `load_price` の `?` で変換され、外側の `map_err(ApiError::from)` に至る関係を、実コードに対応するノードと有向エッジで表す。
2. [意味] `parse_sku` の `?` は `load_price` から早期 return し、`load_price(...).map_err(...)?` の失敗は reserve 以後を実行しないことを表す。
3. [意味] `or_else` は `InventoryUnavailable` のときだけ `reserve_backorder` を呼び、他の reserve 失敗は `Err(other)` のまま通過し、`reserve_backorder` 自身の `BackorderRejected` も失敗として残ることを表す。
4. [意味] 最後の `map_err(ApiError::from)` は `Err(CheckoutError)` を `Err(ApiError)` に写すだけで、成功値へ回復しないことを表す。
5. [共通HTML] クリックまたはキーボード操作で各ステップを選択でき、選択中ステップに対応するコード上の意味・成功出力・失敗出力を表示する。
6. [共通HTML] 各ステップの補足を個別に開閉でき、利用者が選ぶ 1 つの実現可能な経路だけを強調し、それを実行結果・実行トレースと称さない。各グラフのノード意味とエッジには対応するソース抜粋を添え、説明文だけで済ませない。
7. [実行契約] bundled renderer の HTML と flow.json/.mmd を残し、デスクトップ・狭幅・オフラインで操作と図形を検証する。Effect は syntax helper を試し evidence と status、失敗時の limitations を保存する。

### 2: holdout-local-scope.rs.fixture

`inputs/holdout-local-scope.rs` の `charge_invoice` を入口に、読める範囲だけを使ってレビュー用の単一 `railway.html` を作ってください。Mermaid フローチャート で局所的な `?` と `or_else` のスコープを示し、ステップ選択、詳細の折りたたみ、実行トレースを装わない実現可能な 1 経路の強調を操作できるようにしてください。`crate::gateway::quote_tax` の実装は与えられていません。

1. [critical] [意味] `normalize_country(country)?` の失敗は `tax_rate` から早期 return し、`quote_tax(...).or_else(...)` の回復は `tax_rate` の内部だけで、外側の `charge_invoice` の `ChargeDeclined` を捕捉しないことを、コードに対応するノードと有向エッジで表す。
2. [意味] `TaxServiceDown` だけが局所的に `Ok(0)` へ回復し、他の `quote_tax` エラーは `Err(other)` のまま `charge_invoice` の `?` を通じて返ることを表す。
3. [意味] 利用不能な `crate::gateway::quote_tax` は「未知の外部呼出し」と明記し、未提示の内部ノード・回復・失敗種類を捏造しない。
4. [共通HTML] クリックまたはキーボード操作で各ステップを選択でき、選択中ステップに対応するコード上の意味・成功出力・失敗出力を表示する。
5. [共通HTML] 各ステップの補足を個別に開閉でき、利用者が選ぶ 1 つの実現可能な経路だけを強調し、それを実行結果・実行トレースと称さない。
6. [共通HTML] 各グラフのノード意味とエッジには対応するソース抜粋を添え、説明文だけで済ませない。
7. [実行契約] bundled renderer の HTML と flow.json/.mmd を残し、デスクトップ・狭幅・オフラインで操作と図形を検証する。Effect は syntax helper を試し evidence と status、失敗時の limitations を保存する。

## Iteration 1

### Changes

初回実行。対象 skill の変更なし。Pattern applied: (new)。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| Effect | × | 85.7% (6/7) | 未取得 | 未取得 | 0（自己申告） | Planning |
| Rust | ○ | 100% (7/7) | 未取得 | 未取得 | 2事象（回数未申告） | Execution（検証手順のみ） |

### Structured reflection

- Effect: **[critical] 項目1が partial**。通常成功が「在庫切れを処理」へ流れ、条件一致時だけ handler が実行されることを図だけで表せていない。項目3も partial。
  - Issue: 通常成功の named path が error-category の `OUT_OF_STOCK_SCOPE` と `MAP_ERROR` を通る。説明文は pass-through を区別するが、図の処理ラベルは handler / error transform の実行に読める。
  - Cause: pipeline に演算子が存在することと、その callback が実行されることの区別がモデル化の規則として明示されていなかった。
  - General Fix Rule: action node は callback の実行条件に合わせ、pass-through は対応する action node を迂回して次の処理へ接続する。
- 親が図を確認して指摘し、実行者が自己報告の項目1・3を○から partial に修正した。成果物は変更していない。独立した初回自己申告と、親からの指摘後の採点を区別する。実行者の Trace は all OK のままだが、親はノード抽象化の選択を Planning の弱点と分類する。
- Effect の manifest 不在は入力条件。依頼で指定した v3 を前提に limitation を残したため失敗にしない。file URL 拒否は環境制約であり、HTML を setContent してネットワーク遮断下で検証した。いずれも skill 修正対象に混ぜない。

Rust は親のソース・モデル照合でも7項目を満たした。13 nodes / 15 edges / 5 paths。file URL 拒否と Playwright Node context から DOM を参照した失敗は検証側の環境・実行ミスで、意味モデルの誤りではない。Effect は10 nodes / 14 edges / 6 paths。両方とも1440px・390pxの図形検査とオフライン操作検査が成功した。

### Discretionary fill-ins

- Effect: handler scope を成功時に通る別ノードとして表現した。mapError に成功・失敗の両入力を合流させた。

### Ledger updates

- Added: **pipeline presence mistaken for callback execution**
  - Example: 成功経路が「失敗を変換」ノードへ接続される。
  - General Fix Rule: ノードを callback の実行条件で定義し、pass-through と分離する。
  - Seen in: iter 1 Effect。

### Next fix

固定チェックリストの Effect 項目1（handler は一致失敗時のみ）と項目3（mapError は残余失敗だけを変換）を満たすため、モデル化手順に callback execution / pass-through の区別を1段落追加する。実行者も同じ対応関係を自己報告で確認した。既存 ledger に同じ pattern はない。

Convergence: 新規曖昧点あり、0 clear rounds。native metrics 未取得のため strict convergence 対象外。

## Iteration 2

### Changes

`SKILL.md` のモデル化手順へ、callback の実行と pass-through を分離する1段落を追加。Pattern applied: **pipeline presence mistaken for callback execution**。renderer や評価入力は変更していない。

### Execution results

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| Effect | ○ | 100% (7/7) | 未取得 | 未取得 | 2事象（回数未申告） | Execution（検証手順のみ） |
| Rust | ○ | 100% (7/7) | 未取得 | 未取得 | 0 | — |

### Structured reflection

- Effect: 成功経路は `CATCH_BYPASS`（破線の合成ノード）を通り、回復 callback へ入らない。`MAP_ERROR` は失敗入力と失敗終端だけに接続され、通常成功は `RENDER → SUCCESS` へ流れる。親のソース・エッジ照合と画像確認でも、初回の問題は再現しない。
- Rust: 価格取得の `?` と最後の `map_err` が別の失敗変換として描かれ、通常成功はどちらの変換 callback も迂回する。限定回復と失敗継続もソースと一致する。
- Effect の未提供サービス実装・manifest は初回と同じ入力境界であり、新しい指示の曖昧点ではない。
- Effect の補助検証で相対 root による containment エラーがあり、絶対 root で再実行した。また、出力削除を含むコマンドがポリシー拒否されたため、削除せず新規ディレクトリへ保存して完了した。いずれも評価者の実行手順の問題として記録し、skill の意味規則へ混ぜない。

### Discretionary fill-ins

- Effect は正常時の catchTag pass-through を合成 bypass ノードとして残した。誤った handler 実行とは区別されている。
- Rust は load_price 呼出しとその内部を別ノードにし、6本の named path を選んだ。

### Ledger updates

- 初回 pattern の再発なし。今回の対象 skill に新規の instruction ambiguity は確認されなかった。

### Next fix

追加の文言変更なし。新規実行者による同条件の反復と hold-out が次の評価になる。

Convergence: 修正後の新規 instruction ambiguity なしは1 roundのみ。Effect は +14.3 points で改善しており、飽和判定ではない。native metrics も未取得なので strict convergence は未確認。

## 検証・終了条件

- 初期の renderer contract 8テスト、関連 Bats 3件は成功。
- 初回・再評価の4 HTML すべてで、1440px/390px の図形・オフライン操作検証が成功。文字重なり、線と文字の衝突、無関係なノード横断、端点不一致、本文横あふれ、JavaScript error は0件。デスクトップでは図全体が横スクロールなしで表示され、狭幅は図だけが横スクロールする。
- 初回: Effect 10 nodes / 14 edges / 6 paths、Rust 13 / 15 / 5。再評価: Effect 10 / 13 / 6、Rust 14 / 17 / 6。これは成果物の大きさであり、tool_uses の代用ではない。
- 初回の自己報告を無批判に採用せず、親が全モデルのエッジとソースを照合し、デスクトップ画像および再評価版の狭幅画像を確認した。
- 第3反復用の新規 spawn は `agent thread limit reached` で失敗した。4人の既存実行者を再利用すると blank-slate 条件を満たさない。追加反復・hold-out は未実施として **resource cutoff** で終了する。
- qualitative plateau も quantitative convergence も確定しない。一般的な成功率や人間の理解時間の改善は推定しない。再開時は新しい runtime/session で新規実行者を使い、固定したチェックリストと修正版の同一性を保って反復・hold-out を行う。
- 変更は task worktree 内だけに保持し、live source への配備は行っていない。

最終書式確認は repo の固定依存を `bun install --frozen-lockfile` で展開したうえで oxfmt を使用。system oxfmt の初回実行は依存未展開で設定を読めず失敗したため、検証環境を整えて再実行した。
