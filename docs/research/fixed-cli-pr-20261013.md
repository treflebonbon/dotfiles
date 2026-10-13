# 固定CLI後続PR（2026-10-13）

## 現在の依頼と範囲

ユーザーの明示した `implement` と正式引継ぎに基づき、保留成果から固定CLI4件を独立PRへ分割する。同じnative checkout `/home/ubuntu/orca/workspaces/dotfiles/update-fixed-clis-20261013`、branch `dev/update-fixed-clis-20261013`、開始HEAD `31969aa1dca1e7b45be7992083ca8570a5ea2dd2` で、実装・Linux実build／起動・関連検証・2軸レビュー・canonical全Bats・commit・`git-push-topic`・PR作成まで行う。開始時のphysical root・branch・HEAD・clean・worktree Git dir・common dirは自身で確認済み。merge／`chezmoi apply` は対象外。

読み取り参考は統合成果 `864880c0498d9b274c506183a2087f0863d674f7` と同checkoutの `docs/research/update-tools-skills-20261011.md`。過去の採否・検証は参考資料とし、このbranch自身の成功へ転記しない。新しいlatestを追わず、一般Nix入力の更新で互換性問題を解決しない。

| 対象           | 開始HEAD | 固定候補 |
| -------------- | -------- | -------- |
| flyline        | 1.8.0    | 1.9.0    |
| gwq            | 0.1.1    | 0.1.2    |
| waza           | 0.38.7   | 0.38.10  |
| Playwright CLI | 0.1.19   | 0.1.22   |

予定変更は `private_dot_config/nix-devshell/packages/{flyline,gwq,waza,playwright-cli}.nix`、`playwright-cli-agent/{package.json,package-lock.json}`、`tests/nix-devshell.bats` のPlaywright exact版期待値、本記録と既存4分割記録への追跡追記。pin／hash／文書には既存fixtureと実成果物を使用し、新logic／汎用helper配布は追加しない。

## 適用規約と検証境界

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) Decision 1–4の更新単位・互換性ゲート・rollback境界の分離を適用し、先行Snapshot／通常APM／Impeccable／Mattは維持する。[ADR-0021](../adr/0021-replace-blesh-with-flyline.md) のLinux glibc loadable、bashのline editor／履歴所有者、warning-only fallbackを維持する。[ADR-0038](../adr/0038-keep-wsl2-browser-free.md) Decision 1–4／7のbrowser-freeとno-fallback、[ADR-0047](../adr/0047-centralize-managed-chrome-ownership.md) の停止確認・未確定起動保持・世代照合、[ADR-0059](../adr/0059-scope-browser-ownership-and-share-attachments.md) のworktree別identity／registry／socketと共有所有権を維持する。各ADRの過去migration完了条件は、変更していない全ブラウザ機能の再実装依頼へ広げない。

root／user flakeの3 system評価、4CLIのx86_64-linux実Nix build、version／help、gwqのbash／fish／zsh completion生成、wazaのオフラインsmoke、flylineのUbuntu `/usr/bin/bash` とNix bash-interactiveによる対話TTY load／enableを確認する。非対話shellやreadlineを持たない通常Nix bashの失敗は成功として扱わない。flylineは既存どおりLinuxだけに供給し、ARM／Darwinの評価と実機実行を区別する。

`TEST_PLAYWRIGHT_PACKAGE` に候補のbrowser-free Nix outputを明示して `tests/playwright-runtime.bats` の実配布保護／共有FD・lock fixtureを実行する。HOMEと全XDGはdevShellのshellHookより先に隔離し、source-selected user／repo devShellの6AI CLI outputと実起動を照合する。npm導入版は公式公開時刻と7日待機規則を照合する。実ブラウザ操作が必要な場合は候補package内のManaged Chrome所有権を再利用し、既存consumerを停止せず、browser bundleを混在させない。

