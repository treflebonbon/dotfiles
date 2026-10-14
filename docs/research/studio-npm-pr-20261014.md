# studio依存・生成物の独立PR（2026-10-14）

## 現在の依頼と範囲

承認済み推奨案と正式briefに基づき、studio依存と生成dist／ライセンスを独立した更新単位として実装・検証・独立2軸レビュー・親確認・canonical全Bats・通常PR公開まで進める。checkoutは `/home/ubuntu/orca/workspaces/dotfiles/update-studio-deps-20261014`、branchは `dev/update-studio-deps-20261014`、baseは `681e6c5dd610cbbe195ebc5dd412736c216e7021`。同session自身のreadinessと親の照合が成立し、model／effortはsessionの実効記録でgpt-6.1-sol／xhigh、cwdも一致した。main／live source／配備先は編集せず、merge／apply／default branch pushは行わない。

予定変更は `local-skills/domain-modeling-studio/{package.json,package-lock.json,dist/studio.html,dist/THIRD-PARTY-LICENSES.txt}` と本記録、`nix-languages-pr-20261013.md`／`root-npm-pr-20261014.md` の7 file。React／react-dom 19.3.0、React Flow 12.12.0に入口候補を固定し、esbuild 0.28.2／exact指定／scriptsを維持する。UI・model・render・export・CSP・offline契約とライセンス保持を変えない。root npm／Nix／template／AI／APM／Codex設定、汎用helper／testsは今回の変更に含めない。

