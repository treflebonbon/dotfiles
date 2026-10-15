# canonical検証の証拠記録の設計（2026-10-15）

この記録は `$grill-with-docs` 中の合意と現状確認をまとめたもの。Q1–11はユーザーが各推奨案を採用し、設計全体の最終確認後に `$implement` を明示して実装・検証・レビュー・commitへの移行を承認した。

## 合意済み

- **Q1 — 実行証拠の照合から**: 成功報告の前に、証拠の欠落と異なる実行結果の混在を検出する。PR本文やCI記載漏れの照合は初回範囲外。
- **Q2 — dotfilesに限定**: 他repoへの配布は初回範囲外。
- **Q3 — 全Bats 1回分から**: 公開前のcanonical実行について、source・環境・TAP・終了コードを対応付ける。関連テストやAI/APM個別検証を共通集約する機能は初回範囲外。
- **Q4 — 新規実行時から記録**: 既存の検証コマンドを一度だけ実行し、開始前条件と終了後結果を記録して対応付ける。既存ログだけでは、実行前のHEAD/hashを後から証明できない。
- **Q5 — 必須証拠5点**: 対象worktreeと完全なHEAD、全trackedファイルの実行前後の内容一致、実行コマンドと使用したruntimeの記録、TAPと終了コードの整合、指定した必須fixtureの成功・skipなしを必須にする。
- **Q6 — 不足・不一致時の扱い**: Bats自体の結果と証拠照合の問題を区別し、必須証拠が不足・不一致なら全体を検証成功とせず非0終了する。原始ログを保持し、自動再実行はしない。既定のopt-in skipは許容し、指定必須fixtureのskipだけを不成立にする。
- **Q7 — 時間の計測範囲**: 全Batsを呼ぶ既存コマンドの開始から終了までの実測時間を必須にする。環境準備込みの総時間を記録する場合は別項目とし、実測・推定を明示する。
- **Q8 — 利用する入口**: 更新時に明示して使う手動入口から、既存の `lefthook run test` を一度呼ぶ。既存のログ保存とTAP検査を再利用する。
- **Q9 — 開始時のsource**: 作業ツリーがcleanで、検証する変更がcommit済みであることを開始条件にする。完全なHEADと実際の検証対象を対応付ける。
- **Q10 — 必須fixtureの初期設定**: 既存のDesign Hook 13件とPlaywright runtime 2件を既定セットにし、各名称の存在・成功・skipなしを照合する。件数だけでは判定せず、独立した名前一覧の変更をレビュー対象にする。
- **Q11 — runtimeの準備**: 必要なruntimeは既存手順で事前準備して渡す。入口は準備状態を確認し、不足時はBats開始前に理由を返す。Nix buildやAPM再生成は既存の準備手順で行う。

## 確認した事実

- [`scripts/test.sh`](../../scripts/test.sh) は `tmp/test-run.*` にTAP、setup、environment、exit-codeを残す。Batsが終了コード0の場合、TAP plan、連番、失敗結果、bailoutを確認する。
- 同じ入口は通常の `bun run test` と `lefthook run test` から使われ、[`tests/test-entry.bats`](../../tests/test-entry.bats) はGitのないfixtureへ入口をコピーして検証する。
- 生成した `tmp/test-run.*` を呼出元へ機械的に返す手段は現状ない。内部変数の値をstderrへ人向けに表示するだけである。test-entryのfixtureは入口を再実行し、export済みの環境変数も継承する。
- 既定にするDesign Hook 13件とPlaywright runtime 2件のテスト名は、現在のtop-level `tests/*.bats` 間で重複していない。
- [`scripts/verify-ai-tools.py`](../../scripts/verify-ai-tools.py) は `metadata.json`、`paths.tsv`、`startup.log`、`exit-code` を保持し、sourceから選ばれた実行パスを照合してからCLIを起動する。集約コンソールには個別パスを出さない。
- 直近のPR #408では、一時記録のconsole由来パスがnullだったため `startup.log` を根拠に補正した。本実行時間1119.94秒とlauncher総時間の推定値1164.44秒は別の計測境界である。最初のlauncher失敗（127、Bats未開始）も本実行とは分けて保持した。過去の `tmp` JSONのキーは現行仕様を意味しない。

## 実装へ渡す設計案