関連Bats／root型検査／変更file format／diff checkを終え、commit済み差分を開始HEADからStandards／Specへ渡す。両軸には現在要件・ADR箇所・予定scope・下表の除外差分・参考資料の区別を渡す。指摘修正と親の最終確認後、このbranch自身で `lefthook run test` を一度実行し、TAP plan・連続番号・pass／skip／fail・exitを保存する。全suite開始前から候補Playwright outputと採用中Impeccable 4.5.2／engine 0.1.14の実runtimeを指定する。既定opt-inはskipを維持し、別gate結果を合算しない。成功後の結果追記だけでは全suiteを反復しない。

## 元差分から外した変更の追跡

開始HEADと統合成果の41 file差分を照合する。今回の6 package fileは採用、`tests/nix-devshell.bats` は版期待値2行だけ採用し、Snapshot記録参照を統合記録へ戻す差分は採用しない。残る34 fileは以下のとおり。同file内の残差分も区別し、保留成果の参照checkoutは編集しない。

| 外したfile／部分 | 扱い・対応先・状態 |
| --- | --- |
| `apm.lock.yaml`、`tests/apm-runtime.bats` | PR #398–400の採用済みnative metadata／期待値を維持。統合成果への置換は採用しない。APM manifestも不変。 |
| `docs/adr/0045-separate-llm-agents-and-apm-update-units.md`、`runtime/ai-runtimes.md` | PR #397の採用snapshot／cleanup判断を維持。統合成果の古い記録への置換は採用しない。一般Nix等の残説明は保留。 |
| `docs/research/tool-snapshot-pr-20261013.md`、`docs/research/ordinary-apm-pr-20261013.md`、`docs/research/impeccable-pr-20261013.md`、`docs/research/mattpocock-pr-20261013.md` | 元差分の削除は採用せず、履歴を保持して本単位の対応先だけ追記する。先行PR #397–400はmerge済み、配備済みはユーザー／親の引継ぎに基づく。 |
| `flake.lock`、`private_dot_config/nix-devshell/flake.lock`、`private_dot_config/nix-devshell/flake.nix` | 一般Nix・言語取得元の単位へ保留。後続PR未作成・未配備。既存AI snapshotは維持。 |
| `templates/bun/flake.nix`、`templates/elixir/flake.nix`、`templates/gleam/flake.nix`、`templates/go/flake.nix`、`templates/perl/flake.nix`、`templates/rust/flake.nix`、`templates/go/DEVELOPMENT.md`、`templates/rust/DEVELOPMENT.md` | 言語テンプレートの単位へ保留。後続PR未作成・未配備。 |
| `package.json`、`bun.lock` | root npm依存の単位へ保留。後続PR未作成・未配備。 |
| `local-skills/domain-modeling-studio/package.json`、`local-skills/domain-modeling-studio/package-lock.json`、`local-skills/domain-modeling-studio/dist/studio.html`、`local-skills/domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` | studio依存・生成物の単位へ保留。後続PR未作成・未配備。 |
| `scripts/verify-ai-tools.py`、`scripts/verify-apm-deployment.mjs`、`tests/verify-ai-tools.bats`、`tests/verify-apm-deployment.bats` | 汎用helper配布・testsは保留。必要な検証補助はGit管理外tmpへ読み取り取得し、PRへ追加しない。 |
| `docs/architecture.md`、`docs/conventions.md`、`runtime/skill-harness.md` | 一般Nix・言語・検証helper案内等の残差分を保留。現在の規約・先行採用記録は維持。固定CLI更新に必要な説明変更は現時点でなし。 |
| `docs/research/braces-response-20261013.md`、`docs/research/update-tools-skills-20261011.md` | 元の調査履歴を参考として保持。今回の実検証は本記録へ置き、一般npm advisoryの判断は今回変更しない。 |

保留は統合成果 `864880c` に保持する。今回のPR公開と更新全体の完了は区別し、固定CLIもmerge・live配備は未実施として報告する。

## このbranch自身の採用確認と実検証

