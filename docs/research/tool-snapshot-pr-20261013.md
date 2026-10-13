# Tool Snapshot PR分割（2026-10-13）

## 依頼と範囲

現在の依頼は「Tool Snapshotの分割branchを最新の採用内容に揃え、検証・レビュー・コミット後、PR本文を更新してpush・PR作成まで進める」。main `6a5a7a6a176d34e2510e732f1fb8c9045e8a9043` を開始点とし、検証済みの同じcheckout／branch `chore/ai-tool-snapshot-20261013` で全phaseを続ける。既存8fileの未commit変更を引き継ぐ。ADR-0045 Decision 1／更新単位の独立性、ADR-0047のpackage outputによる品質floor判定、ADR-0070のLinux sandbox回帰を適用する。

参照する統合成果は `dev/update-tools-skills-codex-binary-20261013` の `864880c0498d9b274c506183a2087f0863d674f7`。元branch `chore/update-tools-skills-20261011` の `38a4cac5fd55ece548a1778af6c40aa6f2cdfd34` も保持し、双方を読み取りだけに使う。採用済みimmutable snapshot `998b9f267c671917a0b9a88b01e287c3168f3c24` へ揃え、upstream HEADを追い直さない。過去の分割依頼のサブエージェント禁止は今回の制約ではなく、commit済み差分のStandards／Specを2軸subagentでレビューする。dotfiles自身のPRだけを公開し、依存先upstream書込み・merge・live applyは行わない。

採用する差分はAI snapshotのsource/native lock、Claude／Codexの品質floor、上流へ統合済みFD patchの適用終了、対応する独立テスト期待値、採用理由のADR／runtime記録に限定する。cleanup supervisor patchとsingle-job buildは維持する。

## 変更前後

| 対象 | main | このPR |
| --- | --- | --- |
| snapshot | `2109db8971dc18137ff1ac9393627c761609600d` | `998b9f267c671917a0b9a88b01e287c3168f3c24` |
| Claude品質floor | 2.1.289 | 2.1.296 |
| Codex品質floor | 0.159.1 | 0.162.0 |
| Claude Code | 2.1.293 | 2.1.296 |
| Codex | 0.161.0 | 0.162.1 |
| Copilot CLI | 1.0.93 | 1.0.96 |
| Antigravity CLI | 1.3.1 | 1.3.3 |
| APM／Herdr | 0.33.0／0.9.3 | 不変 |

## 分割で外した差分の対応

未採用の差分は元branchと最終統合成果 `864880c` に保持する。下表のsource commitは元の分割時点の履歴であり、最新内容の参照先は統合成果とする。後続PRが未作成の項目を保留とし、このPRの完了を更新全体の完了として扱わない。