手動入口は、検証対象のlinked worktreeと完全なHEAD、clean状態、事前準備したruntimeを確認し、全trackedファイルの記録を採取してから `lefthook run test` を一度だけ呼ぶ。終了後に同じ実行のTAP・終了コード・runtime記録を読み、sourceの前後記録と必須fixtureを照合する。既存コマンドの開始から終了までを実測し、スイート結果と証拠照合の結果を区別して報告する。

初期の必須fixtureは、base `bf31e700feef5ba9443c367e0d6d087ca757c894` の `tests/design-hook.bats` にある13のテスト名と `tests/playwright-runtime.bats` にある2つのテスト名で固定する。今回実行したTAPや変更中のテスト定義から期待する一覧を動的に作らず、各名称が結果に一度ずつ現れて成功し、skipされていないことを確認する。

ログの対応付けに最新directory探索や人向けconsoleの表示解析は使わない。`scripts/test.sh` が生成したログ先をその呼出元へ一意に返す最小限の連携だけを追加する。連携しない通常実行の挙動は維持し、受渡し情報はテスト内の別runnerへ引き継がない。実際のCLI名や内部項目名は実装時に既存の規約に沿って決める。

runtimeは既存のrunnerの記録と、明示した非秘密の実行パスを根拠にする。宣言値と実行記録を区別し、環境変数の実値全体を列挙しない。AI/APM個別gateの採否や6AIの版・output一致をこの入口で再判定する機能は追加しない。

```mermaid
flowchart TD
    A[手動入口] --> B{clean・HEAD・runtimeを確認}
    B -->|不成立| F[理由を記録して非0終了]
    B -->|成立| C[source前記録を採取]
    C --> D[既存の全Batsコマンドを一度実行]
    D --> E[同じ実行のログ・終了コード・source後記録を照合]
    E --> G{スイート成功・必須15件成功・証拠充足}
    G -->|成立| H[結果と実測時間を報告して終了0]
    G -->|不成立| F
```

### 受入確認

- 正常な全suiteのTAP・終了コードと、必須15件それぞれの存在・成功・skipなしを照合し、成功・skip・失敗の件数を分けて報告できる。suite全体の総件数は固定値にしない。
- 異なる実行のログ混入、ログ受渡しの欠落、source/HEADの前後不一致、欠けたまたはskipされた必須fixtureを成功として扱わない。
- clean条件やruntimeの準備状態が不成立ならBatsを開始しない。実行開始後の失敗・中断では元のログを保持し、成功にせず、自動再実行もしない。
- 通常のテスト入口と、Gitのないfixtureからの入口利用を維持する。テスト内で別runnerが起動しても外側の実行のログ参照を上書きしない。

sourceの照合は前後のHEAD・追跡対象・内容に対するもので、実行途中だけの変更や全filesystemの不変を保証するものではない。この記録が示すのは検証した時点のsourceと結果であり、後続のPR HEADやlive配備との一致確認は別の手順に残す。

## 最終確認

目的・範囲・合格条件・利用方法についてQ1–11の判断は完了し、最終確認への回答である `$implement` により設計全体の合意が成立した。同じtask worktreeで実装phaseを継続する。

テスト境界は、受入確認で合意した手動入口のコマンドと、既存runnerのログ先受渡しとする。前者は終了結果・保存した証拠と不足や混在の拒否を、後者は通常実行・入れ子のrunner・非Git fixtureとの互換性を確認する。外部コマンドをfixtureへ置き換える関連検証と、準備済みの実runtimeでの全suiteを区別する。

## 今回の境界

記録はこのrepoの手動入口が使う最小限に留める。汎用evidence JSON schemaやworkflowへ自動配線する新しいgate、上流skillのforkは導入しない。既存の準備・個別検証を一括実行する仕組みやPR本文・CIの照合も今回の範囲外とする。

用語集には合意した範囲の `canonical検証` を記録する。この変更はrepo内で容易に戻せる手動検証の改善であり、ADRの採用基準である変更コストの大きい判断には当たらないため、ADRは追加しない。

参照: [ADR-0004](../adr/0004-fill-mattpocock-gaps.md)（旧機構の境界）、[ADR-0041](../adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md)（schema/gate境界）、[ADR-0071](../adr/0071-adopt-mattpocock-standard-workflow.md)（標準workflow）、[ADR-0046](../adr/0046-separate-orca-native-worktree-entry.md) および [`runtime/skill-harness.md`](../../runtime/skill-harness.md)（native worktree入口）。