公式の [flyline v1.9.0](https://github.com/HalFrgrd/flyline/releases/tag/v1.9.0)、[gwq v0.1.2](https://github.com/d-kuro/gwq/releases/tag/v0.1.2)、[waza v0.38.10](https://github.com/microsoft/waza/releases/tag/v0.38.10)、[Playwright CLI v0.1.22](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.22) を固定tagで照会し、draft／prereleaseではないことを確認した。公開日はそれぞれ2026-09-20／10-02／10-09／09-28。flylineは非Nix bashへのロード・inline suggestion等の修正、gwqはglobal discovery高速化とworktree copy修正、Playwrightはdialog／download／run-code等の修正を含む。候補より新しいlatestは調べていない（`tmp/fixed-releases.json`）。

flylineのLinux2 assetとwazaのLinux2／Darwin1 assetの公式release SHA-256 digestをSRIへ変換し、採用hash全5件と一致した（`tmp/fixed-release-hashes.json`）。gwqのsource hashと既存vendorHash、PlaywrightのnpmDepsHashは現Nix入力による実buildで通過した。Playwrightのexact dependency／lockは0.1.22で一致し、公式npmのintegrity・依存集合と全3 entryが一致した。直接依存0.1.22と上流が固定する `playwright`／`playwright-core` の `1.64.0-alpha-1790635538000` は2026-09-28公開で、照会時点に約14日経過し7日待機を満たした。alphaの推移依存はCLIの公式依存であり、一般Playwright stableや他のnpm依存を更新していない（`tmp/fixed-npm-age.json`）。

root／userの `nix flake check --no-build --all-systems --no-write-lock-file` はともにexit 0。user devShellのdefault／wslを3 systemで開始HEADと比較し、package集合は不変、Linuxは4CLI、Darwinはflylineを除く3CLIだけのversion／output差を確認した。root／user flake入力・lock、APM manifest／lock、root package／bun.lock、AI moduleは開始点からbyte一致。統合成果41 fileのうち7対象／34除外を全件追跡し、予定12 file以外のdiffがないことと文書リンクをassertした（`tmp/fixed-{root,user}-check.*`、`tmp/fixed-metadata{,-comparison}.json`、`tmp/fixed-scope-check.json`）。ARM Linux／Darwinは評価だけで、実機実行していない。

| CLI | x86_64-linux実Nix output | 実起動／smoke |
| --- | --- | --- |
| flyline 1.9.0 | `/nix/store/j92bwfspzdayjx056vg08anvrldi8iky-flyline-1.9.0` | Ubuntu bash 5.2.21とNix bash-interactive 5.3.9のstdin／stdoutをTTYとして確認し、load／enable・builtin判定・version／help・mouse無効化が成功 |
| gwq 0.1.2 | `/nix/store/ghpzaqcbw6ipf9ax5kxpp93dxjc2cwk8-gwq-0.1.2` | version／help、bash／fish／zsh completion生成が成功 |
| waza 0.38.10 | `/nix/store/v2ps863hjq5qjj34vbxq0019zanyjvr3-waza-0.38.10` | version／help、tmpのscaffoldからmock executorで1件成功・失敗／error 0。実モデル／認証は使わない |
| Playwright CLI 0.1.22 | `/nix/store/a625fgzxq8qdhqynb86rffwbvy2q4i0f-playwright-cli-0.1.22` | version／help、共有ownerと本worktreeのheadless Windows Chromeでopen／eval／run-code／snapshot／対象session closeが全てexit 0 |

buildログ／exitは `tmp/fixed-build.{log,json,exit}`、版／help／completionは `tmp/fixed-*-{version,help}.log` と `tmp/fixed-gwq-completion.*`、flylineのTTY結果はtool実行記録と `tmp/fixed-flyline-tty.json`、wazaは `tmp/fixed-waza-{offline.log,offline.exit,result.json}` に保持する。Playwrightは `tmp/fixed-browser-{smoke.log,smoke.exit,result.json}` と各commandログ。候補packageのowner・Windows scriptを使い、共有ownership directoryを明示し、既存consumerのない本worktreeだけを操作した。通常browser／他worktreeを停止せず、終了後に既存全identityのrecordが前後不変、本sessionの所有権が解放済みであることを確認した。WSL local browserを起動・追加downloadしていない。

gwq 0.1.2の上流breaking changesは、広い `copy_files` patternがdirectoryを再帰コピーする点、global discoveryでlinked worktree内部のnested repositoryを探索しない点、plain bare repoの設定rootがbare directoryになる点。repoに該当するgwq設定・callerはなく、wrapper／completion以外のsource変更は不要と判断した。利用者自身の設定にはこの挙動変更が及ぶためPR本文へ記載する。

初回のflyline TTY probe2件はheredocがstdinを置き換えてTTY判定でexit 1となった。`/dev/tty`をstdinに戻した同じ対話shellで成功し、初回を成功に含めない。formatterの初回 `nix run .#formatter` はapp解決に失敗したため正式な `nix fmt` へ訂正した。変更したgwqに既存format差があり、同fileだけを採用formatterで整形してNix4 fileのcheckを通過した。logic／vendorHashは変えていない。

source-selected user／repoの両wsl devShellを、shellHookより先にHOME／全XDGを隔離して起動した。6AI CLIのNix outputと実版はClaude 2.1.296／Codex 0.162.1（cleanup patch付き）／Copilot 1.0.96／Antigravity 1.3.3／APM 0.33.0／Herdr 0.9.3で一致。補助helperは統合成果から `tmp/reference-verify-ai-tools.py` へ読み取り取得しただけで配布しない。

全suite用の実Impeccable launcherを、source-selected APM 0.33.0で既存manifest／lockから `/tmp/fixed-clis-apm.mHuaBN` に隔離frozen配布した。20 dependencyのinstall、lock SHA-256前後不変とsource byte一致、audit baseline 10/10は成功。隔離cwdにGit remoteがないため組織policy enforcementはwarning付きskipで未実行。採用中skill 4.5.2／engine 0.1.14を全suite開始前から指定する。source pairの生成・再解決・編集は行っていない（`tmp/fixed-apm-prepare.*`、runtimeの `frozen.log`／`audit.log`／`lock-{before,after}`）。

関連Bats初回は40件中39通過・1失敗、exit 1。実Playwright packageのstore path転記ミスによるfixture入口の失敗であり、候補buildの失敗ではない（`tmp/fixed-related-initial.tap`）。候補pathを `tmp/fixed-paths.json` の実build結果から読む形へ直し、同じ関連40件を再実行する。結果は以下へ追記し、初回と区別する。新しい配布logic／test seamは追加しない。

関連再実行は `tests/nix-devshell.bats`／`tests/playwright-runtime.bats`／`tests/dot_bashrc.bats` の40件が全通過・skip 0・失敗0、Bats exit 0。候補Nix outputを指定した実配布fixtureには共有FD／lock・直接CLI保護の検証を含む。plan 40・1–40の連続番号・bailoutなしを照合した（`tmp/fixed-related-final.tap`／`fixed-related-result.json`）。同じ隔離devShellのroot frozen install／`bunx tsc --noEmit`もexit 0。ランチャーのexit 1は後続Markdown format checkで本記録1 fileの未整形を検出した結果で、Batsの失敗とは区別する。記録を整形して変更fileのformatを再確認し、テストを不要に反復しない。

## 2軸レビューとcanonical全suite

実装commit `33727ba5ec255666daa4e05124538286bee50bc4` をfixed point `31969aa1dca1e7b45be7992083ca8570a5ea2dd2` から `code-review` の2軸subagent（gpt-6-luna／xhigh）で確認した。Standardsは規約違反0件・重要smell 0件、Specは欠落／部分実装0件・依頼外追加0件・誤実装0件。現在要件・ADR箇所・予定12 file・全除外34 file・過去参考と今回の実証の区別を両軸へ渡し、指摘修正は不要だった。ユーザーの追加引継ぎによれば、親の独立Standards／Specも同commitで各0件。親の結果とこの担当のレビューは区別する（`tmp/fixed-review-result.json`）。

親の最終確認後、同commitのsource・test・依存・検証環境を固定し、source-selected user／repo両wsl devShellを隔離HOME／全XDGで起動した。6AI CLIのoutput／実版一致を確認してから、このbranch自身のcanonical `lefthook run test` を一度実行した。全769件（748通過・21 skip・失敗0）、runner／ランチャーともexit 0、1323.89秒。TAP planは1つで件数と一致し、1から769の連続番号・bailoutなしを確認した。実行前後の全578 tracked fileのSHA-256も不変だった。

開始前から `TEST_PLAYWRIGHT_PACKAGE=/nix/store/a625fgzxq8qdhqynb86rffwbvy2q4i0f-playwright-cli-0.1.22`、`IMPECCABLE_HOOK_RUNTIME=/tmp/fixed-clis-apm.mHuaBN/.agents/skills/impeccable/scripts/impeccable`、source-selected `IMPECCABLE_BIN=/nix/store/jdlsfn13dv4y82vk67x1fanrn67jyj7m-impeccable-0.1.14/bin/impeccable` を固定した。全suite内の実Design Hook13件と候補Playwright実配布保護／共有FD・lock fixtureは通過し、未materialize／package未指定skipはなかった。21 skipは実Herdr、Bash 3.2、実モデル／認証付きGitHub／MCP、専用隔離runtime／public dependency gateway、6言語生成、public Nix appの既定opt-in。関連40件や別CLI／browser smoke、先行branchの769／787件を全suiteの通過数へ合算していない。

証拠は `tmp/test-run.LtpUUO/{tap.log,setup.log,environment,exit-code}`、`tmp/fixed-canonical.{log,exit}`、`tmp/fixed-full-result.json`、`tmp/fixed-canonical-{environment,source-before,source-check}.json`、`tmp/ai-tools-5z7e14yx/{metadata.json,startup.log,exit-code}`。canonicalのPythonは `/nix/store/c717105hk6ppc20pi88g0n1ad5nr5s8m-python3-3.14.7-env/bin/python3.14`、`with-env` は `/nix/store/q3xwg3rk7s8l92a92rmaiqpmh3rmnp1m-with-env/bin/with-env` を使用した。

## 最終記録と公開の境界

全suite後の変更は本記録と既存4分割記録への結果・対応先の追記だけ。実行source・test・Nix／lock・依存・検証環境を変更せず、全suiteを不要に再実行しない。ユーザーが再度 `pr` を明示し、親のレビュー済み本文 `/tmp/nix-shell.BKnozE/dotfiles-fixed-cli-pr-reviewed-iusvfi1m.md` の採用を指定したため、新しい一時bodyfileへコピーし全suite行だけを実際の結果へ置き換える。

最終記録・review・commit・clean・fullsuite成功を照合してから、同じtopicを `git-push-topic` で公開し、remote default `main` 向けに英語Conventional title `chore(tools): update pinned fixed CLIs` でPRを作成する。既存current branch PRは入口確認時になかった。固定CLIのPR公開までを今回の完了境界とし、merge／live applyは行わない。一般Nix／言語／root npm／studio／汎用helper等は統合成果 `864880c` に保留し、更新全体の完了とは扱わない。

最終記録と指定PR本文のbounded reviewもStandards／Spec各0件。記録5 file以外の573 tracked file、6AI CLI／4固定CLI／Impeccable engine／canonical `with-env` outputが全suite時から不変であることを確認した（`tmp/fixed-final-{source-check,output-check,outputs}.json`）。ユーザー指定の公開本文との差は全suite行だけで、成功・skip・失敗・exit・source前後一致を実測値へ置換した。結果をcommitしてcleanを確認後、topic公開へ進む。

公開結果: [固定CLI後続PR #402](https://github.com/treflebonbon/dotfiles/pull/402) を `main` 向けに作成した。branchは `dev/update-fixed-clis-20261013`、実装commit `33727ba`、検証記録commit `f01c38a`。`git-push-topic` の成功と、PR作成時のlocal／upstream／PR HEAD `f01c38a9f4682565a8d907d15abf8fb5c166a912` の一致、英語Conventional title／指定日本語本文／OPEN・非draft状態を確認した（`tmp/fixed-pr-created.json`）。公開後の変更はこの対応先と既存4記録への追跡追記だけで、実行source・依存・検証環境は不変。この文書追記もcommit・topic pushして最終HEAD一致を確認する。merge／live applyは未実施、一般Nix・言語・root npm・studio・汎用helper等は保留で、更新全体は未完了である。

## PR #402 Review Round（review 5503105919）

ユーザーのレビュー対応依頼と親の正式引継ぎに基づき、同じcheckout／branch、開始HEAD `289328499e6af10a6b2f2962e78f95b773ec2a77` のphysical root・branch・HEAD・clean・Git dir・common dirを自身で再確認した。対象threadは `PRRT_kwDOTMg6A86r2GPW`、package lockのresolved URL3件が第三者mirrorへ変わりcache miss時の配布をmirrorへ依存させる指摘。親の妥当性判断を受け、mainで用いていた公式 `https://registry.npmjs.org/` へ戻す。global npm設定／live HOMEは変更しない。

予定変更はlockのURL3件、実fetchから必要となる場合のnpmDepsHash 1 field、本記録だけ。版・integrity・依存集合・package.json・他CLI・Nix入力・APMは維持する。公式tarballを実取得してSHA-512 integrityを照合し、候補Linux Nix build／version・help／関連Bats／型・formatを検証する。HOME／全XDGをshellHook前に隔離し、候補Playwright outputと採用Impeccable実runtimeを開始前から指定してcanonical全suiteを再実行する。前の748通過・21skipとは別の結果として扱い、前回ログは上書きしない。証拠は `tmp/review-round-5503105919/` と今回生成する一意なruntime／TAP directoryへ保存する。実装・検証記録を一つの `fix: address PR review feedback` commitにまとめ、topic pushとPR本文反映まで行う。thread返信／resolveは親が担当する。merge／applyは対象外。

修正前はresolved 3件がmirrorを指すことを一時checkerで確認し、修正後はURL3行以外のlock metadataとpackage.jsonが不変であることをassertした。公式URL3件を新しいdirectoryへ実取得し、HTTP 200・redirect後もregistry.npmjs.org・SHA-512 integrity一致を確認した。キャッシュ再利用だけの取得確認ではない（`tmp/review-round-5503105919/{official-url-before-result,lock-invariant-result,official-fetch-result}.json` と `official-tarballs/`）。採用Nix入力の実prefetchでnpmDepsHashは `sha256-JrqEzup8H1XYx3EViWHqj4P53a9sBXdot586PkT0knQ=` から `sha256-Jiy7hSv23PenWcQcX5rd6oyEiMV0nW7FatfhAxj5Sdw=` へ変わり、同fieldだけを更新した。最初のprefetch utility評価は一時Nix式のpathと演算子の空白不足で失敗し、式を訂正して取得・prefetchが成功した。失敗ログは別名のまま保持し、成功へ含めない。

公式URL／新hashでPlaywright CLIのx86_64-linux実Nix buildはnpm-depsと本体の2 derivationをbuildして成功し、候補outputは `/nix/store/5ifpr6jvz2rj8m8vwz79iddsh3ag2li7-playwright-cli-0.1.22`。同outputを指定したnix-devshell／playwright-runtimeの関連31件は31通過・skip 0・失敗0、plan・連続番号・bailoutなし・exit 0を照合した。version 0.1.22／help、root frozen install／型検査、変更Markdown／JSON／Nix format、user flakeの3 system評価、diff checkも成功。shellHook前にHOME／全XDGを隔離したsource-selected user／repo devShellで6AI CLIのoutput／実版も一致した。証拠は `tmp/review-round-5503105919/{playwright-build,related-result}.json` と各log／exit、隔離runtime `tmp/ai-tools-5szvkqqh/`。親の指摘・対象diffと実変更を照合し、lock URL3行／npmDepsHash 1 field／本記録の3 fileだけであることを最終assertした。新しい配布helper／test seamは追加していない。

今回の修正後canonical `lefthook run test` は新しい隔離HOME／全XDGとsource-selected user／repo wsl devShellで実行し、769件（748通過・21 skip・失敗0）、runner／canonical／ランチャーともexit 0、lefthook計測1049.71秒。TAP planは1つ、1–769の連続番号・bailoutなしを照合し、全578 tracked fileの実行前後SHA-256も不変だった。実Design Hook13件と候補Playwright実配布保護／共有FD・lock fixtureは全suite内で通過。21件は既定opt-inで、前の748／21の成功や今回の関連31件・version smokeを合算していない。

開始前から `TEST_PLAYWRIGHT_PACKAGE=/nix/store/5ifpr6jvz2rj8m8vwz79iddsh3ag2li7-playwright-cli-0.1.22`、採用中Impeccableの既存frozen launcherとsource-selected engineを固定した。APM manifest／lockはそのfrozen runtimeとbyte一致しており、APM再解決・配備先変更は行わない。証拠は `tmp/review-round-5503105919/{full-result,source-before,source-check,environment}.json`、`canonical{,-launch}.exit`、`canonical-output.log`、`current-tap-path`、今回のTAP `tmp/test-run.AQaUjf/{tap.log,environment,exit-code}`、6AI CLI起動runtime `tmp/ai-tools-ut6i4gw8/`。前の `tmp/fixed-*`／`tmp/test-run.LtpUUO/` は保持した。ARM／Darwin実機・認証／モデル等の既定opt-in・APM組織policyの未確認境界は変わらない。

親が追加指定したReview Roundの順序は、canonical成功→結果文書追記→一つの `fix: address PR review feedback` commit→固定点 `2893284` からcommit済み差分の `code-review`→`git-push-topic`。この順で進め、公開前の必要修正だけを未公開commitへまとめ直す。published amend／force pushは行わない。今回の結果追記だけでは成功済み全suiteを反復せず、実行source／test／依存／検証環境が変わる場合は再実行する。公開後のshort／full SHA・検証結果・evidence path・HEAD一致を親へ報告し、thread返信／resolveは親へ委ねる。PR本文には公式URL修正と今回の結果を反映する。

一般Nix入力と6言語テンプレートは承認済みの別単位として実装・検証を開始した。対応先と元差分の採否・残保留は [一般Nix／言語記録](nix-languages-pr-20261013.md) に追跡する。先行PR #397–402の採用済みsourceは維持し、merge／live applyは今回行わない。

一般Nix／6言語単位の実装commitは `dd7cf20`。今回branchの関連89/89、全6言語独立gateと追加compile／test、固定CLI／flyline実TTY、独立レビューStandards 0件／Spec 0件が成功した。同commitのcanonical全suiteは769件（748 pass／21 skip／0 fail、runner／launcher exit 0、579 tracked file不変、942.5秒）。親の独立照合も完了し、[今回記録](nix-languages-pr-20261013.md) と日本語本文を確定してtopic公開・PR作成へ進む。旧成果や別gateの件数は合算せず、merge／live applyとroot npm／studio／汎用helper等の保留は未完了のまま維持する。

一般Nix／6言語の対応先は [後続PR #403](https://github.com/treflebonbon/dotfiles/pull/403)。実装 `dd7cf20`／検証記録 `c8cb1bc` を非force公開し、通常PR・main・確定本文・HEAD一致を照合した。CIはscan-pr / osv-scanのSUCCESSと、osv-scannerの新規alerts判定不可によるNEUTRALを区別する。詳細は [公開記録](nix-languages-pr-20261013.md) を参照。workflow修正は今回追加せず、merge／live apply・残保留・更新全体の完了は未実施のまま維持する。
