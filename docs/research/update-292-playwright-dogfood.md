---
type: research
title: "Update #292: Playwright and Dogfood adoption"
description: exact npm更新、selected skill、既存Nix browserとWSL実機での互換性検証
tags: [update, playwright, dogfood, nix, evidence]
---

# Update #292: Playwright and Dogfood adoption

2026-09-10。親 [#283](https://github.com/treflebonbon/dotfiles/issues/283) と子 [#292](https://github.com/treflebonbon/dotfiles/issues/292) の本文・全コメントを取得した。comments は両方空。AGENTS.md、docs/conventions.md、docs/architecture.md、runtime/skill-harness.md、ADR-0031/0038/0047 の既存 distribution / browser-free / managed ownership 契約と承認済み TDD seams を使用。

CLI 0.1.19とDogfood 1.63.0、既存Nix browserを解決する最小修正をsourceへ採用した。hostはx86_64 LinuxのWSL2で、通常のWindows CDP経路と、既存のtest seamで明示したLinux native経路を検証した。ARM実機・受入後のlive配備は未実施。全体回帰と最終レビューは[#295](update-295-integrated-acceptance.md)で統合する。

## 固定候補と現行

候補の入口確認は root が保存した tmp/update-283/playwright-candidates-entry.json を正本とし、再 latest 解決していない。native npm lock は指定 exact version から生成した。

| 単位 | 現行 | 候補 / 今回の判断 |
| --- | --- | --- |
| @playwright/cli | 0.1.17 | [0.1.19](https://registry.npmjs.org/@playwright/cli/0.1.19)、既存 buildNpmPackage 経路で採用 |
| CLI 内部 playwright/core | 1.62.0-alpha-1783623505000 | 1.63.0-alpha-2026-08-31。stable CLI 自身の exact dependency をそのまま使用し、独自に stable1.63.0へ置換しない |
| Dogfood playwright/core | 1.59.1 | [1.63.0](https://registry.npmjs.org/playwright/1.63.0)、gitHead 1b025d7e20a026371cd5f98ba0cdce48892737c8 |
| root Nix browser | #286 採用 1.61.1 / Chromium1228 | 維持。Linux nativeでweb/MV3・video/trace PASS |
| user Nix browser | #287 採用 1.59.1 / Chromium1217 | 維持。CLI default・runnerのLinux native起動 PASS |
| WSL Chrome | 既存 Managed Playwright/Dogfood Chrome | 既存 Windows供給・用途別profile・共有排他・CDPのみ。通常browser更新なし |
| managed adapter / close / ownership | 現行の Bash/PowerShell/Node 実装 | コード不変。新CLIと実機で再検証済み |

候補 CLI 内部 client と Dogfood stable client の Chromium metadata はいずれも revision1243。Dogfood baseline/candidate の ffmpeg metadata はともに1011。Node24.19.0 / npm11.17.0 で native lock と frozen install を検証し、共通 Node24を維持する。

CLI tarball integrity: sha512-eGXIsYa5D+dC6wHGf+9uEislhPGip1djK+yiNAD7BVsXN3WzzR1J4ClFAhYhyu7wSEFqhcPrqXAYeBJF1dKJ7A==。Dogfood playwright tarball integrity: sha512-+7ziBLidS4NaNCdt57SUDT+wYmmd5fmiQejUic/kb+YsYSCPyOOE9sebzMjNmQrsnNpDJqd4WHvV/8lfKfUDUg==。

## Native npm evidence

- CLI npmDepsHash: sha256-koaZHHqnURkdRPICXo8kyIbFFpsWnf7+R3nbgQJ3Bl0=。既存 prefetch-npm-deps0.1.0 で算出。実 fixed-output Nix buildはdefault/WSL両方PASS。
- CLI package-lock.json SHA256: 884af7693bfeb4dee5b2614d72169cbf31eb985c908a8207b1e32d463132b94a。
- Dogfood package-lock.json SHA256: 158ec0dc06920f128f22132ff556adc59003b5b26b3e1244c640b6c89e31976d。
- PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1、隔離 HOME/cache、npm install --package-lock-only --ignore-scripts --no-audit --no-fund で native lock を生成。npm ci --ignore-scripts --no-audit --no-fund の前後で両 lock hash が不変。browser install コマンドは実行していない。
- CLI version/help、open --help、show --help は baseline/candidate 全8呼出し成功。open/show の公開 help は同一。全体 help は upload の可変引数表記と recording-start/stop の追加のみ。実open/show/annotationは後述のhost検証で成功。

## Selected CLI patch と skill payload

playwright-core/lib/tools/cli-client/program.js の既存 substituteInPlace 対象は候補でも1件一致する。PWTEST_CLI_MANAGED_CHROME=1 のときだけ open の goto を tab-new に置換する既存1行 patch を変更せず維持できる。patched program の node --check が成功。実CLI/CDPでも、open前の全page ID・URLが保たれ新規タブが1枚増えることを確認した。

default package が使う PWTEST_CLI_GLOBAL_CONFIG と .playwright/cli.config.json の解決は候補 coreBundle.js に残っている。Nix package の explicit executablePath、WSL variant の browser-driver=null、wrapper からの PLAYWRIGHT_BROWSERS_PATH/PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD の unset、symlinkによる skill 配布は不変。

配布対象10ファイルを baseline/candidate で比較。実差分は次の2ファイルのみ。

- SKILL.md: recording-start/recording-stop の公開コマンド説明を5行追加。
- references/tracing.md: traces/ という説明を .playwright-cli/traces/ に訂正。

他8ファイルは不変。既存 playwright-cli-wsl-skill.md を同じ手順で追記した selected-skill/ を作成し、manifest と diff を保存した。APM はこの skill の所有者ではなく、APM担当の lock/payloadとは独立。新しい操作 workflow を組み込む変更はない。

## Native runner の不一致と最小修正

公開 API chromium.executablePath() とファイル存在確認だけを使い、実 npm baseline/candidate の解決結果を比較した。この不一致の診断時点ではChromeを起動せず、修正後に両bundleとの実接続を検証した。

| supplied bundle fixture | baseline1.59.1 の解決 | candidate1.63.0 の解決 |
| --- | --- | --- |
| Chromium1217 | chromium-1217 / exists=true | chromium-1243 / exists=false |
| Chromium1228 | chromium-1217 / exists=false | chromium-1243 / exists=false |

単なる npm pin 更新では user defaultを壊し、現行runnerも更新済みroot browserとは不一致になる。したがって runner の native launch 分岐内だけで、既存 PLAYWRIGHT_BROWSERS_PATH にある Chromium executable を選ぶ修正を採用した。

- Linux x86_64 の chrome-linux64/chrome、Linux arm64 の chrome-linux/chrome、Apple Silicon の Chrome for Testing layout を扱い、Nix bundleの symlink を追う。
- Chromiumが一意で実行可能なファイルである場合だけ launchPersistentContext の executablePath に渡す。不在・曖昧・アクセス失敗は既存 result の startup failure として報告し、別 browserを起動しない。
- PLAYWRIGHT_BROWSERS_PATH 未設定、または upstreamのhermetic指定0では通常の Playwright解決を維持する。
- managedDogfood が得られた WSL branch はこの解決処理を通らず、既存 connectOverCDP/context/viewport/ownershipを維持する。
- channel chromium、headless/headed選択、persistent profile、extension launch引数、service worker確認、annotation、video/trace、終了処理は変更しない。

固定nixpkgs 2版×3 systemの一次package定義と実ZIP一覧を照合し、3 layoutが一致した。root ARM Linuxの配布サーバーがRangeを拒否したため、その1件だけ同じ固定ZIP全体を取得して一覧を確認した。Apple Siliconの両固定assetはChrome for Testingで、Chromium.app fallbackは不要。archive/layoutの確認とARM実機起動は区別する。hostでは1.63 clientとChromium1217/1228のweb/MV3各2件がexit0となり、screenshot・trace・storage・console・network・確定videoとextension IDを保存できた。

## TDD / quality evidence

既存 tests/dogfood-results.bats とその Playwright境界adapterを使い、公開runner実行から報告結果まで確認した。内部呼出順やversion定数を写すテストは追加していない。

1. candidate pinのみのrunnerに対し、供給された異なるrevisionの実行パスを渡す契約が失敗する red を記録。
2. native分岐の修正後、供給bundleを通じた起動・report/evidenceが green。
3. 3種類のlayoutをsymlink経由で渡すcase、不在bundleから別browserへ進まないcaseを含め、既存16件＋新規2件が18/18 PASS。
4. scoped oxfmt と oxlint を実行。初回lintのawait/regexp/style指摘を修正し、最終lint成功。変更したrunner/fixtureの構文確認も実施する。

rootは既存の所有権・WSL adapter・runner contractを合わせた107件を実行し、107/107 PASSを確認した。実Chromeを使うDogfood統合テストは同じ新CLIとNode24.19.0で実行する。

## 準備物と適用範囲

- private_dot_config/nix-devshell/packages/playwright-cli.nix: versionとnpmDepsHashのみ。
- 同 playwright-cli-agent/package.json、package-lock.json: exact CLI候補のnative lock。
- local-skills/dogfood-to-issues/references/package.json、package-lock.json: exact runner1.63.0。
- 同 playwright-dogfood-runner.mjs: native executable解決だけ。
- 同 mv3-extension.md: 現行pinとbrowser供給の説明を整合。
- tests/dogfood-results.bats、tests/fixtures/dogfood-playwright.mjs: 上記公開seamの2case。
- docs/research/update-292-playwright-dogfood.md: 本準備記録。

共有 `tests/nix-devshell.bats` の旧版期待値を0.1.19へ整合し、配布経路・WSL wrapper・skill symlinkのassertionを保持した。既存のmanaged adapter・所有権・終了処理の実装は変更していない。

## 採用後の検証

| gate | 結果・証跡（`tmp/update-283/`） |
| --- | --- |
| exact候補 / native npm frozen no-rewrite | PASS、上記lock/hash。source採用後も同bytes |
| Nix-installed selected skill | 10/10ファイルが固定候補＋既存WSL追記と一致、`playwright-installed-skill.json` |
| CLI default/WSL × 3 system | 評価PASS、`playwright-candidate-all-systems.json`。実source全6 shellのflake checkもPASS |
| host default/WSL package build | PASS、`playwright-candidate-host-build.json`、既存npmDepsHashとmanaged-tab patchが有効 |
| source host WSL build | PASS、`playwright-source-wsl-build.json` |
| WSL packageのbrowser非収録 | 4 browser packageをclosureに含まない、`playwright-wsl-closure.txt` |
| 固定browser archive layout | 6/6一致、`292-fixed-archive-layouts/results.json` |
| default CLI + Chromium1217 | open/eval/snapshot/screenshot/trace/tab/close PASS、`playwright-cli-native/results.json` |
| native runner + Chromium1217/1228 | web/MV3の4/4、video/traceを含む全成果物PASS、`playwright-native/results.json` |
| WSL CLI headless | 操作・終了、headedへの不正切替と別session競合の拒否PASS、`playwright-cli-wsl/results.json` |
| WSL CLI headed / Dashboard | show、新規openの既存tab保持、annotation送信、CLI終了後のDashboard保持と最後のconsumer終了PASS、`playwright-cli-wsl-headed/` |
| 実Dogfood統合 | 14/14 PASS、新CLI・Node24.19、`playwright-real-dogfood.log`。web/MV3・annotation attachment・失敗時の証拠確定を確認 |
| 所有権・adapter・runner contract | 107/107 PASS、`playwright-related-contracts.log` |
| full Bats / final review | [#295](update-295-integrated-acceptance.md)。最終full658実行PASS・20skip・1環境失敗（exit1）、Standards規約違反0/smell0、Spec0 |
| ARM実機 / live配備 | 未実施。ARMホストなし、liveは受入・merge後 |

実headed検証ではDashboardの通常UIから検証用feedbackを送信し、CLIが同文言とannotation画像を返した。描画modal内の「Done annotating」を経由してから「Submit」を操作する。最初の確認操作はmodal背後をクリックしtimeoutしたが、この正規操作で成功したため製品コードの変更は不要だった。managed ownershipは検証の前後にnullを確認し、通常Chrome profileや別consumerには触れていない。

native検証はWSLホスト上で既存の `PWCLI_TEST_WSL=0` / `DOGFOOD_TEST_WSL=0` を明示した互換性probeであり、通常WSL利用をLinux browserへ切り替える配備ではない。通常WSLはWindows供給ChromeをCDPで利用し、Dogfoodは1440×1000、video非取得の既存契約を維持する。

Scratch: /tmp/nix-shell.2VWWVm/nix-shell.faRWAp/update-292-preparation._uqun8w7

Evidence: upstream/playwright-candidates-entry.json、upstream/selected-skill-diff.patch、upstream/selected-skill-manifest.json、upstream/managed-patch-evidence.json、logs/native-frozen-installs.json、logs/cli-version-help.json、logs/native-revision-resolution.json、logs/dogfood-native-bundle-red.log、logs/dogfood-native-bundle-green.log、logs/dogfood-results-final.log、logs/scoped-oxlint-green.log。