| file | 扱い | 対応先・状態 |
| --- | --- | --- |
| `apm.lock.yaml` | 保留 | 元branch `38a4cac`／source commit `13597db`に保持。後続PR未作成 |
| `apm.yml` | 保留 | 元branch `38a4cac`／source commit `13597db`に保持。後続PR未作成 |
| `bun.lock` | 保留 | 元branch `38a4cac`／source commit `eff331f`に保持。後続PR未作成 |
| `docs/architecture.md` | 一部採用／残り保留 | Codex cleanup撤去条件・cache／source build制限だけ採用。一般Nix／言語説明は統合成果 `864880c` に保持、後続PR未作成 |
| `docs/conventions.md` | 保留 | 元branch `38a4cac`／source commit `c02f12b`に保持。後続PR未作成 |
| `docs/research/braces-response-20261013.md` | 保留 | 元branch `38a4cac`／source commit `f136ee1`に保持。後続PR未作成 |
| `docs/research/update-tools-skills-20261011.md` | 保留 | 元branch `38a4cac`／source commit `38a4cac`に保持。後続PR未作成 |
| `flake.lock` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `local-skills/domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `local-skills/domain-modeling-studio/dist/studio.html` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `local-skills/domain-modeling-studio/package-lock.json` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `local-skills/domain-modeling-studio/package.json` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `package.json` | 保留 | 元branch `38a4cac`／source commit `eff331f`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/flyline.nix` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/gwq.nix` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/impeccable.nix` | 保留 | 元branch `38a4cac`／source commit `44e10b5`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package-lock.json` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package.json` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/playwright-cli.nix` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `private_dot_config/nix-devshell/packages/waza.nix` | 保留 | 元branch `38a4cac`／source commit `40e3383`に保持。後続PR未作成 |
| `runtime/skill-harness.md` | 保留 | 元branch `38a4cac`／source commit `c98bf9d`に保持。後続PR未作成 |
| `scripts/verify-ai-tools.py` | 保留 | 元branch `38a4cac`／source commit `a8e9963`に保持。後続PR未作成 |
| `scripts/verify-apm-deployment.mjs` | 保留 | 元branch `38a4cac`／source commit `c98bf9d`に保持。後続PR未作成 |
| `templates/bun/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `templates/elixir/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `templates/gleam/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `templates/go/DEVELOPMENT.md` | 保留 | 元branch `38a4cac`／source commit `c161c66`に保持。後続PR未作成 |
| `templates/go/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `templates/perl/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `templates/rust/DEVELOPMENT.md` | 保留 | 元branch `38a4cac`／source commit `c161c66`に保持。後続PR未作成 |
| `templates/rust/flake.nix` | 保留 | 元branch `38a4cac`／source commit `8ea23ac`に保持。後続PR未作成 |
| `tests/apm-runtime.bats` | 保留 | 元branch `38a4cac`／source commit `13597db`に保持。後続PR未作成 |
| `tests/impeccable-engine.bats` | 保留 | 元branch `38a4cac`／source commit `44e10b5`に保持。後続PR未作成 |
| `tests/mattpocock-update-gate.bats` | 保留 | 元branch `38a4cac`／source commit `760b439`に保持。後続PR未作成 |
| `tests/verify-ai-tools.bats` | 保留 | 元branch `38a4cac`／source commit `a8e9963`に保持。後続PR未作成 |
| `tests/verify-apm-deployment.bats` | 保留 | 元branch `38a4cac`／source commit `c98bf9d`に保持。後続PR未作成 |
| `tests/workflow-contract.bats` | 保留 | 元branch `38a4cac`／source commit `760b439`に保持。後続PR未作成 |

同じfile内で外した差分: user flakeの一般stable／言語取得元はmainを維持し、lockではllm-agents subtreeだけを更新する。`tests/nix-devshell.bats`のRemotion pinとPlaywright 0.1.19期待値はmainを維持する。ADR／runtimeの通常APM・Impeccable・Matt・一般ツールの採用記録は取り込まない。

## 検証計画

分割後のsource/lock/pin整合、非candidate inputとAPM／一般Nix／npm不変、個別品質floor・nix-devshell・sandbox回帰、3-system評価、隔離HOMEでの6 CLI output照合を確認する。commit済み差分を2軸で確認して修正を閉じた後、分割branch自身で全Batsを一度実行する。統合branchの既存787件の成功を分割branchの成功として転記しない。認証・実モデル等のopt-in skipを維持する。

## 最新統合成果からの追加差分の採否

| 差分 | 扱いと理由 | 対応先・状態 |
| --- | --- | --- |
| architectureのCodex取得経路・cache制限2行 | 採用。FD patch適用終了とcleanup patch維持後の説明を整合させる | このPR |
| runtimeのnative child採用記録2行 | Snapshot／Copilot／Codex制限だけ採用。通常APM／Impeccable／Mattの採用記録は保留 | このPR／統合成果 `864880c`、後続PR未作成 |
| 統合更新記録のCodex比較・検証約64行 | 取得経路の採否根拠だけ本記録へ要約。統合branchの検証結果はこのbranchの成功として転記しない | 本記録／原文は統合成果 `864880c`、後続PR未作成 |
| 汎用検証helper追加 | 保留。今回のpin更新に新しい配布helperは不要 | `scripts/verify-ai-tools.py`等は統合成果 `864880c`、後続PR未作成 |

