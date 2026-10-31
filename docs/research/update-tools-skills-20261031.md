# AI ツール・管理スキル更新（2026-10-31）

## 現在の採用範囲（APM本体・依存の切替を除外）

ユーザーの追加依頼「apm 関連だけ省いた更新」と選択「APM本体・依存の切替だけを外し、管理スキルの更新は残す」に従い、PR #549を再構成する。APM 0.35.0と既存のBrotli 1.2.1修正は更新前と同じoutputを維持し、Claude Code / Codex等の他6ツール・waza・管理スキルの更新を残す。未修正upstream APMへの切替は後続対応先未定の保留とし、この候補から除外する。自前ビルド・live apply・mergeは行わない。

以下の初期候補とPR全体の保留判断は、追加依頼までの履歴である。現在の採否と外した差分は末尾の「APM除外版」で追跡する。

## 初期要件と経緯

依頼は「`implement` ツールとスキルの更新」。範囲はユーザーが選択した「AI ツール＋全管理スキル」。追加指示は「自前ビルドしない。llm-agents のもの」。開始点は main `97820638edf96c911b2e9a1bc2957856cc204706`、Codex native worktree `/home/ubuntu/.codex/worktrees/8bc3/dotfiles`、branch `chore/update-tools-skills-20261031`。公開・merge・live 配備は今回の実装依頼に含めない。

適用する判断は ADR-0045 の更新単位分離と今回の direct package 方針、ADR-0047 の品質 floor、ADR-0042 の Matt managed set 更新ゲート、ADR-0053 の Impeccable skill / engine 一体検証、ADR-0082 の公開 plugin の固定版照合。過去の記録は参考資料とし、今回の要件と区別する。

## 更新単位と採否

