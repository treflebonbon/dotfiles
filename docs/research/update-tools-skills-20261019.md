# ツール・スキル更新（2026-10-19）

## 現在の依頼と更新境界

依頼は「`$implement` ツールとスキルの更新」。調査・実装・必要な検証・Standards／Specレビュー・commitまでを対象とする。開始点はmain `30cd7bfa8bad5595ccb7074a479674e27d73135e`。Codex native worktree `/home/ubuntu/.codex/worktrees/b71d/dotfiles`、branch `chore/update-tools-skills-20261019` のphysical root・HEAD・clean・worktree Git dir・common dirを確認した。live sourceはprimary checkoutを指す。

ADR-0045 Decision 1–4の更新単位、同ADRの2026-09-01 amendmentのTool Snapshot先行merge、ADR-0047の独立した品質floor期待値、ADR-0053のImpeccable skill／engine一体検証を適用する。`docs/conventions.md` の更新追跡とsource build前の方針確認、`runtime/skill-harness.md` の隔離native lock生成・frozen不変・audit・配布照合に従う。過去initiativeの結果・承認を今回へ転用しない。

## 計画

- AI snapshot、全20 APM dependency、一般Nix、root／studio npm、固定CLI、言語sourceの候補を調べる。
- Tool Snapshotは実装入口で確認したdefault HEAD `53172a740b3f5f283274f456da3e3f0babca6504` を候補に固定する。既存バイナリのcache可用性とsandbox回帰を先に確認し、新たなCodex source buildを始めない。
- 通常APMはselected subtreeに実差分のあるexact pinを候補とし、floatingのrevision-onlyを区別する。両targetのfile bytes／hash、候補外metadataと共有ledgerを照合する。
- ImpeccableはHEAD `2f46b7a8b059af00d20dd13b64dbe165e7c6a742` のpayloadとengineを比較し、Design Hook gateの結果で採否する。Matt、Modern Web Guidance、Security Auditはdefault HEADが現行pinと同じため維持する。
- 採用したsource／lockに必要な既存test期待値と記録だけを変更し、機能や配布経路は追加しない。関連検証後、commit済み差分をレビューし、準備済みruntimeでcanonical全suiteを一度実行する。

調査証拠は `/tmp/codex/update-tools-skills-20261019.jXRa6F/` に保存する。sourceの実装完了と、PR公開・merge・live配備の状態は区別する。

## 候補の採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| Tool Snapshot | 不採用。候補のClaude 2.1.303／Codex 0.163.0／Copilot 1.0.98／Antigravity 1.4.2／Herdr 0.9.5／APM 0.33.0を確認。配布Codexのcleanupは8件中5成功・3失敗。現行patch付き0.163.0はcacheにないため、既存の適合配布待ち判断を維持し、新規source buildは実行しない。snapshot・floor・Herdr対応skillを維持する。 |
| 通常APM | Remotion 4.0.535→4.0.536を候補とする。Track／Interactive.create()／timeline構造、color correction、transitionの指針等、selected subtreeの25fileに実差分。Orca CLIは最新HEADのselected subtreeが現行pinと同一なので維持する。floatingの採用fieldとledger比較は生成完了後に記録する。 |
| Impeccable | 4.6.0のまま5fileのpayload更新を候補とする。改行指針、download中断時の一時file処理、HTTP originでのlive session／clipboard対応。engineのVERSIONは0.1.15で現行と一致し、engine packageは変更しない。 |
| Matt／Modern Web／Security Audit | default HEADが現行exact pinと一致し維持する。 |
| 一般Nix | root候補`fe132422`、user stable候補`21691b79`で直接packageの版を比較し、全て不変。revision-onlyの更新を不採用とし、両lockを開始点へ戻した。 |
| root／studio npm、固定CLI | npmのwanted／latestはmanifestと一致。Playwright CLI 0.1.22／design.md 0.4.0／gwq 0.1.2／waza 0.38.10／gws 0.22.5を維持する。flylineだけ1.9.0→1.10.0を採用候補とし、Linux2 assetの固定hashを取得した。ユーザーが追加承認した`gh release view`でdraft／prereleaseともfalseを確認した。 |
| 言語source | Gleam 1.19.1→1.19.2、rust-analyzer 2026-10-05→2026-10-12を採用候補とし、対象2テンプレートのlanguage sourceを`fe132422`へ固定する。Rust本体は公式安定版1.99.1が既存rust-overlayに収録されていたため1.99.0→1.99.1を採用する。Bun／Go／Perl／Elixir、共通with-envの検証済みrevisionと他4テンプレートは維持する。 |