## Codexの取得経路と残制限

統合成果の `docs/research/update-tools-skills-20261011.md:279` 以降と `tmp/codex-binary-20261013/` を読み取りで確認した。これは今回の再実行結果ではなく、取得経路の採否を確定した参考証拠である。

- 公式0.162.1 musl package（SHA-256 `a676f5722aae0d86cbe3764332f08eab1fdd89dc0a300b3ad4ffbf48611fa3e3`）とNumtideのパッチなしcache outputは、どちらもcleanup 8件中5成功・3失敗。SIGKILL、並行終了、SIGTERM無視で空の`.env`が残った。FD回帰は成功した。
- したがって公式バイナリ／パッチなしcacheへの切替は却下し、既存cleanupパッチ付き0.162.1を維持する。npm／Homebrewのinstaller自体は未実行で、独立したcleanup修正版の根拠もないため採用しない。
- 外部cleanup wrapperや共有cache新設は今回の範囲へ追加しない。derivationとoutputが既存cacheにあれば再利用できるが、未キャッシュLinux環境ではsingle-job source buildが必要。「自前buildを完全に不要にした」とは扱わない。
- FD回帰とcleanup全8件が公開安定版で成功した場合にcleanup patchを撤去する。ARM Linux／Darwinは今回評価のみで、実機実行はしない。

このbranchの検証結果とレビュー状態は以下へ追記する。

## 分割branch自身の個別検証

- source URL／native lockの`original.rev`・`locked.rev`／独立期待pinは`998b9f2`で一致。mainから変わるlock nodeは`llm-agents`／推移的`nixpkgs`／`treefmt-nix`だけ。root flake、非candidate input、APM manifest／lock、npm、言語テンプレートは不変。統合成果から外した全fileが追跡表にあることもassertした（`tmp/snapshot-scope-check.log`）。
- root／user両flakeの`nix flake check --no-build --all-systems --no-write-lock-file`は成功。3-systemの6 CLI metadataは上表の採用版と一致（`tmp/snapshot-{root,user}-check.log`、`tmp/snapshot-metadata.json`）。Linux devShell dry-runのbuild対象はshell derivation 1件のみで、Codex source buildなし（`tmp/snapshot-dry-run.log`）。
- 参照helperをGit管理外の`tmp/verify-ai-tools-reference.py`へ読み取り取得し、隔離HOME／XDGでsource-selected 6 CLI outputと実起動を照合した。採用後のパッチ付きCodex outputは`/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1`。helperはPRへ追加しない。
- 個別Batsは49件（49通過・skip 0・失敗0）。nix-devshell／品質floor／cleanupの45件、managed sandbox／FDの4件で、cleanup全8件とCRGの3-system floor・Linux CLI／MCP smokeを含む。証拠は`tmp/ai-tools-s90hoalj/startup.log`（45＋3件）と`tmp/ai-tools-qjg1a_bm/startup.log`（残り1件）、両helper exit 0。
- 初回は存在しない`tests/codex-managed.bats`を誤指定し、Bats収集段階でexit 1になった。実テストの成功には含めず、正しい既存fileで上記49件を実行した。初回ログは`tmp/ai-tools-6442rlem/`へ保持する。
- root TypeScript `bunx tsc --noEmit`、変更MarkdownのOXC format、変更Nix2fileのnixfmt、`git diff --check`は成功。新logic／TDD seam／配布helperは追加していない。

## 実配布の別gate

