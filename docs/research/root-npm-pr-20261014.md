# root npm依存の独立PR（2026-10-14）

## 現在の依頼と範囲

承認済み推奨案と正式briefに基づき、root npm依存を独立した更新単位として実装・検証・2軸レビュー・親確認・canonical全Bats・commit・topic push・通常PR公開まで行う。checkoutは `/home/ubuntu/orca/workspaces/dotfiles/update-root-npm-20261014`、branchは `dev/update-root-npm-20261014`、baseは `33c826ce2c9b1c2443f289549cff1945b2918d3d`。同sessionでphysical root／branch／HEAD／clean／Git dir／common dir／pointer／back-pointerを自身でread-only確認済み。親はこのsessionのmodel／effort／cwdを照合済み。main／live source／配備先は編集せず、merge／applyは行わない。

予定sourceは `package.json`／`bun.lock`。Oxfmt 0.72.0、Oxlint 1.87.0、Ultracite 7.12.4に固定し、別のlatestを追わない。Bun／bun-types 1.4.2、TypeScript 7.0.2、brace-expansion override 5.0.9、既存script／preset／caller、`minimumReleaseAge=604800`を維持する。native Bun生成と公式registryを使い、lock metadata／integrityは手編集しない。動作維持に必要な設定修正が判明した場合だけ最小修正と根拠を記録する。

