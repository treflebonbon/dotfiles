# Impeccable PR分割（2026-10-13）

## 現在の要件と更新境界

ユーザーの「推奨案で進めて」と正式引継ぎに基づき、保留Impeccableのskill／engineを独立PRへ仕上げる。実装・隔離配布・検証・2軸レビュー・commit・`git-push-topic`・PR作成までが承認範囲。merge／`chezmoi apply`は対象外。開始hookのtimeoutによる中断後も通常の再開に成功し、hook設定・権限は変更していない。

native checkout `/home/ubuntu/orca/workspaces/dotfiles/update-impeccable-20261013`、branch `dev/update-impeccable-20261013`、開始HEAD `7af6a0ace1f3f2692c59068d2898c6595dcb020a`、clean、worktree Git dir／common dirを自身で再確認した。同checkoutで全phaseを続け、raw adapterで起動し直さない。

Tool Snapshot [PR #397](https://github.com/treflebonbon/dotfiles/pull/397) と通常APM [PR #398](https://github.com/treflebonbon/dotfiles/pull/398) は開始HEADへmerge済みとGitHubで確認した。live配備はユーザー報告と親のsource／lock一致確認に基づき、この担当の実行結果とは区別する。snapshot `998b9f267c671917a0b9a88b01e287c3168f3c24`、APM 0.33.0、品質floor、Codex cleanup patchを維持する。

適用する [ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) はDecision 3の独立Design Hook互換性ゲートと更新単位・rollback境界、Decision 2／4の通常APM／Mattの独立性。[ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) のAPM skill／launcherとNix engineの分離、一体検証、quiet、5秒／30秒、正常出力、失敗stdout破棄・fail-open、cache所有先、理由付きignore-valueとfile／rule承認境界を維持する。`runtime/skill-harness.md:119–123` のsource外native lock生成と、`docs/conventions.md` の追跡・canonical全suite契約に従う。過去initiativeのlive配備完了境界は今回の承認範囲へ広げない。

読み取り参考は統合成果 `864880c0498d9b274c506183a2087f0863d674f7` の `docs/research/update-tools-skills-20261011.md` と既存 [Snapshot分割記録](tool-snapshot-pr-20261013.md)／[通常APM分割記録](ordinary-apm-pr-20261013.md)。過去の採用・検証・残差分は参考とし、このbranch自身の成功として転記しない。参照checkout・live配備先は編集しない。

## 候補と予定変更

| 対象 | 開始HEAD | 採用候補 |
| --- | --- | --- |
| APM skill／launcher | 4.5.1 `9dad388a41944a0d2b8d1fb547c8556d2ecb49e7` | 公開4.5.2 `d631a8827f99414d2b6daba4ef08b7f8701751d7` |
| Nix engine | 0.1.12 | 公開0.1.14 |

予定差分は `apm.yml` のImpeccable pin、native生成の `apm.lock.yaml` の候補payload／hash／ledger、`private_dot_config/nix-devshell/packages/impeccable.nix` のversion／3-system hash、`tests/apm-runtime.bats`／`tests/impeccable-engine.bats` の独立期待値、`runtime/skill-harness.md` の現行版表記と本記録・分割追跡。hook配線／timeout／download／失敗処理は既存fixtureで互換性を確認し、必要がなければ変更しない。上流skillはforkしない。新logicは予定せず、pin／期待値／文書には既存testsを使う。

公式 [skill-v4.5.2](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.5.2) のannotated tagをcommitまで解決して指定revisionとの一致を確認した。[engine-v0.1.14](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.14) はdraft／prereleaseではなく、GitHub release APIの3 asset digestをSRIへ変換して固定する。上流HEADへ範囲を広げない。過去に却下された未公開HEAD `245ad82d` のseed reference／`--check-seed`要求は公開engine非対応の参考判断として保持し、今回採用しない。

## 分割で外した変更と対応先

元差分の各file一覧は既存Snapshot／通常APM追跡表に保持する。開始HEADと統合成果の差分も照合し、同fileの部分採用と残り保留を区別する。

| 更新単位・差分 | 対応先と現在の状態 |
| --- | --- |
| Tool Snapshot／品質floor／FD patch適用終了／cleanup維持 | PR #397、実装 `4dcf299`、merge `ef64dd3b`。merge・live配備済み（上記証拠境界）。 |
| 通常APM18依存のpin／payloadと独立期待値 | PR #398、実装 `d8adb3a`、merge `7af6a0a`。merge・live配備済み（上記証拠境界）。今回の非candidateとして全field・実bytes・ledgerを比較する。 |
| Impeccable manifest／lock／Nix package／tests／runtime版表記 | このbranch／本記録に対応。実装・検証・レビュー・公開を今回行う。live配備は未実施。 |
| Matt pin／workflow contract／gate tests／runtime採用記録 | 統合成果 `864880c` に保持。後続PR未作成・未配備。今回 `b0618bc436ad893b3c5e84e55fba86586d34a404`／27 fullsetを維持する。 |
| root／userの一般Nix・言語取得元／6テンプレート／architecture・conventionsの残差分 | 統合成果 `864880c` に保持。後続PR未作成・未配備。今回のflake／lockは維持する。 |
| npm／studio package・lock・dist／Playwright package・lock | 統合成果 `864880c` に保持。後続PR未作成・未配備。 |
| fixed CLI（flyline／gwq／waza／Playwright） | 統合成果 `864880c` に保持。後続PR未作成・未配備。 |
| 汎用verify helper／そのtests／braces記録／統合調査記録の残差分 | 統合成果 `864880c` に保持。後続PR未作成・未配備。helperは必要ならGit管理外tmpへ読み取り取得して補助利用し、配布しない。 |

APM全20 dependencyと両target各46 skillを保持する。非Impeccable19 dependency（通常18＋Matt）のpin／payload／metadata／owner ledgerは不変を要求し、native package_type差があれば原因を確認する。手書きlock補正や候補外driftの黙認はしない。一時pin gate lockをsourceへコピーしない。

## 検証計画

source外のcwd／HOME／全XDGでsource-selected APM 0.33.0を照合し、実manifestから `scripts/generate-apm-lock.sh` を実行する。同環境のfrozen前後SHA-256不変、audit baseline 10/10（Git remoteなしの組織policy skipと区別）、実bytes／frontmatter／discovery／owner ledgerと候補外不変を確認してからsourceへ採用する。

候補実engine＋launcherでDesign Hook全13件、APM／engine／managed hook周辺tests、3-system Nix eval、Linux実build／version、root／user flake評価、型・変更file format・diffを確認する。commit済み差分をfixed point `7af6a0a` からStandards／Specのgpt-6-luna／xhighでレビューし、修正後の同じsource-selected隔離環境でcanonical `lefthook run test` を一度実行する。全suite開始前から候補runtimeを明示し、TAP plan／連続番号／pass・skip・fail・exitを保存する。既定opt-inはskipを維持し、別gateを全suite通過数へ合算しない。ARM Linux／Darwinは評価のみと区別する。

## このbranch自身の隔離配布と個別検証

source-selected Nix metadataと実CLIはAPM 0.33.0 `/nix/store/wq2wcjgmpcn370kmsszpyx8fyk1wz7x3-apm-0.33.0/bin/apm` で一致した。source外 `/tmp/impeccable-20261013-a3c3gvew` のcwd／HOME／全XDGに候補manifestと開始lockをコピーし、`scripts/generate-apm-lock.sh SOURCE_DIR` からnative lockを生成した。`--update`や非candidate一時pinは使っていない。生成／同環境のfrozen／auditは全てexit 0、frozen前後SHA-256は `b50e830f7a90b17b3d8848c4f84fa855c214c46e2df22020d183507eb9a7d01a` で不変。audit baselineはdriftなし10/10。隔離cwdにGit remoteがなく、組織policy enforcementはwarning付きskipで未実行である。

非Impeccable19 dependencyはresolved_commitを含む全fieldが不変。Mattのpin／hash／27 fullset・native `marketplace_plugin`、通常18依存のpayload／metadataも維持した。候補はnative `claude_skill` のまま、content hashは `sha256:12a70e4f07c928562c475b24b952c9b5005614cfd7feeaed59c35dcd3efa66cb`。両target各46 skill、全1,372 file hashと実bytes・frontmatter・余剰／不足skillを照合し、追加0／削除0。owner ledger全1,464 recordの構成・owners／active_ownerは不変で、候補単独ownerの126 record中10 content hashだけが変わった。共有ownerを含む候補外ledgerは全field不変。比較成功後のnative lockだけをsourceへコピーし、手修正・再整形はしていない。

上流selected subtreeの差分は各targetの `SKILL.md` version、3 reference（doctor／init／new-work）、`scripts/VERSION` の5 file。launcher本体は不変、VERSIONのみ0.1.14へ進んだ。公式release間の `crates/hooks/` に差分はなく、engineはcode-ledの操作画面／文書とfont fingerprint最適化を含む。未公開seed契約は取り込んでいない。API比較は `tmp/impeccable-{upstream,engine}-comparison.json` に保存した。

| system | 公式engine asset SHA-256 | 検証境界 |
| --- | --- | --- |
| x86_64-linux | `3d31ec1a664ac35c815ea1d7c10abad1155ce364d0f461157eb837a34368efb6` | Nix実build／実binary hash一致／実起動 |
| aarch64-linux | `396263ee694780db942483fc80933a012ef08bf981f5f26b0da5e16b6208c948` | 公式digest照合とNix評価のみ |
| aarch64-darwin | `abbd69d540532b91e9599c41d3a6127dfbaabae5e24bafd74ff7e2fb18f4f87c` | 公式digest照合とNix評価のみ |

root／userの `nix flake check --no-build --all-systems --no-write-lock-file` は成功。`tests/impeccable-engine.bats` は3 system・default／wslの全6 shellのpackage versionと `IMPECCABLE_BIN` を照合した。Linux実outputは `/nix/store/jdlsfn13dv4y82vk67x1fanrn67jyj7m-impeccable-0.1.14/bin/impeccable`。Nix package／上流Cargo workspace／ENGINE_VERSION／launcher VERSIONは0.1.14で一致するが、公開binaryとlauncherの `--version` 出力は `4.0.0` であり、package versionとは区別する。実binary SHA-256が公式release digestと一致したため、別版の混入とは扱わない。

このsourceのuser／repo devShellを隔離HOME／全XDGで組み合わせ、source-selected 6 CLIのoutput／実起動を照合した。Claude 2.1.296、Codex 0.162.1（cleanup patch付き）、Copilot 1.0.96、Antigravity 1.3.3、APM 0.33.0、Herdr 0.9.3が一致した。同環境へ候補launcherと実engineを明示し、Design Hookは13件、APM／cache refresh／engineは30件、managed hookは3件、全46件通過・skip 0・失敗0・helper exit 0。TAP planと1からの連続番号を照合した。Claude／Codex PostToolUse／Stop、quiet、5秒／30秒、正常出力、silent convergence、symlink／monorepo、cache所有先、理由付きignore-valueとfile／rule承認境界、fail-open／失敗stdout破棄を既存fixtureから検証し、hook配線は変更していない。

root frozen npm install／`bunx tsc --noEmit`、変更文書・manifestのOXC format、Nix format、`git diff --check`は成功。予定9 fileのみの差分で、開始HEAD／統合成果の差分44 fileの対応先が既存追跡表にあることもassertした（`tmp/impeccable-scope-check.json`）。新logic／test seam／配布helperは追加していない。

証拠はAPM runtimeの `generation.log`／`frozen.log`／`audit.log`／`lock-sha256.json`／`comparison.json`／`deployment.log`／各 `.tap`／`related-result.json` と、このcheckoutの `tmp/ai-tools-4lel5pz4/{metadata.json,startup.log,exit-code}`、`tmp/impeccable-{root,user}-check.log`／engine build記録。補助helperは参照checkoutから `tmp/reference-*` へ読み取り取得しただけでPRへ追加しない。最初のtmp ledger比較はowner IDをrepo URLと誤認してexit 1になり、正式なvirtual-path付きowner IDへcheckerを訂正して再比較に成功した。source lockの補正や候補外driftの除外ではない。

採用commit前の計画は、この採用差分をcommitして、fixed point `7af6a0ace1f3f2692c59068d2898c6595dcb020a` からStandards／Specへ現在の承認要件・適用ADR箇所・予定変更・外した差分の追跡・過去参考の区別を渡し、指摘修正後にcanonical全suiteを実行することだった。実施結果は以下に記録する。

## 2軸レビューとcanonical全suite

採用commit `83a8f38` をfixed point `7af6a0a` からStandards／Specのgpt-6-luna／xhighでレビューした。Standardsは規約違反0件・smell 0件、Specは欠落／部分実装0件・依頼外追加0件・誤実装0件。予定9 fileと実差分、外した全変更の対応、適用ADR、過去の参考と今回の証拠の区別を両軸へ渡した。指摘修正は不要だった。

同commitのsource・依存・環境を固定し、隔離HOME／全XDGのsource-selected user／repo devShellで6 CLI output／実起動と候補engine／launcher pathを再照合した後、このbranch自身でcanonical `lefthook run test` を一度実行した。全769件（747通過・22 skip・失敗0）、runner／helperともexit 0。TAP planは1つで件数と一致し、1から769の連続番号・bailoutなしを確認した。全tracked 576 fileのSHA-256も実行前後で不変。過去の769／787件は代用せず、別gateの46件も全suiteへ加算していない。

全suite開始前から `IMPECCABLE_HOOK_RUNTIME=/tmp/impeccable-20261013-a3c3gvew/.agents/skills/impeccable/scripts/impeccable` とNixの候補 `IMPECCABLE_BIN` を固定し、全suite内のDesign Hook 13件も全て実行・通過した。未materializeの12 skipは発生していない。残る22 skipは、`TEST_PLAYWRIGHT_PACKAGE` 未指定の実配布fixture 1件と、実Herdr・認証・モデル・MCP・隔離runtime・Bash 3.2・全6言語生成・public Nix app等の既定opt-in 21件。これらとARM実機・組織policy enforcementは未確認のまま残す。

証拠は `tmp/test-run.q0029w/{tap.log,setup.log,environment,exit-code}`、`tmp/ai-tools-gyfiz5j8/{metadata.json,startup.log,exit-code}`、集計 `tmp/impeccable-full-result.json`、source照合 `tmp/impeccable-full-source-{before,check}.json`。選択されたPythonは `/nix/store/c717105hk6ppc20pi88g0n1ad5nr5s8m-python3-3.14.7-env/bin/python3.14`、`with-env` は `/nix/store/q3xwg3rk7s8l92a92rmaiqpmh3rmnp1m-with-env/bin/with-env`。

## 最終記録と公開の境界

PR公開前の計画: 全suite後の差分は本記録の結果追記と既存2記録への対応commit／状態追記だけ。manifest／lock／tests／Nix／依存／検証環境は変更せず、不要な全suite反復はしない。最終記録と日本語PR草稿を両軸で確認し、結果をcommitしてclean／fullsuite成功を照合後、`git-push-topic` で公開する。remote defaultは `main`、同branchの既存PRはなかった。英語Conventional titleと新しい一時bodyfileからPRを作成し、公開結果を追跡へ反映する。

Impeccableの実装・隔離検証・レビュー・PR公開を今回の完了境界とする。merge／live applyは実施せず、Matt／一般Nix／言語／npm／fixed CLI／汎用helperの後続PR未作成・未配備の保留を維持する。更新全体は未完了である。

最終記録／日本語PR草稿のSpecレビューは指摘0件。Standardsは計画の時制が曖昧な1文を指摘し、採用commit前の計画と明示して再確認で解消した。追加指摘・未解決指摘はない。結果追記対象3 file以外の573 tracked file、source-selected 6 CLI output／version、候補engine、canonical `with-env` outputは全suite時から不変（`tmp/impeccable-final-output-check.json`）。PR titleは `chore(impeccable): update validated skill and engine` で、公開後のGitHub titleも照合済み。

公開結果: [Impeccable後続PR #399](https://github.com/treflebonbon/dotfiles/pull/399) を `main` 向けに作成した。採用実装commitは `83a8f38`、検証記録commitは `e7b0d7b`、branchは `dev/update-impeccable-20261013`。`git-push-topic` の公開、PR作成時のlocal／upstream／PR HEAD `e7b0d7b682fddb292727ab52cd1de7e3cb0b1f63` の一致、英語Conventional title／日本語本文／OPEN状態を確認済み（`tmp/impeccable-pr-created.json`）。公開後はこの結果と既存追跡への対応先だけを追記し、採用source・依存・検証環境は不変。今回のImpeccable PR公開まで完了し、merge／live配備と残る別単位は未完了である。

## Matt Pocock後続単位（2026-10-13）

先行PR #397／#398／#399はmerge・配備済みという引継ぎを受け、sourceでは開始HEAD `e333f8a` と一致する。Matt候補 `49dd158d1076134a641b33efb035946536778336` は今回の独立branchで実ordered gate Decision 1–7と別runtimeのnative生成・frozen・audit・bytes／ledger比較を通過し、sourceへ採用した。19 non-Matt dependencyは全field不変。詳細と今回の実検証境界は [Matt後続記録](mattpocock-pr-20261013.md) を参照する。採用直後の計画では、採用後の個別検証・2軸レビュー・canonical全suite・PR公開を後続phaseとした。Mattは未merge・未配備、一般Nix／言語／npm／固定CLI／汎用helper等の残差分は引き続き保留で、更新全体は未完了。過去の検証結果を今回の成功へ転記しない。

Mattの対応実装commitは `4e6f129`。採用後個別53件は全通過、2軸レビューの未解決指摘0件、このbranch自身のcanonical全suiteは769件（747通過・22 skip・失敗0、exit 0）で、実Design Hook 13件も全suite内で通過した。最終記録／PR草稿を確認して公開へ進む。検証境界と残保留は [Matt後続記録](mattpocock-pr-20261013.md) に追跡し、Mattのmerge／live配備と更新全体は未完了のまま。

Mattの対応先は [後続PR #400](https://github.com/treflebonbon/dotfiles/pull/400)。実装 `4e6f129`／検証記録 `c6c2d7e` の同topicを `git-push-topic` で公開し、PR作成時のlocal／upstream／PR HEAD一致と英語Conventional title・日本語本文を確認した。Matt PR公開まで完了し、merge／live配備と一般Nix・言語・npm・固定CLI・汎用helper等の残保留は未完了である。