AI snapshotを変更しないため、通常APMは採用済みAPM 0.33.0で生成する。source変更はmanifest／native lock／対象test期待値、flyline package、Rust／Gleamテンプレートと本記録に限る。新logicは追加せず、既存のtest・互換性gate・独立テンプレートgateで検証する。

## 採用前の関連検証

通常APMはaccepted lockを引き継いだ新しい隔離runtimeでnative生成・frozen hash不変・audit 10/10・配布照合が成功した。20 dependency、両target各46 skill、追加4file／削除0。Remotion単独ownerのledger hash46件と追加4件だけが変わり、残る1,418recordとroot metadata・全owners／active_ownerは不変。floatingのmizchi／shadcn／Orca2件はresolved_commitだけが前進し、selected payloadは不変。Mattを含む他dependencyの全fieldを維持した。

lockなしの最初の生成ではMattのnative package_typeだけが変わったため、その候補は採用しなかった。accepted lockをコピーした別の空runtimeで共通helperの`--update`を使い、候補外metadataも一致したnative出力だけを採用した。生成完了前の配布照合1回は未配布で失敗したため、完了後の成功と区別する。source lockの手編集・整形はしていない。関連APM／Nix／品質floorは67/67、source-selected 6CLIのoutput・実version照合、root TypeScript、Nix／Markdown format、root／userの3-system評価が成功した。

Impeccableは通常APM採用lockをbaselineとする別runtimeでnative生成・frozen hash不変・audit 10/10・配布照合が成功した。候補外19dependencyの全fieldは不変。ledgerはImpeccable単独ownerの10hashだけを更新し、残る1,458recordとroot metadata・全owners／active_ownerは不変。追加削除0、両target各46skill。実launcherとsource-selected engine 0.1.15によるDesign Hookは13/13・skipなし。上流のlive-session unit testは6成功、launcher download testは21成功・1skip（Windows固有）・失敗0。実browserでのlive modeは未確認。

flylineは公式Linux2assetをhash固定して取得し、Nix package化が成功した。Ubuntu bash 5.2.21とNix bash-interactive 5.3p9の実TTYでbuiltinロード・version／help・mouse無効化が成功した。Codexは既存のpatch付き0.162.1 outputを再利用し、新規source buildは実行していない。

証拠は共通一時directoryの`ordinary-apm-native/`、`impeccable-apm/`、`*-deployment.log`、`*-ledger.json`、`impeccable-design-hook.tap`、`flyline-tty.json`、`runtime-build.log`、`language-candidates.json`等。関連67件のTAP／exitはこのcheckoutの`tmp/ai-tools-7on0vweg/`に保存した。APM auditの組織policy enforcementはGit remoteのない隔離cwdのため未検証。関連gateの件数を後段のcanonical全suiteへ合算しない。

source採用後のAPM関連22件も全成功した。最終manifest／lockとImpeccable隔離runtimeのbyte一致を確認し、空candidate planの全配布照合（20 dependency、両target各46 skill、追加削除0）が成功した。user devShellの3-system全package構成を開始点と比較し、版変更はLinuxのflylineだけ、Darwinは全版不変だった。

独立テンプレートgateはshared nixpkgsを既存の`7529d323`、Rust overlayを入口で固定した`42076d1c`に揃え、全6言語を実行した（最終結果は次節）。source差分はRust／Gleamの2テンプレートとRust手順書だけで、他4言語のsourceを変更していない。誤指定した不存在の`tests/templates.bats`は収集時に失敗し、検証成功に含めない。存在する`tests/helpers/template-with-env.py`の結果を採用する。