| 更新単位 | 採否・理由 | 検証 |
| --- | --- | --- |
| Tool Snapshot | `959a6e37…` → `2cae3bb5496cf25b2e951a69f8ecbee963e211c7`。Claude Code 2.1.314、Codex 0.166.0、Copilot CLI 1.0.105、Antigravity CLI 1.4.12、APM 0.35.0、Herdr 0.9.5、code-review-graph 2.3.9。7件とも upstream direct package を加工せず採用。 | Linux の7 outputをビルド禁止で取得成功。対応3 system計21 outputのNumtide cache登録も照合。6 CLIの実パス・版表示を確認。 |
| 通常 APM | Modern Web Guidance `4f2b13e25c5815b3f080ca0d983e828d96561a0f`、Remotion `30d4553ecd46fbc5212fd0ff006ae43af522158b`、Orca CLI `eb3379ff9909f2856113e9cfdc5223c754f5ffe2` に exact pin を更新。floating の orchestration と react-view-transitions にも実体変更あり。 | 生成・frozen no-rewrite・audit 10/10・両 target 配備比較に成功。21 dependency、各 target 47 skill、追加12・削除10。候補外・共有 owner ledger と root metadata は不変。 |
| Impeccable | [Skill 4.8.0](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.8.0) `414603bf14c7a344edb466bb1f85690c77ce8b7d` と [engine 0.1.18](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.18) を一体で採用。未リリース HEAD は採らない。 | 生成・frozen no-rewrite・audit 10/10・配備比較成功。実 engine と候補 launcher に対する Design Hook 13/13、skipなし。 |
| Matt Pocock | 1.3.1 `49dd158d…` → 1.3.2 `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` を採用。27件の membership は不変。fresh context の子、新規 setup の GLOSSARY 移行案内、tracker template 更新が主な差分。 | 専用ordered gate成功。全704件は成功688・既定skip16・失敗0、chezmoi dry-run前後のHOMEも不変。gate後のnative生成・frozen・audit・配備比較も成功。grillingの人間待ちとローカルsafety boundaryを維持。 |
| 公開 skills plugin | 0.2.3を維持。upstream main `629d10fb…` と現行 `7428e056…` は267 fileの内容・種類・実行属性が一致し、更新理由がない。 | 採用するClaude Code 2.1.314で公式導入と2回の再同期が成功。管理設定bytesと全267 fileを維持。 |
| 個別 CLI | [waza 0.39.1](https://github.com/microsoft/waza/releases/tag/v0.39.1) を公式 binary の固定hashで採用。design.md 0.4.0、Playwright CLI 0.1.22、[Ponytail 5.3.3](https://github.com/DietrichGebert/ponytail/releases/tag/v5.3.3) は公開最新版と一致し維持。 | waza起動成功。Impeccableとwazaの対応3環境hashを公式配布物と照合。 |
| 文書変換 CLI | defuddle 0.19.5 / markitdown 0.1.8 の候補は却下し、既存0.19.3 / 0.1.7とsource pin `d6524aac…` を維持する。追加のsource buildを避ける今回の指示を優先。 | 候補の日本語HTML変換は成功したが採用根拠にしない。汎用・言語ツールとroot開発依存も範囲外。 |

通常APMの実体変更は、Web guide改訂、Remotion 4.0.539、Orca CLIのtrigger整理、orchestrationのworkerとnative subagentの使い分け、React 19.3で安定化したViewTransitionの案内。anthropics、shadcn、computer-use、Vercelの他3件、find-skillsはrevisionだけ進みpayload不変。security-audit、Effect-TS、empirical-prompt-tuning、animated-arch-diagramはrevision / payloadとも不変。HerdrのHEADは固定tagとpayloadが同じため、CLI 0.9.5に揃えたpinを維持する。native lockの`resolved_ref`はmanifestのexact pinに限る。

## 再構築しない方針と残る依存

最初の候補 `467c27cb…` は、既存のAPM向けBrotli修正を保つとGit 2.56.0と多数のPython 3.14依存を再構築した。追加指示を受けてその方式を却下し、APMのPython scope overrideと、code-review-graphのローカルdependency / FastMCP patchの適用を終了した。旧patchとparser定義の3ファイルは、ファイル削除の事前確認を受けていないため残すが、現行packageからは参照しない。shared overlayでAI packageを再計算せず、同じsnapshotのdirect outputを使う。Claude / Codexの品質floor（2.1.296 / 0.162.0）とFastMCP >=3.2.4は維持する。

**CRGの依存範囲変更（確認済み）:** CRG 2.3.9本体は`tree-sitter-language-pack>=0.3.0,<1`を宣言するが、採用するllm-agents packageは`pythonRelaxDeps`と`--skip-dependency-check`で上限を緩和し、1.4.1を使う。[導入時の不採用判断](code-review-graph-adoption.md)を今回のdirect package方針で改め、ローカルの`<1`検査と0.13.0の再構築経路を終了した。grammarの同梱と子プロセスprobe用Pythonの修正は上流packageが供給する。LinuxではPythonサンプルのgraph build / MCP呼出しが成功したが、Python以外の言語とARM / Darwinでのgrammar互換性は未確認である。

**確認済み（x86_64-linux）:** 採用7 outputのclosureを`nix-store --query --requisites`で読み取り照会した。209 pathに独立した`nodejs` packageは0件で、APMのclosureには`brotli-1.2.0-lib`と`python3.14-brotli-1.2.0`がある。snapshotのpackage setの`pkgs.nodejs.version`は24.21.0だが、採用outputにその版が含まれることの根拠にはしない。ツール同梱Node runtimeの版と、ARM / DarwinのclosureにおけるNode / Brotliの実体は未確認である。

以前のローカルAPM再構築によるBrotli修正済み保証とは両立しない。Brotli 1.2.1は[CVE-2026-111497の修正release](https://github.com/google/brotli/releases/tag/v1.2.1)であり、今回のAPM依存を修正済みとは扱わない。ローカル配布CLIのNode.js修正検査と、upstream 7 packageの完全なderivation一致検査を分ける。後者の成功は脆弱性修正の保証ではない。攻撃者制御streamが各アプリに届く経路は未確認。upstreamへの書込みは行わない。

## 検証と証跡

- `scripts/verification_env.py` / `verify-ai-tools.py` の保護境界を使い、通常HOMEを変更しない。cache照会は `direct-metadata.json` / `remote-cache.json`、7件のビルド禁止取得は `direct-cache.log`（exit 0）。共通rootは `/tmp/codex/update-tools-skills.PG6k7U/`。
- 通常APMは同rootの`ordinary/`、Impeccableは`impeccable/`。Impeccable採用後のfrozen SHA-256は `a31572a4f20cdf0e8c396a7738efc429b8104d21f20e8641e7077fecb909defe`。両targetのbytes / hash / discovery、候補外と共有owner ledger、既存owner / active_ownerを照合した。
- Impeccableの3 assetは候補skillの`engine-checksums.txt`にも一致し、Design Hook 13件をskipなしで検証した。
- 採用するClaude CLIの実同期記録は `/tmp/codex/claude-plugin-native.66opwq9n/result.json`。前候補の同じ版に対する記録`mopb4o7g`とは区別する。
- 関連Bats初回は83件中81成功・2失敗。失敗はfloatingのOrca revisionと、更新済みReact View Transitionsの旧hash期待値。floatingは40桁revisionの形式と承認済みcontent hashで検査し、exact pinのmanifest/lock一致は維持した。Reactのgolden hashを採用payloadへ更新後、`tests/apm-runtime.bats` 18/18成功。
- Matt gate初回は同じ旧期待値によりworkflow contract段階で停止し、全Bats・dry-runへ進んでいない。証跡`matt-gate.phases`とruntime `matt-temp/mattpocock-update-gate.Rj2nIg`を保持。修正後の2回目は別記録`matt-gate-2.phases`で実行した。
- Matt gateの2回目は全704件のうち成功687・既定skip16・失敗1。入力なしPTYテストだけが30秒で失敗した。こちらが追加した`BATS_NUMBER_OF_PARALLEL_JOBS=16`が子Batsにも継承されることが原因で、同じテストを16で実行すると失敗、1へ変えるだけで成功した（`pty-jobs16.log` / `pty-jobs1.log`、同じ条件の再確認も一致）。追加環境変数を外した標準ゲートの3回目（`matt-gate-3.phases`、runtime `matt-temp/mattpocock-update-gate.nDcQr7`）はworkflow69/69、全704件中成功688・既定skip16・失敗0、chezmoi dry-runとHOME不変を順に通過した。テスト本体・期限・判定は変更していない。
- gate成功後、`matt-native/`で実manifestからnative lockを生成した。frozen前後のSHA-256は`061fab1d785e69069c0d6cbd1b5dbea0785a61be2ba6e1050be72751e40dba6e`で不変、audit10/10。selected content hashは`sha256:d2c8efe424482ed9b171ed5f61a3315bf7fca87ee88184a0d164477e956ddd45`。配備比較の候補はMattだけで、追加・削除0、他20依存のpayload・全1508件の既存owner / active_owner・共有ledgerとroot metadataを維持し、このmanifest / lock pairをsourceへ採用した。native生成中に他依存のrevision-only movementもなかった。
- Matt native pairをsourceへ採用した後のAPM / workflow / orphan cleanup関連Batsは57/57、skipなしで成功した（`/tmp/codex/ai-tools-njgxf1ob/startup.log`）。
- frozen root依存の導入、`bunx tsc --noEmit`、Nix / Markdown整形は成功。記録は `/tmp/codex/ai-tools-ge4rruyh/startup.log`。
- 文書変換の候補smokeは継承したPython 3.14向け`PYTHONPATH`がPython 3.13のNumPyと衝突した。`env -u PYTHONPATH`で同じ入力の変換が成功した。以降の検証からこの継承変数を外した。候補そのものは上記の理由で採用しない。
- 実装commit `f44b0a1`に対するStandards / Specの独立レビューは両軸とも指摘なし。
- source採用後のcanonical初回（`tmp/canonical-run.0ixpwk9u`、環境`/tmp/codex/canonical-env.aeta547l`）は全704件中成功689・既定skip14・失敗1。`tests/mattpocock-update-gate.bats`に残った旧Matt content hashの期待値が原因だった。上記の検証済みnative lockのhashに更新した。関連するgate / APMテスト36/36がskipなしで成功した（`/tmp/codex/ai-tools-zkmk0hbz/startup.log`）。実測137.604秒で、Design Hook13件・Playwright runtime2件はすべてskipなしで成功し、source / HEAD / runtimeの前後照合も一致した。修正後の再検証は別記録として残す。
- hash期待値修正commit `f021913` の追加差分もStandards / Specとも指摘なし。最終canonical（`tmp/canonical-run.z34oyl6f`、環境`/tmp/codex/canonical-env.ox__ys9a`）は、cleanな同commitで `lefthook run test` を実行して成功した。全704件中成功690・既定skip14・失敗0、コマンドとrunnerのexitはともに0、実測148.725秒。Design Hook13件・Playwright runtime2件はすべてskipなしで成功し、source / HEAD / runtimeの前後照合も一致した。TAP SHA-256は`489f853ee5e7cf8bfc7f890a970399099e0187a7f3bd3c40b873f288722d9673`。この成功後の`d12cf38`では記録だけを追記した。後段のHerdrレビュー対応は別の差分として検証する。
- 旧候補の起動検証3件は方針相談時にSIGTERMで中断した（exit 143、テスト失敗と区別）。ARM / Darwin実機、実Windows Chrome、実モデル呼出し、live配備は検証に含めない。

## Herdrレビューへの対応

ユーザーの「推奨案で進めて」を受け、Node依存の確度表現、CRGの依存範囲変更の記録、Playwrightのテストfixtureに残る不要なshared overlay参照を修正した。package pin、APM manifest / lock、品質floorは維持し、自前ビルドやローカルpatchを追加しない。未使用3ファイルの削除は対象に含めない。Brotliの未修正依存は既知の残課題として維持し、旧レビューS-2の脆弱性許容判断は保留する。今回の推奨案の承認からCVE再露出を許容する明示承認を推定せず、受入・merge時の判断に残す。

既存storeの読み取り照会とCRG 2.3.9のsource確認は`/tmp/codex/fix-tools-review.Uzl4nO/dependency-inspection.json`に保存した。これはLinuxの採用7 outputに限る実測で、package setのNode版や同梱runtimeの版、他systemの実行結果へ一般化しない。floatingのorchestration / React View Transitionsはrevisionとcontent hashの両方が変わっており、通常APMの採否記録は変更しない。

CRGの対応3 systemのdirect outputが1.4.1を参照することは、元の`remote-cache.json`でも照合した。grammar実行の互換性とは区別する。関連する`tests/nix-devshell.bats`は21/21、skipなしで成功した（`/tmp/codex/ai-tools-rq7nzhz0/startup.log`）。修正commit `9068cee`の再レビューはCodexのStandards軸で規約違反0件・smell0件だった。Claude OpusのSpec軸では旧S-2の追跡状態を明記する指摘が1件あり、上記の保留理由と判断時点を追記後、追加指摘なしを確認した。Brotliの許容判断を含む更新全体の受入は未完了として追跡する。今回の3点の修正後のcanonical検証（`tmp/canonical-run.0y7t6af0`、環境`/tmp/codex/canonical-env._drivf9i`）はcleanな`f0b18bc`で成功した。全704件中成功689・skip15・失敗0、コマンドとrunnerのexitはともに0、実測146.231秒。従来の既定skip14件に、現在のagent runtimeがrepo-localの`.agents`をmountしていることによるskip1件が加わった。Design Hook13件とPlaywright runtime2件はskipなしで成功し、source / HEAD / runtimeの前後記録も一致した。TAP SHA-256は`6f04150333e4255f90ab694951e68cdded3fa5e852ac2117ae2d60669d002512`。この実行後は検証結果の記録だけを追記し、実装・依存・テストは変更していない。

## PR公開前の鮮度再確認（2026-10-31）

追加依頼を受け、HerdrのCodexとClaude OpusでUTC 05:40〜05:46（JST 14:40〜14:46）に公開情報を再取得した。AIツール7件の採用版、waza 0.39.1、Impeccable skill 4.8.0 / engine 0.1.18、design.md 0.4.0、Playwright CLI 0.1.22は公開releaseと一致する。

llm-agentsのmainは[`19fcd79d82aaf136a14c77d40607dd9510bbda27`](https://github.com/numtide/llm-agents.nix/tree/19fcd79d82aaf136a14c77d40607dd9510bbda27)へ進んでいた。親側でimmutable sourceを取得し、IFDを禁止したmetadata評価で採用snapshotと比較したところ、7件×3 systemの21 packageはversion・derivation・outputがすべて一致した。このためsnapshot pinは維持する。証跡は`/tmp/codex/tools-update-pr.4VKDFg/llm-head-outputs.json`。取得・評価だけでツールの自前ビルドは行っておらず、APMのBrotli依存も変更しない。

Orcaのmainは調査時点で`99cddd97962479cbea92f2da634684334d8d3cf3`だった。[PR #36498](https://github.com/stablyai/orca/pull/36498)のselected skill差分はorchestrationの「--jsonを優先する」案内の削除だけで、他の契約は維持される。採用commitの展開payloadも旧runtimeと直接比較し、選択対象の差分が公開PRの差分と一致することを確認した。通常APMの別更新単位としてnative生成・frozen no-rewrite・audit 10/10・配備比較を通し、解決された`1bd67185489c66a9e0d841e0134727f171a33764`をlockへ採用した。orchestrationのcontent hashは`sha256:591831560700d73c2bc1ca6658dddb6e91f1b52264d116e8ab9095ec3a80bdf0`、frozen前後のlock SHA-256は`0a3cd0f61bc91cf85b1fdf11b030c52339ef28f5fa42619f72fbf8fc5e881f3d`。他20依存のselected payload、各targetの47 skill、追加・削除0、全1508 ledger recordの既存owner / active_owner・共有ownerとroot metadataを維持した。computer-useのrevision-only進行もnative lockへ自然反映し、orca-cliのexact pinは維持する。証跡は同rootの`orchestration/`に保存した。

Impeccableの未リリースmainは採用せず、MattのHEADと1.3.2 pinは一致する。公開skills pluginのmain `629d10fb926b31a633b52adf7cacd50fcd780d8a`とpinは前回と同じなので、以前の同一payload照合を参照して0.2.3を維持する（今回267 fileを再比較したとは扱わない）。Ponytail 5.3.3とcodex plugin 1.0.6等の公開版を確認したが、runtimeが自動管理するpluginの導入済み版とchrome pluginの公開配布元は未確認である。

文書変換CLIには[Defuddle 0.19.6](https://github.com/kepano/defuddle/releases/tag/0.19.6)と[MarkItDown 0.1.9](https://github.com/microsoft/markitdown/releases/tag/v0.1.9)の新候補がある。以前に却下した0.19.5 / 0.1.8とは区別し、今回の新候補について自前ビルドなしのcache / 配布経路は未確認のため採用しない。source pinと既存版を維持する。Brotliの許容判断は旧S-2の保留状態を維持し、今回の再確認やPR公開を許容承認とは扱わない。

採用後の`tests/apm-runtime.bats`は18/18、skipなしで成功した（`/tmp/codex/ai-tools-k8al1k5d/startup.log`）。追加差分commit `c8c3339`はHerdrのCodex（Standards）とClaude Opus（Spec）で再レビューし、両軸とも指摘なしだった。公開するHEADの検証結果はPR本文と公開記録へ残す。最新情報の再確認だけから、未実施のruntime検証やlive配備を完了扱いにしない。

## PR #549 Review Round: 修正済みupstreamを待つ

初期の実装依頼の後、ユーザーの`$pr`でtopic pushとPR公開が承認された。[review 5721661884](https://github.com/treflebonbon/dotfiles/pull/549#pullrequestreview-5721661884)のBrotli指摘に対し、ユーザーは「修正済みupstreamを待ち、このPRのmergeとAPM配備を保留する」を選択した。PRをdraftへ戻し、旧S-2のリスク許容判断は保留のまま維持する。APMの未修正依存が残るため、thread `PRRT_kwDOTMg6A86yOp1_`は未解決で残す。修正済みupstreamの選定・cache取得・依存確認・必要な検証が済むまで、mergeとAPM配備を再開しない。

**confirmed:** 最新upstream `28d5a74ef304d1a3c7a5f6cacfb52bacbf922698`のimmutable sourceを取得し、IFDを禁止したmetadata評価を行った。対象7件×3 systemのversion・derivation・outputは採用snapshotとすべて一致し、Linuxの候補APM outputもBrotli 1.2.0依存を持つ同じoutputだった。snapshot pin・実行設定・APM manifest / lockは変更せず、自前ビルドは行っていない。

**confirmed:** 現在PATHで選択される配備済みAPM `/nix/store/b57d3rsdby4w5pf67hs20y5ddp3kkach-apm-0.35.0`のclosureは、`brotli-1.2.1-lib`と`python3.14-brotli-1.2.1`を参照する。候補への切替を保留し、この配備は維持する。候補APMの`install/validation.py`には`requests.get(...)`があり、[Requestsの公式説明](https://requests.readthedocs.io/en/latest/user/quickstart/#binary-response-content)どおりBrotli libraryが導入されていると`br`応答は自動復号される。攻撃者が制御する応答の到達可能性は**unconfirmed**で、exploit可能とは断定しない。[Brotli 1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1)の修正を候補APMへ適用済みとも扱わない。

今回の証跡rootは`/tmp/codex/pr549-feedback.ZS6GDQ/`。`threads.json`、`llm-latest-metadata.json`、`latest-outputs.json`、`live-apm-closure.txt`に取得結果を残す。前節のorchestration更新の証跡は`/tmp/codex/tools-update-pr.4VKDFg/orchestration/`にある。公開HEADの検証結果と公開照合はPR本文・公開記録へ残す。

## APM除外版

APM本体・依存の切替を除き、管理スキルの更新を残すユーザー選択に従う。PR全体を未修正APMの修正待ちとする直前のscopeを改め、APM切替だけを後続の更新単位へ保留する。PRのmerge・live配備は別途の受入後に行う。旧S-2の未修正Brotliを許容する判断は、本PRの対象外となり、APM切替の後続単位へ移す。

| 元候補の差分 | 現在の扱い | 根拠と対応先 |
| --- | --- | --- |
| APMを新snapshotの未加工outputへ切り替え、Brotli修正用overrideを終了 | 本PRから除外・保留 | Brotli 1.2.0を再導入するため採用しない。修正済みupstreamへの切替は対応先未定。 |
| 既存のAPM 0.35.0とBrotli修正 | 維持 | `llm-agents-apm`に旧snapshot `959a6e37234ae40e3ae6d4c9a564ec1a8803ccf9`を固定し、既存の`nixpkgs-brotli-sources`とPython / Git依存修正をそのまま使う。 |
| 他のllm-agents 6ツール・CRGのdirect output化 | 採用候補を維持 | 同じ`2cae3bb5`の未加工outputを使い、品質floorと18 outputのcache証拠を維持する。 |
| 通常APM payload・Impeccable skill / engine・Matt managed set・waza | 採用候補を維持 | 管理スキルは更新済みmanifest / lockを維持し、保持するAPM outputでfrozen互換性を確認する。 |

**confirmed（予備評価）:** 更新開始点`9782063`と同じAPM定義・依存入力から構成した3 systemのderivation・outputはすべて開始点と一致した。Linux outputは現在配備済みの`/nix/store/b57d3rsdby4w5pf67hs20y5ddp3kkach-apm-0.35.0`であり、既存storeから再利用できる。候補snapshot全体を旧版へ戻さず、APMの依存入力だけを分ける理由である。APMの新規patchや新規ビルドを追加しない。APMは従来の配布方式を維持し、新規端末へのcold installとARM / Darwin実機での実行は今回の確認範囲に含めない。

証跡rootは`/tmp/codex/update-without-apm.aD5lCK/`。予備評価は`probe-apm.nix`と`probe-apm.json`。**confirmed（採用source）:** `final-matrix.json`でも3 systemのAPM derivation・outputが開始点と一致し、他6件は新snapshotのupstream出力と一致した。Linuxの計7 outputは`--max-jobs 0 --builders ''`で取得成功（`existing-outputs.log`、終了コード0の`existing-outputs.exit-code`、出力の`existing-outputs-result.json`）。保持APMのclosureはBrotli library / Python bindingとも1.2.1だった（`apm-closure.txt`）。

保持するAPMで更新済みmanifest / lockを`frozen/`へ隔離導入し、frozen前後のlock SHA-256は`0a3cd0f61bc91cf85b1fdf11b030c52339ef28f5fa42619f72fbf8fc5e881f3d`で不変、audit 10/10。各targetの47 skill、追加・削除0、全1508 recordの既存owner / active_owner・共有ledger・root metadataを維持した。`tests/runtime-security.bats` / `tests/nix-devshell.bats` / `tests/apm-runtime.bats`は45件中44成功・runtimeによるrepo-local `.agents` mountのskip1・失敗0だった（`/tmp/codex/ai-tools-idbvlqgu/startup.log`）。公開HEADのcanonicalは別途PR本文・公開記録へ残す。review thread `PRRT_kwDOTMg6A86yOp1_`には、APM切替を外したcommitの公開確認後に変更と検証結果を返信する。

APM除外版の初回canonicalはcleanな`30d7a93`で705件中690成功・skip15・失敗0だった（`tmp/canonical-run.nb3h83jc`、実測185.084秒）。CodexのStandards軸で、汎用closure検査が保持APMをビルド対象へ含める指摘が1件あり、APMを除外して専用の読み取り検査へ任せるよう修正した。Claude OpusのSpec軸は修正必須0件で、旧S-2の移管と取得終了コードの記録を明確化する提案を反映した。Brotli走査の共通化提案は、APMの存在必須検査とNodeの任意の共有library検査で条件が異なるため個別のまま維持する。修正後の公開HEADのcanonical結果はPR本文へ残す。
