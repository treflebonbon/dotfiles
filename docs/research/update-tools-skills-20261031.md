# AI ツール・管理スキル更新（2026-10-31）

## 現在の要件

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

CRGの対応3 systemのdirect outputが1.4.1を参照することは、元の`remote-cache.json`でも照合した。grammar実行の互換性とは区別する。関連する`tests/nix-devshell.bats`は21/21、skipなしで成功した（`/tmp/codex/ai-tools-rq7nzhz0/startup.log`）。修正commit `9068cee`の再レビューはCodexのStandards軸で規約違反0件・smell0件だった。Claude OpusのSpec軸では旧S-2の追跡状態を明記する指摘が1件あり、上記の保留理由と判断時点を追記後、追加指摘なしを確認した。Brotliの許容判断を含む更新全体の受入は未完了として追跡する。今回の3点の修正後のcanonical検証は、実施後に追記する。