[conventionsのテスト・更新追跡](../conventions.md)、[ADR-0045 Decision 1–4](../adr/0045-separate-llm-agents-and-apm-update-units.md#decision) の更新単位／互換性ゲート／rollback境界、[ADR-0061](../adr/0061-retire-rop-visualizer-into-domain-modeling-studio.md#decision) の単一renderer／ROP契約、[ADR-0062](../adr/0062-scope-architecture-layer-to-neighborhood.md#decision) の近傍1ホップ、[ADR-0038](../adr/0038-keep-wsl2-browser-free.md)／[ADR-0059](../adr/0059-scope-browser-ownership-and-share-attachments.md) のWSL browser-free／用途別ownership、[skill-harness](../../runtime/skill-harness.md) のWorktree・ローカル配布・レビュー／公開契約を適用する。過去ADRのpin候補は今回の固定版に置き換えない。

## 公式候補・native lockと取得経路

入口の親公式metadataは `tmp/studio-npm-20261014/parent-direct-registry.json`。直接依存のpublish ageはReact／react-dom約34.39日、React Flow約19.58日、維持するesbuild約66.28日で7日待機を満たす。別のlatestは追わない。

base lockはrootを含む51 entry、全50 packageのresolved hostが `npm.flatt.tech`。公式registry指定だけで既存resolvedが残るかを隔離したnative npmで実測し、candidateは公式resolvedに揃えたnative生成を採用する。URL変更と推移依存の再解決を分けて記録し、全new／changed版のpublish timeと7日待機、全packageの公式SRI／peer／実取得経路を照合する。metadata／SRIは手編集せず、repo／global npm設定は変更しない。

[React 19.3の公式release](https://react.dev/blog/2026/09/09/react-19-3) は新規APIと既存挙動の修正を含む。現行callerはcreateRoot、useState／useEffect／useRef、memoを使うclient-only rendererで、新規ViewTransition／Fragment ref／browser API、SSR／Server Componentsを導入しない。[React Flow 12.12.0](https://reactflow.dev/whats-new/2026-09-24) はresize終了通知とshouldResize拒否時の値を修正する。現行ReactFlowのノード変更／ドラッグ／選択／fitView／レイヤー切替と、peer契約を実際の候補で検証する。

## 分割成果の採否と対応先

保留成果 `864880c0498d9b274c506183a2087f0863d674f7` はread-only参考。丸ごとcherry-pickせず、現在baseとの二点比較を使う。過去の成功件数を今回の実測に転記しない。全分割の除外台帳は[一般Nix記録](nix-languages-pr-20261013.md#元差分から外した変更の追跡)と[root npm記録](root-npm-pr-20261014.md#保留成果の採否と別単位の状態)を維持する。

| 対象 | 採否・理由・対応先・状態 |
| --- | --- |
| studio direct3／lock／dist／license | 今回採用。公式registryのnative生成と現在のbuild／検証で独立PRへ移管する。対応先PRは公開後に追記。未merge・未配備。 |
| #397–402のAI／APM／Impeccable／Matt／モデル／固定CLI、#403の一般Nix／6言語 | main採用済みsourceを維持。referenceへの巻戻しや未変更gateの成功転記はしない。 |
| root npm #404 | merge済み、merge SHA `681e6c5`。親がmainでBun 1.4.2 frozen install、Oxfmt 0.72.0／Oxlint 1.87.0／Ultracite 7.12.4／source-map-js 1.2.2とpair hash不変／cleanを確認。root npmの反映根拠であり、chezmoi配備全体の完了とは扱わない。 |
| 汎用helper／対応tests／helper案内 | 別単位として保留、対応先未定。必要な検証補助だけGit管理外へ読み取り取得し、sourceへ追加しない。 |
| referenceのmirror lock／過去統合記録 | mirror URLの採用と記録の巻戻しは却下。過去履歴は参照checkoutに保持する。 |

## 今回の検証と制限

unit／real-content／architecture/model、native buildの二回byte一致、manifest／lock不変、license／CSP／安全埋め込み／export／offline／skill treeのnode_modules不在、関連Batsを実行する。base／candidateの隔離install／実解決／auditを別々に保存し、新規advisoryを過去の既知問題として流さない。rootの既報braces／magicast内旧bundleは今回修正済みとは扱わない。

browser QAは既存browser fixturesをManaged Playwright Chrome／CDPで実測し、WSLへのbrowser導入／download／local launchと別consumerの暗黙closeを行わない。証拠は `tmp/studio-npm-20261014/` に保存し、失敗logsも保持する。実装commitをbaseからLuna／xhighの独立Standards／Specでレビューし、同HEADの親 `parent-confirmation.json` を確認してからcanonicalを開始する。

canonicalは同source／test／deps／環境で一度実行し、source-selected user／repo両wsl devShell、6AI output／実版、Playwright browser-free、Impeccable 4.5.2／engine 0.1.14のfrozen payloadを開始前から照合する。TAP／exit／elapsed／全tracked前後hash、必須Design Hook13＋Playwright2 fixtureを確認し、既定opt-in skipは成功に数えない。成功後の結果文書だけの追記では全suiteを反復しない。

## native npmの実測と採用lock

Node.js 24.21.0／npm 11.19.0で、base、既存lockを引き継ぐprobe、manifestだけから再生成するcandidateを別々のGit管理外directoryへ置いた。公式registryを指定したnative `npm install --package-lock-only --ignore-scripts --no-audit --no-fund` は、既存lockを引き継ぐprobeではresolvedをmirror 30件／公式20件にした。公式registry指定だけでは全resolvedが置換されないため、このprobeは採用しない。

採用lockはcandidate manifestだけを置いた `tmp/studio-npm-20261014/candidate-fresh/` で同じnativeコマンドにより生成した。全51 entry（root＋50 package）とpackage集合は不変。全50 resolvedを公式tarball URLに揃えた。このうち42 packageは版不変のURL変更、8 packageは版とURLの変更である。root Bun lockの空registry fieldとは異なるnpmのresolved表現として記録する。repo／global設定やmetadata／SRIは編集していない。

| package                 | base → candidate  | 公式publish time（UTC） |
| ----------------------- | ----------------- | ----------------------- |
| react                   | 19.2.8 → 19.3.0   | 2026-09-09 17:21:30.071 |
| react-dom               | 19.2.8 → 19.3.0   | 2026-09-09 17:17:39.744 |
| @xyflow/react           | 12.11.6 → 12.12.0 | 2026-09-24 12:41:36.171 |
| @xyflow/system          | 0.0.82 → 0.0.83   | 2026-09-24 12:43:01.347 |
| scheduler               | 0.27.0 → 0.28.0   | 2026-09-09 17:17:30.281 |
| @types/d3-selection     | 3.0.11 → 3.0.12   | 2026-09-14 19:05:21.375 |
| @types/d3-zoom          | 3.0.8 → 3.0.9     | 2026-09-29 01:51:15.933 |
| use-sync-external-store | 1.6.0 → 1.7.0     | 2026-09-09 17:19:07.352 |

最後の1.7.0はZustandの既存要求範囲内のnative再解決で、referenceの1.6.0とは異なる。新規direct／overrideは追加しない。8変更版はすべて604800秒以上、最短約15.038日、deprecatedなし。candidate全50 packageのSRIとresolvedは今回取得した公式metadataに一致し、base全50のSRIも公式版と一致した。referenceと同じ7変更版を想定した最初の検証側assertは失敗したが、実際の8変更版すべてのage／SRI／auditは通過した。失敗記録も保存している。

base／probe／candidateの `npm ci` と `npm ls --all --json` はexit 0。base／candidateのReact DOM peerとReact FlowのReact／React DOM peerを満たし、typesのoptional peerを強制導入しない。Linuxで実installされた25 packageは全てlock版と一致し、他platform用のesbuild optional 25 packageはmetadata／SRIだけを照合した。candidateのfrozen再検証でmanifest／lock前後SHA-256が一致した。3試行の公式 `npm audit --json` は全てexit 0／advisory 0件で、新規advisoryは検出されなかった。rootの既報advisoryとは区別する。

実HTTP GETログでは、base／probe／candidateいずれも実tarball取得は `registry.npmjs.org` の25件だった。baseのcache key表記はmirror、probeは混在、candidateは公式だけであり、lock表記・cache key・実GET先を区別する。readonlyで観測した `replace-registry-host` は `npmjs`、registryは明示した公式URL。実取得ログだけを根拠にmirror lockの移植性まで保証しない（`fetch-routes.json`、`npm-fetch-policy.json`）。

根拠は `registry-integrity.json`、`registry-metadata/`、`lock-field-diff.json`、各install／ls／audit logs、`candidate-frozen-result.json`。保留成果からlockをコピーせず、今回native生成したpairをsourceへ戻した。

## studio検証・bundleとbrowser QA

既存 `npm test` は15 pass／0 fail／0 skip。unit、real-content、architecture／modelを通過した。関連Batsは23 pass／0 fail／0 skip、TAP plan1つ・1–23連番・bailoutなし、exit 0（`unit.log`、`related-result.json`／`related-tap-result.json`／`related.log`）。関連件数を後段canonicalへ合算しない。

現行 `node scripts/build.mjs` を2回実行し、HTML／licenseのSHA-256がbyte一致、manifest／lock不変、skill treeにnode_modules不在を確認した。buildのnpm ciは既存どおりskill tree外の一時directoryで実行した。esbuildの実metafileからbundleへ入る17 packageを抽出し、全licenseがsidecarとHTML内noticeへ一致、7箇所のinline legal commentも保持した。検証scriptが/*!形式だけを想定した初回assertは失敗したが、実bundleの/** @license形式に対応した検証で通過し、product／build scriptは変更していない（`build-result.json`、`bundle-result.json`）。HTMLは452875 → 482550 byte（+29675）、licenseは16412 byte。CSPはbaseからbyte不変、外部script／stylesheet入口を追加せず、renderの安全JSON埋め込み・export契約を維持した。

browser QAは導入済みPlaywright CLIの正規Managed Windows Chrome identityからCDP接続し、offlineなlocalhostへのroute fulfillmentで今回の生成HTMLを表示した。既存browser fixtureの30 assertとreal-contentの8 assertを維持した一時adapterで、base／candidateの全workflowとcandidate real-contentの3層drilldownがexit 0。実測は表示・安全埋め込み、readonly現状／改善案編集、層切替／drilldown、指摘保持、Undo／Redo、ドラッグ、コピー拒否fallback、競合import、JSON backup download／復元、旧版保護、4成果物、mobile overflow、storage failure、pageerror 0／外部request 0を含む。fixture表示のlocalhost requestだけを通信assertから除外した。画像／model／backup evidenceは `browser-{base,candidate}-session-retained-evidence/` と `browser-real-content-secure-evidence/` に保持する。

最初の `http://studio-test.invalid` adapterでは安全なcontextにならず、base／candidateともcrypto.randomUUID不在で指摘追加がtimeoutした。localhostではnative crypto.randomUUIDと指摘操作が通過したが、Windows ChromeへLinux artifact pathを渡すdownloadは両方canceled。専用Windows directoryと新規own browserContextIdだけにdownload behaviorを設定し、そのCDP sessionを直ちにdetachする試行も両方canceledだった。同sessionをdownload完了まで保持すると両方成功した。Chromeの実download failureがnullであることとWindows実ファイルを確認し、WSLのPlaywright artifact pathへbyte一致で受渡した後、元のsaveAs／export payload assertionsを通過させた。Blob mock、assert弱化、product source変更はない。

導入版のCDP close実装はChrome WebSocket transportの切断へ進むことを確認し、作成したcontextだけをcloseして接続を終了した。Managed Chrome本体は試行前後の同一webSocketDebuggerUrlで生存を照合した。default／shared contextのdownload設定や別consumerは変更しない。WSL browserの導入／download／local launchは行っていない。既存runtimeに実ファイル受渡しの公開helperは見つからず、一時adapterにその境界だけを置いた（`browser-qa-result.json`、`cdp-disconnect-evidence.txt`）。

実際のfile://のrouting／storage／download、Firefox／WebKit、ARM／Darwin実機は未確認。HTTP origin失敗とsecure再試行、実downloadの差を成功へまとめず、全失敗logsを保持した。source／test／depsはこの切り分けで変更していない。

## 親の最終read-only gate

関連検証済みsourceをhookを通してcommitし、base `681e6c5dd610cbbe195ebc5dd412736c216e7021` から同commit済みHEADを独立Standards／Spec（両方gpt-6-luna／xhigh）でレビューする。未解決指摘を解消して同HEADの `review-result.json` を保存し、clean状態の完全HEAD／evidenceを親へ返す。canonicalは同HEADの `parent-confirmation.json` にconfirmed:trueがあることを確認してから開始する。これは追加ユーザー承認ではなく正式briefのread-only照合gateである。

## 独立レビュー・親確認・canonical全Bats

実装commitは `171685cb249a996f291934e8d658586b4725223b`。同commitをbase `681e6c5dd610cbbe195ebc5dd412736c216e7021` からgpt-6-luna／xhighの独立並列Standards／Specでレビューし、両軸0件、未解決0件だった。親も同完全HEAD／clean／7file scope、全50公式SRI／8版待機、生成物hash／license／browser実ファイル、現在追跡をread-onlyで照合してconfirmed:trueを保存した（`review-result.json`、`parent-confirmation.json`）。pre-commitのOxfmt／gitleaksとcommit-msgのcogを通過した。

同source／test／deps／環境のcanonical `lefthook run test` は一度実行し、769件（748 pass／21 skip／0 fail）、runner／canonical／launcher exit 0、989.12秒で成功した。TAP plan1つ、1–769の連続番号、bailoutなし、全581 tracked fileの前後SHA-256が一致した。今回のunit15／関連23／browser assertや、過去の769／787件等はこの件数へ合算していない。TAPは `tmp/test-run.k9zc0y/tap.log`、同directoryにsetup／environment／exit-code、今回evidence内に `canonical-source-before.json`／`canonical-source-check.json`／`canonical-output.log`／`canonical{,-launch}.exit`／`current-tap-path`／`full-result.json` を保存した。

source-selected user／repo両wsl devShellはshellHookより前からHOME／全XDGを隔離した。6AI output／実版はCodex 0.162.1、Claude 2.1.296、Copilot 1.0.96、Antigravity 1.3.3、APM 0.33.0、Herdr 0.9.3で一致。既存patched Codex outputを再利用し、不要なRust再buildを開始していない。採用Playwright browser-free outputは `/nix/store/r1mia04ilacqdfh4blbgb3hibpjsclap-playwright-cli-0.1.22`、engineは `/nix/store/8d2qywl01wrwpvykrgxg5r9jg7gxw981-impeccable-0.1.14`。frozen APM runtime `/tmp/fixed-clis-apm.mHuaBN` のsource pair／全20 dependency metadata・payload／両target各46 skill・追加0削除0を今回再照合し、固定source commitの公式package version 4.5.2、両launcher／scripts VERSION 0.1.14と実engine-probeを確認した。実Design Hook13件＋Playwright runtime2件の15必須fixtureはcanonical内で通過し、runtime不足skipはない。

初回の環境検証補助はplanを配列として渡したため形式検証でexit 1になり、Bats開始前に停止した。正しい `candidates: []` へ直し、source／test／deps／準備済み隔離環境不変を確認して続行した。初回は `environment-attempt-1/` と `canonical-launch-first-preparation.exit` に保持し、全suiteの一回と区別する。環境根拠は `tmp/ai-tools-1z2qiybm/`、`canonical-package-metadata.json`／`canonical-ai-version-check.json`／`canonical-environment.json`／`apm-runtime-verification.log`／`impeccable-runtime.json`。

21 skipは実Herdr／Bash 3.2、認証・実モデル／MCP、専用隔離runtime／dependency gateway、6言語独立生成、public Nix appの既定opt-in。未変更の6言語gateを今回実行済みとは扱わない。実file://／cross-browser／ARM・Darwin、live配備も未確認。成功後は結果と対応先の3文書だけを追記し、実行source／test／lock／deps／検証環境を維持するためcanonicalを反復しない。

## 公開境界

実remote defaultはmain。親の日本語3節草稿を実測値で確定し、英語Conventional Commits title `chore(deps): update domain modeling studio` で通常PRを公開する。topic pushは `git-push-topic` に限定し、force／default push／merge／applyを行わない。公開後に対応先を3文書へ追記し、最新HEADのCI／PR本文byte一致／local・upstream・actual remote・PR HEAD／cleanまで照合する。studio個別PRの完了と、汎用helper保留／未キャッシュCodex source build要件を含む更新全体の完了は区別する。
