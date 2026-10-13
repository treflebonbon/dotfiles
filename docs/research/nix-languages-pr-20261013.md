# 一般Nix／6言語テンプレート後続PR（2026-10-13）

## 現在の依頼と範囲

承認済みの推奨案と正式引継ぎに基づき、一般Nix入力と6言語テンプレートを一つの更新単位として実装・実build／独立生成・関連検証・2軸レビュー・canonical全Bats・commit・topic push・通常PR作成まで行う。checkoutは `/home/ubuntu/orca/workspaces/dotfiles/update-nix-languages-20261013`、branchは `dev/update-nix-languages-20261013`、開始HEAD／期待baseは `eda7cdb5b7f2ed5840ff709505388e9a6f5686e8`。physical root・branch・HEAD・clean・worktree Git dir・common dirとpointerの整合を自身で確認済み。merge／live applyは行わない。

読み取り参考は保留成果 `864880c0498d9b274c506183a2087f0863d674f7` とその `docs/research/update-tools-skills-20261011.md`。参照checkoutは編集せず、過去の成功を今回branchの結果へ転記しない。候補はunstable／language source `7fd4004d0511991fff3a0524856a9be09e28c5f0` とuser stable `240fddad86d7a0520319f21d8be1b43db426b18d` に固定し、別のlatestを追わない。

当初予定sourceはroot `flake.lock`、`private_dot_config/nix-devshell/{flake.nix,flake.lock}`、`templates/{bun,elixir,gleam,go,perl,rust}/flake.nix`、`templates/{go,rust}/DEVELOPMENT.md` の11 file。Gleamは既存language sourceパターンへ合わせ、Rust selector 1.99.0とGo 1.27.2の説明を実採用版へ揃える。metadata比較でrepo Node.jsの取得元だけ旧stable revisionに残ることを確認したため、architectureの同じstable revisionを使う規約に従いroot `flake.nix` の `nixpkgs-node-sources` とlockも承認済みstable候補へ揃える。Node.js 24.21.0の版は変わらない。最終sourceは12 file。`docs/architecture.md` はGleam取得元の説明だけを更新する。本記録と既存5分割記録には対応先だけを追記する。