source-selected APM 0.33.0とsource-selected Impeccable engineを用い、新しい隔離HOME／XDGへこのbranchの不変APM pairを`apm install --frozen --target claude,codex --https`で配布した。lock SHA-256は前後不変、audit baseline checks 10/10（隔離cwdにGit remoteがないため組織policy enforcementはskip）。候補なし比較は20 dependency、両target各46 skill、追加0／削除0、bytes／metadata不変で成功。実Design Hookは13件（13通過・skip 0・失敗0、exit 0）。全suite側の結果へ合算しない。

証拠は`tmp/snapshot-apm-6u43lm0i/{frozen.log,audit.log,deployment.log,design-hook.tap}`、`tmp/ai-tools-netncl0u/`。補助scriptは統合成果から`tmp/`へ読み取り取得したもので配布しない。この別gateはsource pairや全suite用runtimeを変更しない。

## 事前レビューと全suite

この差分をcommitし、fixed point `6a5a7a6a176d34e2510e732f1fb8c9045e8a9043` のcommit済み差分をStandards／Specで確認する。現在要件・適用ADR・分割で外した変更の対応・統合成果の参考証拠を区別して渡す。全suiteはレビューの指摘修正後にcanonical入口`lefthook run test`でこのbranch自身から実行し、結果を以下へ記録する。統合版787件は代用しない。

## 最終全suiteと完了境界

実装commit `4dcf299189cca903e9332ee41614e1015fb66938` の事前2軸レビューは、Standardsの規約違反0件／smell 0件、Specの欠落・部分実装0件／依頼外追加0件／誤実装0件。指摘修正は不要だった。両軸へ現在要件、適用ADR、保留一覧、統合成果の参考扱いを渡し、親もsource／lock／個別検証証拠を照合した。

同commitの実行source・test・依存・検証環境を固定し、隔離HOME／XDGでsource-selected 6 CLI output／実起動を再照合してから、canonical入口`lefthook run test`をこのbranch自身で一度実行した。全769件（735通過・34 skip・失敗0）、runner／helperともexit 0。TAP planが1つで結果件数と一致し、結果番号が1から769まで連続、bailoutなしを確認した。証拠は`tmp/test-run.bvMpqO/{tap.log,setup.log,environment,exit-code}`、`tmp/ai-tools-vetbtf8s/`、集計は`tmp/snapshot-full-result.json`。統合branchの787件を転記していない。

34 skipはDesign Hook未materializeの12件、既定opt-inの21件、`TEST_PLAYWRIGHT_PACKAGE`未指定の実Playwright配布fixture 1件。Design Hookは上記のsource-selected隔離frozen配布gateで13/13成功しているが、全suiteの735通過には合算しない。認証・実モデル、実Herdr／隔離依存、6言語devShell生成等のopt-inと、変更していないPlaywright配布fixtureは今回実行しない。APM auditの組織policy enforcement、ARM Linux／Darwinの実機実行も未確認として残す。

全suite後の変更は本記録の検証結果とレビュー状態だけで、実行source・test・依存・検証環境を変更していない。最終記録もStandards／Specで確認し、commit後にclean状態と公開対象のdiffを確認して`git-push-topic`／dotfiles自身のPR作成へ進める。後続単位のPRは未作成・保留のまま。merge／live applyは今回の完了境界に含めない。Tool Snapshotの公開を更新全体やlive配備の完了とは扱わない。

最終記録とPR草稿のレビューもStandards／Specとも未解決指摘0件。追記後の6 CLI metadata／outputとcanonical `with-env` outputが全suite時と同一であることを確認した（`tmp/snapshot-final-output-check.log`）。実行source・test・依存・検証環境は不変のため全suiteを繰り返さず、検証結果と保留状態をcommitして公開する。

## 通常APM後続単位の追跡（2026-10-13）