## 実装と関連検証

手動入口は `scripts/verify-canonical.py`。標準ライブラリだけを使い、source・runtime・TAP・必須fixture・実測時間をその試行の記録として保持する。既存runnerへの追加は、呼出元が用意した専用directoryへログ先を返す連携と、子への受渡し情報の継承解除に限定した。元のログを保持し、TAPのSHA-256、コマンドとrunnerの終了コード、中断シグナルを区別して記録する。

ログ受渡し不在と実行runtime記録の空欄、中断の未伝達、中断時の実コマンド終了コードの取り違え、helpによる意図しない全suite開始を、回帰テストで失敗させてから修正した。手動入口のfixtureは実Git linked worktreeと実runnerを使い、外部のlefthook・Bun・Batsだけを置換する。source/HEAD/runtimeの変更、必須名の欠落・重複・skip、異なる実行の参照、非Gitの通常入口も検査する。

source-selected user/repo両wsl devShellの準備は成功し、PlaywrightとImpeccableのoutputと実行パスを照合した。既存frozen runtimeのmanifest/lockはsourceとbyte一致している。関連検証は準備済みdevShellで29件（29 pass／0 skip／0 fail、exit 0、18.627秒）を確認した。証拠は `tmp/canonical-implementation-20261015/` の `related-prepared-result.json`、`related-prepared.tap`、`preparation-result.json`、`prepared.json`。

独立レビューでは、明文化規約違反0件、命名提案1件、仕様指摘1件だった。JSON保存関数の命名を具体化し、コマンドとrunnerの異なる失敗終了コードも証拠不一致として記録するよう修正した。終了コードの回帰テストは修正前の失敗を確認してから追加した。

修正後の関連検証は30件すべてpass、skip・failは0件。`ruff`、`shfmt`、`shellcheck`、TypeScriptの型検査、formatter、commit hooksも通過した。実装HEAD `943a81fc6e05a29e170565d9ed9eff698a974321` の独立再レビューは `gpt-6-luna` / `xhigh` で実施し、Standardsの規約違反・設計上の懸念とSpecの未解消指摘はいずれも0件だった。証拠は `review-result.json`。

## 初回の全Bats実測結果

同じHEADのcleanなworktreeで、source-selected user/repo両wsl devShellから手動入口を一度実行した。全Batsコマンドの実測は985.404秒、外側のlauncherは1000.964秒。別途実施した環境準備は30.124秒で、全Batsの時間には含めない。

- TAPはplan 809、787 pass／21既定skip／1 fail。連番1–809は完全で、bailoutなし。
- Design Hook 13件とPlaywright runtime 2件の必須15名称は、各1回・pass・skipなし。
- 589 trackedファイルと13のruntime記録は前後一致。独立照合時の内容も一致し、HEAD変更やdirty化はなかった。
- runner・lefthook・手動入口・launcherはいずれもexit 1。原始TAPのSHA-256は記録値と一致し、証拠照合エラーは0件。

失敗は既存の `dogfood without annotation preserves the existing report path`（TAP 222）で、Managed Dogfood Chromeの起動前に `port-conflict:8620` を検出した。後続のread-only確認では、WindowsのChrome PID 8620が `127.0.0.1:19385` を使用していた。失敗メッセージの数値はPIDであり、失敗時の予約portを直接記録した値ではない。競合相手の停止やsource/test/deps/envの追加変更はせず、この試行は検証不成立として保持した。自動再実行は行っていない。

記録先は `tmp/canonical-run.zllf56i2/`、runnerログは `tmp/test-run.LsIZKz/tap.log`。独立照合の結果と失敗箇所は `tmp/canonical-implementation-20261015/` の `full-result.json`、`canonical-failure.log`、`dogfood-conflict.json` に保持する。この初回の結果を確定した時点では全suite成功は未成立で、後続の診断と新規試行へ引き継いだ。

## ポート競合の診断と修正

