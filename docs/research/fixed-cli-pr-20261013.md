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