## 適用規約と検証境界

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) Decision 1–4の更新単位・互換性ゲート・rollback境界、[conventions](../conventions.md#言語バージョンの更新) の公式安定版／Nix実解決／lint・LSPの照合と独立展開、同文書の更新追跡・レビュー規約を適用する。[architecture](../architecture.md#per-repo-言語テンプレート) の共通with-envと取得元、[skill-harness](../../runtime/skill-harness.md#worktree-の開始と復旧) の同checkout継続、[ADR-0038](../adr/0038-keep-wsl2-browser-free.md) のWSL browser-freeを維持する。Codexの品質floor・direct output・cleanup patchとpublic/trust境界は変更しない。

root／userの全packageと6言語のbase／candidate metadata、3 system評価、Linux実devShell／package buildと必要CLI起動を確認する。既存 `tests/helpers/template-with-env.py` でHOME／全XDGを隔離した全6言語の独立生成・固定入力lock・devShell／with-env・compile／test／lint／LSP・dotenv／worktree／失敗／output選択・dummy raw adapterを検証する。ARM Linux／Darwinは評価のみと実機成功を区別する。認証・実モデルは有効化しない。

関連検証とcommit済み差分のStandards／Specレビュー・指摘修正・親の最終確認後、source-selected user／repo両wsl devShellをshellHookより前から隔離する。6AI CLIのoutput／実起動を照合し、候補Playwright browser-free outputと採用Impeccable 4.5.2／engine 0.1.14のfrozen runtimeを開始前から指定してcanonical `lefthook run test` を一度実行する。TAP plan・連続番号・bailout・pass／skip／fail・exitと全tracked sourceの前後一致を保存する。関連gateと全suite件数を合算せず、結果文書だけの追記では反復しない。

今回のGit管理外証拠は `tmp/nix-languages-20261013/` に置く。実行中TAP／language evidenceのpathとexit／最終JSONを記録し、前のログは保持する。

## 元差分から外した変更の追跡

開始HEADと保留成果の全46 file差分を照合した。元差分の11 source fileを採用候補とし、architectureのGleam説明だけを選択する。root Node取得元の整合は上述の追加1 fileへ記録した。残るfileと同file内の残差分は以下に追跡する。

| 外したfile／部分 | 扱い・理由・対応先・状態 |
| --- | --- |
| `apm.lock.yaml`、`tests/apm-runtime.bats` | PR #398–400の採用済みnative metadata／期待値を維持。保留成果への置換は採用しない。manifest／lock pairは不変。 |
| `docs/adr/0045-separate-llm-agents-and-apm-update-units.md`、`runtime/ai-runtimes.md` | PR #397のsnapshot／cleanup判断を維持。古い統合記録参照への巻戻しは採用しない。 |
| `docs/adr/0070-adopt-gpt-6-1-sol.md`、`private_dot_config/codex/AGENTS.md`、`private_dot_config/codex/config.toml.tmpl`、`tests/codex-config.bats`、`tests/helpers/fake-raw-codex-app-server.py`、`tests/helpers/raw-codex-handoff.py`、`tests/raw-codex-integration.bats` | PR #401の親gpt-6.1-sol／xhigh・子gpt-6-luna／xhighとhandoff契約を維持。referenceへ戻す差分は採用しない。 |
| `docs/research/{tool-snapshot,ordinary-apm,impeccable,mattpocock,fixed-cli}-pr-20261013.md` | 元差分の削除は採用せず、今回対応先を追記する。PR #397–402のmerge・配備済みはユーザーの引継ぎに基づく。 |
| `private_dot_config/nix-devshell/packages/gwq.nix` | PR #402の採用hashを維持。referenceのhashへの巻戻しは採用しない。一般Nix変更で実buildに修正が必要なら取得根拠とともに最小修正する。 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package-lock.json`、`private_dot_config/nix-devshell/packages/playwright-cli.nix` | PR #402 Review Roundの公式registry URL3件／npmDepsHashを維持。referenceのmirrorには戻さず、今回入力で実build／配布fixtureを検証する。 |
| `tests/nix-devshell.bats` | PR #397のsnapshot記録参照を維持。referenceの統合記録参照への置換は採用しない。 |
| `package.json`、`bun.lock` | root npm依存の別単位として保留していた。2026-10-14に独立更新し、[今回の記録](root-npm-pr-20261014.md)へ移管。[通常PR #404](https://github.com/treflebonbon/dotfiles/pull/404)、branch `dev/update-root-npm-20261014`、未merge・未配備。 |
| `local-skills/domain-modeling-studio/package.json`、`local-skills/domain-modeling-studio/package-lock.json`、`local-skills/domain-modeling-studio/dist/studio.html`、`local-skills/domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` | studio依存・生成物の別単位として保留。対応先PR未定・未配備。 |
| `scripts/verify-ai-tools.py`、`scripts/verify-apm-deployment.mjs`、`tests/verify-ai-tools.bats`、`tests/verify-apm-deployment.bats` | 汎用検証helper配布・testsは別単位として保留。必要な補助だけGit管理外へ読み取り取得し、今回PRへ追加しない。 |
| `docs/architecture.md` のCodex説明・参照変更、`docs/conventions.md`、`runtime/skill-harness.md` | 現在baseの採用済みcleanup記録／規約を維持。helper案内はhelper単位へ保留。Gleam説明だけ今回採用。 |
| `docs/research/braces-response-20261013.md`、`docs/research/update-tools-skills-20261011.md` | 保留成果内の参考履歴を読み取り専用で保持。braces advisory判断は別単位へ保留、今回は変更しない。今回実測は本記録へ保存する。 |

今回のPR公開と更新全体の完了は区別する。root npm／studio／汎用helper等は保留成果 `864880c` に残り、対応先未定のため更新全体は未完了である。

## このbranch自身の採用確認と実検証

公式APIで固定候補のcommitとstable releaseを確認した。unstableは2026-10-11 15:54:36 UTC、stableは同日00:25:25 UTCのcommitで、別のlatestへ更新していない。root／userのnative lock生成後、変更nodeはrootの `nixpkgs`／`nixpkgs-node-sources` とuserの共有 `nixpkgs_2`／`nixpkgs-language-sources` だけ。候補外node、llm-agents snapshot／品質floor／Codex cleanup patch、APM pair、固定CLIの版／hash／公式registry URL、Codex管理設定は開始HEADから不変である（`lock-invariants.json`）。

| 環境・対象 | 開始HEAD | 採用候補・判断 |
| --- | --- | --- |
| repo chezmoi | 2.72.2 | [安定版2.73.0](https://github.com/twpayne/chezmoi/releases/tag/v2.73.0) |
| repo lefthook | 2.1.14 | [安定版2.1.15](https://github.com/evilmartians/lefthook/releases/tag/v2.1.15) |
| repo pinact | 4.1.1 | [安定版5.0.0](https://github.com/suzuki-shunsuke/pinact/releases/tag/v5.0.0)。既存callerの互換性を下記fixtureで確認 |
| user gh | 2.101.0 | [安定版2.102.0](https://github.com/cli/cli/releases/tag/v2.102.0) |
| repo／user Node.js | 24.21.0 | 版を維持し、取得元・3 systemのversion／drv／outputを一致させる |
| 汎用Python／Bun | 3.14.7／1.4.2 | 版を維持。[Bun 1.4.3](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.3) は候補取得元に未収録のため新規取得経路を追加せず却下 |
| user Codex／APM／Herdr | 0.162.1／0.33.0／0.9.3 | 3 systemの全metadata不変。パッチ付きCodex direct outputを再利用し、Rust source buildは不要 |

root全package（各system default18／wsl17）とuser全package（Linux default81／wsl80、Darwin default78／wsl77）のname／version／drv／outputをbase／candidateで比較した。構成は不変、版変更は上記4ツールだけ。rootは全output、userはdirect Codex／APM／Herdr以外のoutputが変わる。同版outputの変更は一般Nix取得元の更新によりconsumer側package set／stdenv／依存が進むためで、AI snapshotや固定CLIの版変更ではない。overlayを使うClaude／Copilot／Antigravityと固定CLIも今回outputで確認する（`{repo,user}-{base,candidate}-metadata.json`、`shell-metadata-comparison.json`）。

### pinact major更新の互換性

公式v5 releaseと候補binary内のupgrade guideを確認した。CLIはCobraへ移行し、単一dashの長いflagが非互換になる。Go module pathと文書pathの変更もあるが、既存caller `lefthook.yml` の `pinact run {staged_files}` はflagを使わず、ライブラリimport／go install／旧文書pathにも依存しない。

HOME／全XDGを隔離した二つのGit fixtureで、実4.1.1／5.0.0を使い `pinact run .github/workflows/fixture.yml` を実行した。両方exit 0で、`actions/checkout@v5` が同じ `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0` に固定された。再実行もexit 0・file不変。live workflow全fileと `lefthook.yml` の前後SHA-256も一致し、live workflowの書換えは行わない。Git管理外の証拠は `pinact-{base,candidate}-compat.log`、`pinact-compat-result.json`。新しいskillやcallerの書換えは追加しない。

### Linux buildと関連検証

root／user両flakeの3 system `flake check --no-build --all-systems` が成功した。Node取得元を揃えた後のrootも再評価した。x86_64-linuxのroot／user wsl devShellとroot `with-env` は実Nix buildが成功し、source-selected user／repo devShellをshellHookより前からHOME／全XDGで隔離して起動した（`linux-build.{json,log,exit}`）。ARM Linux／Darwinは評価のみで実機実行ではない。

6AI CLIの候補output／実起動一致、chezmoi 2.73.0／lefthook 2.1.15／pinact 5.0.0／gh 2.102.0／Node.js 24.21.0／Python 3.14.7／Bun 1.4.2／Playwright 0.1.22のversion、pinact runとPlaywrightのhelpを確認した。候補Playwright outputは `/nix/store/r1mia04ilacqdfh4blbgb3hibpjsclap-playwright-cli-0.1.22`。公式registry URLとnpmDepsHashはbaseのままで実buildを通過し、追加hash修正は不要だった（`tools-smoke.log`、`related-environment.json`）。

関連Batsは89件、89通過・skip 0・失敗0・exit 0。TAP plan／連続番号／bailoutなしを照合した。nix-devshell、品質floor、Codex cleanup、候補Playwrightの実配布保護／共有FD・lock、devshell-env、Claude devShell、実Design Hookを含む。root frozen install／型検査、変更Markdown／Nixのformatと `git diff --check` も成功した（`related-result.json`、`related.tap`、`root-frozen-type-format.log`）。

全suite用の既存frozen runtime `/tmp/fixed-clis-apm.mHuaBN` は現在のAPM manifest／lockとbyte一致し、20 dependencyの全metadata・全配備bytes・両target各46 skill・追加0／削除0を読み取り照合した。Impeccable skill 4.5.2とsource-selected engine 0.1.14、実launcherのhashが一致した（`apm-runtime-verification.log`）。APM再解決やlive配備は行わない。既存runtimeでの過去audit結果を今回のaudit成功へ転記せず、組織policy enforcementも今回実行したとは扱わない。

同版outputが変わる固定CLIも、今回のsource-selected隔離devShellでgwq 0.1.2／waza 0.38.10／gws 0.22.5／Playwright 0.1.22のoutput／version／help一致を確認した。flyline 1.9.0の候補loadableは `/nix/store/691gqmlic42ikjmparbkqap3cf19l7qz-flyline-1.9.0/lib/libflyline.so`。Ubuntu `/usr/bin/bash` 5.2.21と候補stableのNix bash-interactive 5.3.9の双方で実対話TTYのstdin／stdout、load／version／mouse設定／Ctrl-G bindingがexit 0で通過した（`fixed-cli-smoke-result.json`、`flyline-tty-result.json`）。先行PRの成功を今回outputの成功に代用していない。

### 全6言語の独立生成

現在の `tests/helpers/template-with-env.py` をsource-selected user／repo両wsl devShellから実行した。検証用の浮動nixpkgsは承認済みstable `240fddad86d7a0520319f21d8be1b43db426b18d`、rust-overlayは候補取得元の日時に合わせ2026-10-12 00:00 UTC以前のcommit `c1cfa7a2c809d364ac1a7e9b3ec418afa3f19793` に固定した。テンプレート自身のchannel URLや取得経路を変更する指定ではない。base／candidateの言語metadata比較でも同じ二つの検証入力を使い、浮動channelのdriftを言語source更新の差分に混同しない。

| テンプレート | 開始sourceでの解決 | 今回の解決・採否 |
| --- | --- | --- |
| Go | 1.27.1、gopls 0.23.0、golangci-lint 2.14.0 | [安定版1.27.2](https://go.dev/dl/) を採用。gopls／lintの版は維持し、両方をGo 1.27.2でbuildした実outputとcompilerの互換性を確認 |
| Rust | 1.98.1、rust-analyzer 2026-09-21 | [安定版1.99.0](https://github.com/rust-lang/rust/releases/tag/1.99.0) と [rust-analyzer 2026-10-05](https://github.com/rust-lang/rust-analyzer/releases/tag/2026-10-05) を採用 |
| Elixir | 1.20.4、OTP 29.1.1、Expert 0.1.10 | 本体／OTPを維持し、[Expert 0.1.11](https://github.com/expert-lsp/expert/releases/tag/v0.1.11) を採用 |
| Perl | 5.42.3、PerlNavigator 0.6.3 | 維持。[公式5.44.0 tag](https://github.com/Perl/perl5/tree/v5.44.0) は候補取得元に未収録のため、新しい配布経路は追加せず却下 |
| Gleam | 共有channelの1.18.1、OTP 29.1.1 | language sourceの1.19.1を採用。OTPは維持。[公式1.19.2](https://github.com/gleam-lang/gleam/releases/tag/v1.19.2) は取得元に未収録のため却下 |
| Bun | 1.4.2、TypeScript language server 5.3.0 | 維持。1.4.3は取得元未収録のため却下 |

6言語の全package metadataを3 systemで比較し、構成はGo15／Rust7／Elixir4／Perl3／Gleam3／Bun3 packageで不変。版変更は表の本体／LSPだけで、他の版は不変だった（`language-{base,candidate}-metadata.json`、`language-metadata-comparison.json`）。共通with-envの検証済みrevision `63e47ffc471ff5e01f58a8a268ea553b0c9ab976` とpublic／trust境界は維持した。

実Nixの独立ゲートはBats 1/1・6/6言語・skip 0・失敗0・gate／launcher exit 0。全言語で独立生成lock、3 system flake評価、devShell／公開with-env、dotenv／linked worktree／失敗／output選択／lock不変と、実raw entryからのdummy test／commit／再起動を通過した。HOME／全XDGと各言語cacheは隔離した。Codexの実モデルや認証は有効化していない。evidenceは `/tmp/nl-20261013.RX4lMU/nix-shell.rrV79t/nix-shell.dFIqpa/template-with-env-258-_jvdlb3v`、TAPは `tmp/nix-languages-20261013/language.tap`、実行コマンドは同directoryの `language-commands.log`、最終JSONは `language-result.json`。生成した6組のsource／lockも `generated-sources/` に保存した。

Goの実test／gopls check／golangci-lint、Rustのvtable／offline Cargo test／nextest／clippy／fmt、GleamとOTP29の実compile／runが成功した。lintのbuild versionとgoplsの `go version -m` はともにGo 1.27.2で、compilerの版と一致した（`go-lsp-build-info.log`）。Expertのhelp、PerlNavigatorの診断なしEOF exit 1、BunのLSP versionも確認した。LSP全機能のprotocol検査を実施したとは扱わない。

同じ生成repoを使い、Elixirの実elixirc／ExUnit、Perlの構文検査／Test::More、Bunのtest／build／生成JS実行も隔離HOME／全XDGで成功し、各lockは不変だった（`language-extra-smoke-result.json`、`{elixir,perl,bun}-compile-test.log`）。独立ゲートや追加smokeの件数は後段のcanonical全suiteへ合算しない。

## レビュー・canonical全suite・公開境界

実装commitは `dd7cf2010b3d45dc855df6cd99b7af205d9d8a00`。同commitの独立code-reviewはStandards 0件／Spec 0件。初回Specの除外台帳指摘は、参照成果への三点比較で古いmerge-baseを使ったことが原因で撤回された。元差分の二点比較46 fileと指摘10 pathの同一blobを親・Spec reviewerが独立照合し、source修正はなかった（`review-result.json`、`reference-diff-audit.json`）。レビュー子にはユーザー指定のgpt-6-luna／xhighを指定した。親は同commitのsource差分・Node整合・追跡・今回実検証を読み取り照合し、両軸の未解決0件とsource／test／依存維持を条件に最終確認を完了した（`parent-confirmation.json`）。

同commitのcanonical `lefthook run test` は一度実行し、769件（748 pass／21 skip／0 fail）、runner／canonical／launcher exit 0、942.5秒で成功した。TAP planは1つ、1–769の連続番号・bailoutなしを照合し、579 tracked fileの実行前後SHA-256も全て一致した。親もTAP・exit・source不変・時間を独立照合した。旧成果の769／787件や、今回の関連89件／6言語gate／追加smokeをこの通過数へ合算していない。

開始前から `TEST_PLAYWRIGHT_PACKAGE=/nix/store/r1mia04ilacqdfh4blbgb3hibpjsclap-playwright-cli-0.1.22` と `IMPECCABLE_HOOK_RUNTIME=/tmp/fixed-clis-apm.mHuaBN/.agents/skills/impeccable/scripts/impeccable`、source-selected engineを固定した。user／repo両wsl devShellのshellHookより前からHOME／全XDGを隔離し、6AI CLIの候補output／実版を照合した。実Design Hook13件と候補Playwrightの実配布保護／共有FD・lock fixtureは全suite内で通過し、runtime／package未指定によるskipはない。

21 skipは実Herdr、Bash 3.2、実モデル／認証付きGitHub／MCP、専用隔離runtime／public dependency gateway、6言語独立生成、public Nix appの既定opt-in。6言語は上記の独立gateだけを実行済みと扱う。ARM Linux／Darwin実機とLSP全機能のprotocol検査、認証／実モデル等は今回未実施である。

証拠は `tmp/test-run.uqvfEW/{tap.log,setup.log,environment,exit-code}`、`tmp/nix-languages-20261013/{full-result,canonical-source-before,canonical-source-check,canonical-environment,canonical-ai-version-check}.json`、`canonical{,-launch}.exit`、`canonical-output.log`、`current-tap-path`、隔離AI runtime `tmp/ai-tools-k0g3zhdc/`。前の成果logsと参照checkout `864880c` は保持した。

環境間の既存版差も全package metadataに保存した。repo／userのlefthookは2.1.15／2.1.5、pinactは5.0.0／3.9.2、oxfmtは0.68.0／0.45.0で、リポジトリ編集用と汎用環境の取得元を区別する。root npm lockのoxfmt 0.67.0等は別の保留単位として維持した。今回必要なNode.js 24.21.0は両環境で取得元・版・outputを一致させ、既存callerのpinact検証はrepo側5.0.0で行った。

成功後の変更は今回結果・対応先の文書だけ。実行source／test／Nix・lock／依存／検証環境を維持し、結果文書の追記だけでは全suiteを反復しない。最終記録と日本語3節のPR本文を確認し、commit／clean後に `git-push-topic` で同topicを非force公開して、実remote default `main` 向けの通常PRを作成する。Codexのsource build不要は今回の既存output再利用に限り、未キャッシュ環境のsource build要件は残る。merge／live applyはユーザー担当。root npm／studio／汎用helper等の残保留があるため、更新全体は未完了である。

公開結果: [一般Nix／6言語後続PR #403](https://github.com/treflebonbon/dotfiles/pull/403) を `main` 向けのOPEN・非draft通常PRとして作成した。実装commit `dd7cf20`、検証記録commit `c8cb1bc` を同topic `dev/update-nix-languages-20261013` から `git-push-topic` で非force公開し、作成時のlocal／upstream／PR HEAD `c8cb1bc6db5d9a4298667976e9af08404b54bb26` と英語Conventional title／確定日本語本文の一致を確認した。親もPR状態／本文／CIを独立照合した。公開対応先の追記だけを文書commitとして公開し、実行sourceは維持する。

CIの `scan-pr / osv-scan` はSUCCESS、`osv-scanner` はNEUTRAL。check-run `115366083329` のsummaryはmainの `osv-scanner-full.yml` 構成がPR側で見つからず、新規alertsを判定できないという警告で、annotationsは0件。前者の実行成功と後者の判定制限を区別し、新規alertsなしと報告しない。親はPR #402でも同じSUCCESS＋NEUTRALを確認している。今回workflowは変更しておらず、CI設定修正は範囲へ追加しない（`osv-check-run-initial.json`、`pr-created.json`）。merge／live applyはユーザー担当で未実施、残保留と更新全体の未完了状態は維持する。