[conventionsの更新追跡とレビュー](../conventions.md#ツールスキル更新の追跡とレビュー)、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) Decision 1–4の更新単位／互換性ゲート／rollback境界、[architecture](../architecture.md#ツール追加先の使い分け)の供給区分、[Worktree開始規約](../../runtime/skill-harness.md#worktree-の開始と復旧)を適用する。既存[一般Nix／6言語記録](nix-languages-pr-20261013.md)には今回対応先だけを追記する。Git管理外の今回証拠は `tmp/root-npm-20261014/` に保存する。

## 保留成果の採否と別単位の状態

保留成果 `864880c0498d9b274c506183a2087f0863d674f7` はread-only参考で、whole cherry-pickや過去の検証成功の転記はしない。現在baseと保留成果の二点比較を使い、root pairに関係する変更だけを選択する。

| 対象 | 採否・理由・対応先・状態 |
| --- | --- |
| root `package.json`／`bun.lock` | 三つのdirect更新と公式source-map-js修正を採用。参考lockのmirror URLは採用せず、今回native生成で公式registry／SRI／7日待機を検証。[通常PR #404](https://github.com/treflebonbon/dotfiles/pull/404) は2026-10-14にmerge済み（`681e6c5`）。親がmainでBun 1.4.2 frozen install、Oxfmt 0.72.0／Oxlint 1.87.0／Ultracite 7.12.4／source-map-js 1.2.2、pair hash不変・cleanを照合。root npmの反映根拠であり、chezmoi配備全体の完了ではない。 |
| #397のAI snapshot／floors／Codex direct output・cleanup、#398–400のAPM／Impeccable／Matt、#401のモデル設定、#402の固定CLI／Playwright公式registry lock | main採用済みsourceを維持。保留成果への巻戻しは却下。今回の検証で過去成功を代用しない。 |
| #403の一般Nix pins／6言語template／architecture | merge済みbaseを維持。今回未変更の全3system／6言語gateは反復しない。配備全体の完了は断定しない。 |
| studio `package.json`／`package-lock.json`／`dist/studio.html`／`dist/THIRD-PARTY-LICENSES.txt` | 別単位として保留していた。2026-10-14に[studio独立更新記録](studio-npm-pr-20261014.md)へ移管し、branch `dev/update-studio-deps-20261014` で実装・関連検証・独立2軸レビュー・canonical全Batsを完了。[通常PR #405](https://github.com/treflebonbon/dotfiles/pull/405) をOPEN・非draftで公開済み。未merge・未配備。 |
| `scripts/verify-ai-tools.py`／`scripts/verify-apm-deployment.mjs`、対応tests、helper案内 | 汎用helper配布の別単位として保留。対応先PR未定。必要な検証補助だけGit管理外へ読み取り取得し、今回sourceへ追加しない。 |
| 参考 `docs/research/update-tools-skills-20261011.md`／`braces-response-20261013.md` | 過去履歴として保留checkoutに保持。今回の要件・実測とは区別し、現在braces依存／入力経路／公式修正状態／auditは本記録で再確認する。 |
| 既存5分割記録／conventions／skill-harness／ADR | 採用済み規約・対応先を維持。古い記録への巻戻しや同じ全文の重複追記は却下。 |

2026-10-14現在、root npmは#404のmergeと親のmain frozen install照合まで完了。studioは[通常PR #405](https://github.com/treflebonbon/dotfiles/pull/405)で公開済み（未merge・未配備）、汎用helperは保留のため更新全体は未完了。以下の実装・公開・Review Roundは当時の履歴として保持する。

## 公式候補・native生成・lock検証

公式release APIで三つの候補がdraft／prereleaseでないことを確認し、npmのdeprecated指定もない。[Oxfmt 0.72.0](https://github.com/oxc-project/oxc/releases/tag/oxfmt_v0.72.0) はMarkdownをnative formatterへ切り替えるbreaking changeと日本語改行保持の修正を含む。[Oxlint 1.87.0](https://github.com/oxc-project/oxc/releases/tag/oxlint_v1.87.0) はruleのsuggestion／fixer修正、[Ultracite 7.12.4](https://github.com/haydenbleasel/ultracite/releases/tag/ultracite%407.12.4) はopt-in GDP preset追加を含む。GDP presetは採用しない。npm latestは別版だが、今回の固定候補を維持した（`official-summary.json`）。

| direct依存 | base → candidate | 公式npm publish time（UTC） |
| ---------- | ---------------- | --------------------------- |
| oxfmt      | 0.67.0 → 0.72.0  | 2026-10-05 11:03:48.808     |
| oxlint     | 1.82.0 → 1.87.0  | 2026-10-05 11:05:35.081     |
| ultracite  | 7.11.1 → 7.12.4  | 2026-10-05 15:41:15.303     |

導入版Bun 1.4.2のhelpで `--registry`／`--minimum-release-age`／`--lockfile-only` を確認し、公式registryを指定したnative `bun add --dev oxfmt@0.72.0 oxlint@1.87.0 ultracite@7.12.4` で固定版を生成した。Bunがexact宣言を書いたため、package.jsonの三つを既存caret形式へ戻し、native `bun install --lockfile-only` でworkspace dependency metadataを同期した。実解決版は固定候補のまま。repo／global .npmrcや取得policyは編集せず、lock metadata／SRIも手編集していない。後述のsource-map-js修正もnative経路で行った。

lockは148 → 152 entry。OXCの各19 native bindingをdirect版に揃え、Ultraciteの要求範囲に従い `@clack/prompts`／`@clack/core`、empathic、magicast、string-width、yaml、zodを更新した。Oxfmtのtinypoolも2.2.0へ進む。string-width 8.3.0を要求するUltraciteと8.2.2固定の既存caller、yaml 2.9.1を要求するUltraciteと2.9.0固定のfind-workspacesを同時に満たすため、旧版のnested entryが計4件増えた。これらはnative再解決の結果で、新しいdirect依存／overrideはない。workspace name `claude-plugins-coherence` はbase由来でnative Bunも保持したため、手で補正していない。

152 entryすべてのSRIを今回取得した公式npm metadataと照合し、全tarball hostが `registry.npmjs.org`、lockのregistry fieldは全てbaseと同じ空文字列だった。保留成果の `npm.flatt.tech` 固定URLは採用しない。最終package version集合は参考lockと一致するが、registry表現と今回のnative生成／検証を区別する（`registry-integrity.json`、`lock-diff.json`、`lock-result.json`）。

新規選択50 unique versionを公式npm publish timeと今回UTC時刻で照合し、全版が604800秒以上、最短も約8.087日を満たした。TypeScript 7.0.2／bun-types 1.4.2は不変。candidate frozen installはexit 0、package.json／bun.lockの前後SHA-256不変、実node_modulesの三つのdirect／TypeScript／bun-types／source-map-jsはlockと一致した（`publish-times.json`、`candidate-frozen.log`、`lock-result.json`）。

## preset・caller・実環境の互換性

rootのOxlint／Oxfmt設定、project-ignore-patterns、lefthook／bunx caller、scriptを維持した。UltraciteのOxfmt preset29行と共通ignore78行はbaseからbyte不変。Oxlint coreは606 → 622行で、test拡張子追加、Astro override、TypeScript rule追加等のupstream差分を含む。実candidateでpreset import／ignore合成のassert、`bunx tsc --noEmit` とroot3 TypeScript fileのOxlintがexit 0。Bun 1.4.2と実candidate `bunx oxfmt`／`oxlint`／`ultracite` のversion／helpも起動成功した（`preset-source-comparison.json`、`preset-config-compat.log`、`candidate-{typecheck,oxlint,cli-smoke}.log`）。

source-selected user／repo両wsl devShellをshellHook前からHOME／全XDGで隔離し、6AI CLIのNix outputと実起動を照合した。Codex 0.162.1、Claude 2.1.296、Copilot 1.0.96、Antigravity 1.3.3、APM 0.33.0、Herdr 0.9.3が一致した。証拠は `tmp/ai-tools-k693jmqx/` と `environment-launch.log`。Nix／templateを変更していないため全3system／6言語gateは反復せず、過去の通過数は今回へ転記しない。

関連 `tests/nix-devshell.bats` は29件通過・skip 0・fail 0・exit 0で、既存OXC／lefthook caller規約を含む。TAP plan／連続番号／bailoutなしを照合した（`related-result.json`）。変更JSON／Markdown3 fileだけを実Oxfmt 0.72.0で整形し、JSON値／文書内容保持、二回目のbyte不変・非空白文字不変、format check／diff checkを確認した。初回の生文字比較はtable区切り線のhyphen数変更で失敗したため、そのsyntaxだけを正規化して内容比較し、最終形式での再実行は生文字も不変だった。repo全体のformat sweepは行わない（`format-result.json`、`format-first.patch`）。

既存frozen runtime `/tmp/fixed-clis-apm.mHuaBN` はAPM source pairのbyte一致、20 dependency全metadata／payload、両target各46 skill・追加0／削除0、Impeccableの両launcher一致を今回照合した。source-selected engineの実probeは0.1.14、採用skillは4.5.2。canonical開始前からsource-selected Playwright browser-free packageとこのruntimeを固定する（`apm-runtime-verification.log`、`impeccable-runtime.json`）。

## 今回のadvisory再確認

base／最初のcandidateの `bun audit --json` は両方exit 1で、bracesに加えsource-map-jsのHighを検出した。後者を過去承認済みの既知bracesとして流さず、依存／入力経路と公式修正版を調査した。

[source-map-js GHSA-68fv-2mgg-jv7q](https://github.com/advisories/GHSA-68fv-2mgg-jv7q) は1.0.0以上1.2.2未満をaffected、1.2.2をpatchedとする。[公式1.2.2 release](https://github.com/7rulnik/source-map-js/releases/tag/v1.2.2) はindexed source mapのoffsetによるDoS修正を含み、npm公開は2026-09-30 14:08:09.382 UTCで7日待機を満たす。経路はUltracite → magicast → source-map-jsで、magicastの `^1.2.1` 範囲内、追加依存なし。親も公式版／age／tarball／SRIを独立照合し、既存root npm更新範囲での最小lock更新を承認した。

導入版の `bun audit fix --dry-run` はsource-map-js 1.2.1 → 1.2.2だけを提案した。同じnative `bun audit fix` はこの1 packageを更新し、package.jsonのdirect／overrideを変えなかった。修正後auditはbracesだけでexit 1。fix自体も残るbracesのためexit 1で、検出を隠すflagは使っていない。SRI／age／frozen／実版／root互換性は更新後のpairで検証した（`source-map-{registry,advisory,release}.json`、`audit-fix-plan.log`、`source-map-native-fix.log`、`candidate-audit-after.log`）。

ただしmagicast 0.5.5の配布distにはsource-map-js 1.2.1のconsumerがbundle内に残る。外部dependencyを1.2.2へ更新したことやmanifest auditの解消を、bundleも含む完全修正・安全保証とは扱わない。rootの通常callerは静的OXC presetだけを読み、Ultracite CLI／magicast／source-mapへ入力を渡す経路は今回の静的確認で見つからなかった。CLIのinit／config変換等を使う場合や、upstream bundleが更新された場合に再評価する。PoC／fork／patch／preset撤去は今回へ追加しない（`dependency-input-paths.log`）。

[braces GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm) はHigh、affected ≤3.0.3、patchedなし。今回公式npmのlatest／公開版一覧も3.0.3まで。依存経路はUltracite → fast-glob（find-workspaces経由を含む）→ micromatch 4.0.8 → braces 3.0.3でbaseから維持される。brace-expansion override 5.0.9とは別package。通常callerからの未信頼glob入力到達は静的確認範囲で見つからないが、未解決dev dependency advisoryとaudit exit 1をそのまま残す。ignore／dismiss／omit-dev／未公開修正は使わず、テスト成功と区別する。

## レビュー・canonical・公開

実装commitは `7e855f1e8604177a576d055ffb95cbc1a0d4829b`。同commitをbase `33c826c` から独立Standards／Specの並列subagent（指定gpt-6-luna／xhigh）でレビューし、両軸0件。親もGit HEAD／clean、4file scope、現在要件・台帳・検証・bundle制限をread-only照合して確認した（`review-result.json`、`parent-confirmation.json`）。pre-commitのOxfmt／gitleaksとcommit-msgのcogを通過した。隔離HOMEで作者情報が見えない初回exit 128と、作者変数だけではcogが設定を取得できない再試行はcommit前に停止した。通常環境で読み取った既存公開identityをprocessへ渡し、隔離HOMEだけへ同じidentityを補って回復した。通常のglobal／shared configは変更せず、hookを省略していない。

同source／test／依存／環境でcanonical `lefthook run test` を一度実行し、769件（748 pass／21 skip／0 fail）、runner／canonical／launcher exit 0、983.15秒で完走した。TAP planは1つ、1–769の連続番号、bailoutなし。全580 tracked fileの実行前後SHA-256は一致した。過去769／787件や今回関連29件をこの通過数へ合算していない。

開始前からsource-selected Playwright browser-free output `/nix/store/r1mia04ilacqdfh4blbgb3hibpjsclap-playwright-cli-0.1.22`、照合済みImpeccable 4.5.2のfrozen runtimeとengine 0.1.14を固定し、同隔離devShell環境の6AI CLI output／実版を再照合した。実Design Hook13件とPlaywright runtime／配布保護・共有FD2件は全suite内で通過し、runtime不足によるskipはない。

21 skipは実Herdr／Bash 3.2、認証・実モデル／MCP、専用隔離runtime／dependency gateway、6言語独立生成、public Nix appの既定opt-in。ARM／Darwin実機やPoC／動的到達性も今回未確認。未変更の6言語gateを実行済みとは扱わない。

今回TAPは `tmp/test-run.Yg07Ud/tap.log`。同directoryにsetup／environment／exit-codeを保存し、`tmp/root-npm-20261014/{full-result,canonical-source-before,canonical-source-check,canonical-environment,canonical-ai-version-check,canonical-required-fixtures}.json`、`canonical{,-launch}.exit`、`canonical-output.log`、`current-tap-path` に試行根拠を保存した。成功後は結果・対応先文書だけを追記し、実行source／test／lock／依存／環境を維持するため全suiteを反復しない。実remote defaultは `main` と確認済み。承認済みtopicを `git-push-topic` で非force公開し通常PRを作成する。merge／applyは行わない。

公開結果: [root npm独立PR #404](https://github.com/treflebonbon/dotfiles/pull/404) を `main` 向けOPEN・非draftの通常PRとして作成した。実装 `7e855f1` と結果記録 `40534d6` を `git-push-topic` で非force公開し、作成時local／PR HEAD `40534d684af147212e2d7950b2fa0227f23325f1` と英語Conventional title／確定日本語3節本文の一致を確認した。公開先の最小追記だけを同topicへ追加commit／pushする。CIは初回PR作成時点では未観測として本文に明記し、最新HEADの実結果とcode-scanningの判定制限を観測後にPR本文とGit管理外evidenceへ反映する。merge／applyは未実施で、studio／汎用helper等の保留による更新全体の未完了状態を維持する。

Review Round（[review 5508107296](https://github.com/treflebonbon/dotfiles/pull/404#pullrequestreview-5508107296)）: thread `PRRT_kwDOTMg6A86sAIVU` の指摘に従い、一般Nix記録の現在要約を表と同じPR #404公開済み・未merge／未配備へ修正した。studio／helperは保留成果864880cに残り対応先未定、更新全体未完了を維持し、過去phase記録は変更しない。変更文書のcandidate formatter／再整形不変／内容・リンク／diff／commit hookを検証し、一つの `fix: address PR review feedback` commitで非force公開する。実行source／test／依存／環境の一致を照合して上記canonical 769件の結果を再利用し、全suiteは反復しない。証拠は `tmp/review-5508107296/`。threadの返信／resolveは親が担当する。

## 汎用検証 helper の採否と現在の追跡（2026-10-14）

分割時に保留した2 helper と対応 tests／案内は、[独立した採否・検証記録](verification-helpers-pr-20261014.md)へ移管し、branch `dev/decide-verification-helpers-20261014` で限定した手動入口として採用する。対応先 PR は実装・検証後に確定する。上記の分割・公開・保留は各 phase 当時の履歴として保持する。

現在の base `1813c865897e0b8977a12a7b698977e6eafb00b2` は #397–405 の source 採用を含み、#405 は merge 済みである。親の merge 照合時に両 live hub の studio4files は旧版で、今回子からの配備照合・apply はしていない。helper 採用・canonical・公開と live 配備を区別し、更新全体を完了扱いにしない。未キャッシュ Linux の Codex source build 要件、root braces audit exit 1 と magicast 内の旧 bundle 残存は未解消のまま維持する。

### helper 実装・検証の完了（2026-10-14）

[helper 独立記録](verification-helpers-pr-20261014.md)の実装 `6346cd8` は、同 HEAD の独立 Standards／Spec 各0・親照合後に canonical 全795件（774 pass／21 skip／0 fail、全 exit 0、985.622秒）を完了した。実 Design Hook13＋Playwright2件は skip0、全586 tracked hash は不変。初回83関連／現 helper26件／過去 suite は別結果として保持する。結果文書だけを確定して topic 公開・通常 PR 作成へ進み、対応先を追記する。現在は helper 未 merge・未配備で、#405 source 採用と両 live hub の旧 studio 配備状態を区別する。