## レビュー・canonical検証の境界

通常APM、Impeccable、flyline、Rust／Gleamを別commitにした。開始点`30cd7bfa8bad5595ccb7074a479674e27d73135e`からのcommit済み差分をStandards／Specで確認した。両軸へ現在の依頼、本記録、適用ADR・規約を渡した。今回PR分割は行わず、採用しなかった候補と理由は上表へ記録した。PR公開・merge・live applyは未実施で、本依頼の完了条件に追加しない。

レビュー後に最終sourceをcleanにし、source-selected 6CLIと既存Codex outputを`verify-ai-tools.py --no-codex-build --shell wsl`で照合した。最終APM runtimeのlauncher、source-selected engine、WSL Playwright outputを開始前から指定し、`verify-canonical.py`から`lefthook run test`を一度実行した。TAP・終了コード・必須15fixture・source／runtime前後一致と独立テンプレートgateの結果は次節に記録した。

## 最終検証結果

検証対象HEADは`2f1e0b6e62ba65c0a7807a80024c1c36ca7362ad`。事前の独立code-reviewはStandardsの規約違反／smellとも0件、Specの未実装／部分実装・依頼外追加・誤実装とも0件で、source修正は不要だった。

canonical入口をこのbranchから一度実行し、全1,036件（1,015成功・21既定skip・失敗0）、verifier／runner／commandのexitは全て0。実測1,228.51秒（約20分29秒）。Design Hook13件とPlaywright runtime2件の必須fixtureは15件全てskipなしで成功した。HEAD・全tracked654fileのbytes／mode・13runtime pathの実体／hashは前後一致し、HEAD不一致・証拠照合エラー・中断は0。親もTAPの1–1,036の連番・件数・skip・exit・前後JSON完全一致を独立照合した。

独立テンプレートgateは6/6言語・exit0。全言語で3-system評価、devShell／with-env実行、dotenv／worktree／失敗／output選択、lock不変、raw entryからのdummy test／commit／再起動が成功した。Rust1.99.1はvtable回帰・Cargo test／nextest／clippy／fmt、rust-analyzer2026-10-12の起動を確認した。Gleam1.19.2は既存fixtureでOTP29の`rand:shuffle/1`を使い、devShell／with-envの両方でcompile／runが成功した。追加smokeの準備は既存fixtureの存在確認で停止し、既存gateの実行証拠を採用した。

canonical証拠はこのcheckoutの`tmp/canonical-run.wix1eos4/{before.json,after.json,result.json,runner-path}`、TAP／exitは`tmp/test-run.lTnxM7/`、source-selected6CLIの照合は`tmp/ai-tools-_r0tyc4n/`。独立テンプレートのstdout／exitは`tmp/ai-tools-zf0_vivh/`、共有可能な結果は共通一時directoryの`template-result.json`／`template-startup.log`／`gleam-compile-evidence.log`に保存した。raw内部の証拠は`template-result.json`に所在だけを記録する。関連gate・upstream unit test・独立テンプレートの件数をcanonical全suiteへ合算していない。

全suite後のsource変更は本記録の結果追記だけで、実装・test・依存・検証runtimeは維持する。最終commit前後に本記録以外のtracked内容とruntime実体／hashを照合した。実装・test・依存・検証runtimeが不変のため、同じ全suiteは繰り返していない。sourceの実装・検証・レビュー・commitを完了対象とし、PR公開・merge・live配備は未実施。

canonicalのskipは21件。このうち6言語gate1件相当は上記の独立実行で6/6言語を検証済みで、残る20件は未実行。canonicalの21skipを成功へ数え直していない。ARM Linux／Darwinの実機実行、LSP全機能のprotocol検査、実browserでのImpeccable live mode、APM組織policy enforcement、認証・実モデル等は未検証。Codex0.163.0を含む新AI snapshotはcleanup回帰と適合cache不在で不採用とし、現行snapshot／floor／patchを維持した。

最終結果追記のStandards確認で残っていた未来形とskip内訳の2点を修正した。Spec確認は指摘0件。実装差分と検証結果は変更していない。