後続の `$diagnosing-bugs` で、同じtask branchへmainの#409をmergeした（`3e6687ceb4863095f7d2e7bf7ea067100f930cf3`）。通常の失敗テスト単体は36.383秒でpassしたため、run IDを `dogfood-port-repro-3` に固定し、公開された `acquireManagedDogfoodChrome` を直接呼ぶ再現コマンドへ縮小した。Playwright接続・レポート生成・npm installを外しても、ポートの明示指定なしで同じ `port-conflict:8620` を2回連続、2.540秒／2.391秒で再現した。

仮説は、所有権記録先の分断、共通記録にも存在しない外部listener、起動・終了タイミングの競合、の順に提示した。呼出元の共通記録先には19385の予約があり、HOME/XDGを隔離した記録先にはその予約がなかった。同じrun ID・runtimeのまま記録先だけを共通の値へ変えると、19385を避けて19386で起動し、10.683秒で正常終了した。根本原因は、隔離した `XDG_RUNTIME_DIR` によって所有権記録の参照先まで分断したことだった。自動割当とlock自体は、ADR-0059の同じ記録先を共有する前提どおりに動作している。

同じ問題を持つ既存の `scripts/verify-ai-tools.py` を修正した。HOME/XDGの分離前に `BROWSER_OWNERSHIP_DIR` を確定し、明示値を維持するか、元の `XDG_RUNTIME_DIR` → `TMPDIR` → `/tmp` から導く。回帰テストは実際のCLIからNix境界と後続コマンドまで値を確認し、修正前の省略時の失敗と、修正後の成功を確認した。関連40件はすべてpass、skip・failなし。既存のroot解決・自動割当・外部競合の拒否契約は変更しない。

実6 CLIを照合する公開helperから同じ再現コマンドを呼ぶ対照実験も行った。修正前は6 CLI照合成功後に同じ競合でexit 1（30.187秒）、修正後は6 CLI照合成功後に19386で起動・終了しexit 0（36.090秒）。既存Chromeの停止や予約の削除はしていない。証拠と一時的な診断スクリプトは `tmp/dogfood-port-diagnosis-20261015/` に分離して保持する。修正HEAD `bd34733e28b72c752d8a02f0f5d02eddb11f0e5a` の独立レビューは `gpt-6-luna` / `xhigh` で実施し、Standardsの規約違反・設計上の懸念とSpecの未解消指摘はいずれも0件だった。

## 修正後の全Batsと最終照合

修正HEADのcleanなworktreeで公開helperを使い、実6 CLIのsource-selected outputと版を照合してからcanonical入口を一度実行した。Playwright／Impeccableのoutputとfrozen runtimeのmanifest/lockも開始前に照合した。共通 `BROWSER_OWNERSHIP_DIR` はNix評価・両devShell・後続のcanonical実行まで引き継がれた。初回の失敗試行とは記録先を分けた、新規の実行である。

- TAPはplan 824、803 pass／21既定skip／0 fail。連番1–824は完全で、bailoutなし。main #409のテストと今回の回帰テストを含む。
- 必須15名称は各1回・pass・skipなし。初回に失敗したdogfoodテストもTAP 222でpassした。
- 593 trackedファイルと13のruntime記録は前後一致。独立照合時の内容も一致し、実行中にsourceやHEADを変更していない。
- runner・lefthook・canonical入口・AI helper・launcherはすべてexit 0。原始TAPのSHA-256と記録値は一致し、証拠照合エラーは0件。
- 全Batsコマンドの実測は1097.750秒。環境準備・6 CLI照合等を含む外側のlauncher全体は1121.947秒で、別の計測境界として扱う。
- 既存19385予約の内容hashは診断前後で一致した。全TAP出力後のread-only観測でも、Chrome PID 8620は同portを使用していた。

canonical記録は `tmp/canonical-run.ms8c9z_f/`、TAPは `tmp/test-run.vQk5tY/tap.log`、AI照合は `tmp/ai-tools-vyxy_367/`。独立照合の `full-result.json`、レビューの `review-result.json`、原因対照の `diagnosis-result.json` は `tmp/dogfood-port-diagnosis-20261015/` に保持する。sourceへのdebug instrumentationは残さず、一時的な診断スクリプトは同directoryだけに分離した。

全Bats後はこの結果文書だけを追記し、実装・tests・依存関係・検証環境の追加変更や全Batsの再実行は行わない。push・PR公開・PRのmerge・applyは今回の診断では実施していない。21件のopt-in検証は未実行のままである。