PR [#397](https://github.com/treflebonbon/dotfiles/pull/397) は `ef64dd3b6a2787a8b4b46d53d88649a9270dfa9f` へmerge済み。ユーザーは配備済みと報告し、親がlive source一致を確認した。上記の分割時点の履歴を保持し、保留だった通常APM18 dependencyのmanifest／native lockと関連期待値は [通常APMの分割記録](ordinary-apm-pr-20261013.md) に対応付ける。Impeccable／Matt部分、一般Nix／言語／npm／汎用helper等の後続PRは未作成・保留。通常APMの公開を更新全体やlive配備の完了として扱わない。

通常APM後続の対応実装commitは `d8adb3a12125dd23f7186ff9a0dccb5e152c5211`、公開branchは `dev/refresh-ordinary-apm-20261013`。同branch自身のcanonical全suiteは769件（735通過・34 skip・失敗0、exit 0）で、詳細と保留一覧は上記の通常APM分割記録を参照する。通常APMのmerge／live配備はこの承認範囲に含めない。

通常APMの対応先は [後続PR #398](https://github.com/treflebonbon/dotfiles/pull/398)。通常APMの分割・検証・レビュー・commit・topic push・PR作成は完了し、merge／live配備とImpeccable／Matt／一般Nix／言語／npm／汎用helper等の保留は残る。

## Impeccable後続単位の追跡（2026-10-13）

上記は各PR公開時点の履歴。現在はPR #397／#398がmain `7af6a0a` へmerge済みで、ユーザーは両方を配備済みと報告し、親がlive source／lock一致を確認した。保留Impeccableのskill 4.5.2／engine 0.1.14は `dev/update-impeccable-20261013` の [独立分割記録](impeccable-pr-20261013.md) に対応付ける。ADR-0045 Decision 3とADR-0053の一体検証で、Impeccableのmanifest／native lock／Nix package／tests／runtime版表記だけを採用予定とする。Matt等の残差分は統合成果 `864880c` に保持し、後続PR未作成・未配備のまま。更新全体は未完了。

Impeccable対応実装commitは `83a8f38`。このbranch自身のcanonical全suiteは769件（747通過・22 skip・失敗0、exit 0）、候補の実Design Hook 13件を全suite内で実行し、2軸事前レビューも指摘0件。最終記録／PR草稿を確認してtopic公開へ進む。今回のImpeccable live配備と、残る別単位の保留は未完了。

Impeccableの対応先は [後続PR #399](https://github.com/treflebonbon/dotfiles/pull/399)。実装 `83a8f38`／検証記録 `e7b0d7b` の同topicを `git-push-topic` で公開し、PR作成時のlocal／upstream／PR HEAD一致を確認した。最終記録の時制1文の指摘は修正・再確認済みで、未解決レビュー指摘はない。ImpeccableのPR公開まで完了、merge／live配備とMatt等の残保留は未完了。

## Matt Pocock後続単位（2026-10-13）

先行PR #397／#398／#399はmerge・配備済みという引継ぎを受け、sourceでは開始HEAD `e333f8a` と一致する。Matt候補 `49dd158d1076134a641b33efb035946536778336` は今回の独立branchで実ordered gate Decision 1–7と別runtimeのnative生成・frozen・audit・bytes／ledger比較を通過し、sourceへ採用した。19 non-Matt dependencyは全field不変。詳細と今回の実検証境界は [Matt後続記録](mattpocock-pr-20261013.md) を参照する。採用直後の計画では、採用後の個別検証・2軸レビュー・canonical全suite・PR公開を後続phaseとした。Mattは未merge・未配備、一般Nix／言語／npm／固定CLI／汎用helper等の残差分は引き続き保留で、更新全体は未完了。過去の検証結果を今回の成功へ転記しない。

Mattの対応実装commitは `4e6f129`。採用後個別53件は全通過、2軸レビューの未解決指摘0件、このbranch自身のcanonical全suiteは769件（747通過・22 skip・失敗0、exit 0）で、実Design Hook 13件も全suite内で通過した。最終記録／PR草稿を確認して公開へ進む。検証境界と残保留は [Matt後続記録](mattpocock-pr-20261013.md) に追跡し、Mattのmerge／live配備と更新全体は未完了のまま。
