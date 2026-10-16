# Impeccable PR分割・公開（2026-10-16）

## 現在の依頼と範囲

ユーザーの「ok」は提示済み3本文を使う通常APM・Impeccable・user Nixの分割・検証・topic push・PR作成の承認。Codexのビルドは禁止、merge・live applyは対象外。baseはmain `300ffc81704f04f09df33de62dbf348a48578b5d`。同じvalidated worktree `/home/ubuntu/.codex/worktrees/591a/dotfiles`のbranch `chore/update-impeccable-20261016`でこの単位だけをmain向けに公開する。

ADR-0045 Decision 3の独立性、ADR-0053のskill／engine一体採用、runtime/skill-harness.mdの隔離native lock／frozen／audit／配布照合、docs/conventions.mdの分割追跡・公開前全Batsを適用する。元の統合branch `chore/update-tools-skills-20261016`／`85756fb`と実装`5e4d79d`は参考で、統合全suiteの成功をこのbranchへ転記しない。

## 予定変更と分割対応

| 元のfile／部分 | このPRと対応先 |
| --- | --- |
| `apm.lock.yaml` | main baselineからImpeccableだけを更新したnative lockを生成。通常APM部分は`chore/update-apm-skills-20261016`へ分離し、このbranchの候補外19 dependencyはmainと同じfieldを保つ。 |
| `apm.yml` | Impeccable pin `5bf0a069`を採用。 |
| `docs/research/update-tools-skills-20261016.md` | 元branchに保持し、このPRには追加しない。現在の範囲・今回検証は本記録を正本とする。 |
| `private_dot_config/nix-devshell/flake.lock` | `chore/update-user-nix-20261016`へ分離。 |
| `private_dot_config/nix-devshell/packages/impeccable.nix` | engine 0.1.15と公式3 asset hashを採用。 |
| `runtime/skill-harness.md` | Impeccable現行版表記だけ採用。 |
| `tests/apm-runtime.bats` | Impeccable pin／hash期待値だけ採用し、通常APM値はmainを維持。 |
| `tests/impeccable-engine.bats` | engine 0.1.15期待値を採用。 |

他2単位の対応先は上表のbranch。各単位の公開・merge・配備は別状態として追跡する。3件はmain向けの独立PRであり、共有lock／test期待値はmerge順に応じて再整合する。

## このbranchの検証計画

source外の新しいHOME／cwd／全XDGで実manifestとmain baseline lockからnative生成する。frozen hash不変、audit、候補外19 dependency・root metadata・共有owner ledger不変、両target各46 skillの実bytes／hash／frontmatterを照合する。公式engine assetは先行取得済みの固定hashを再利用する。

source-selected CLI outputを`--no-codex-build --shell wsl`で確保し、このbranchの実Nix engineとlauncherでDesign Hook 13件、3-system評価、2軸レビュー、canonical全suiteを実行してから公開する。ARM実機と認証・実モデル等の既定opt-inは未検証のまま明記する。

## 分割sourceへのnative採用

今回の隔離runtimeでAPM 0.33.0のnative生成・frozen no-rewrite・audit 10/10が成功した。main baselineに対して候補外19 dependencyは全field不変。root metadataは不変で、ledgerはImpeccable単独ownerの56 content hashだけ変更し、残る1,408 recordと全owner／active_ownerは不変。既存helperで20 dependency・両target各46 skill・全bytes／hash／frontmatter・追加削除0を照合した。

native lockをそのままsourceへ採用し、通常APMの変更は含めていない。user flakeの3-system checkとcommon root checkはexit 0。source-selected Codexは既存`/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1`で、engine／WSL Playwright outputは先行検証と同じ。今回のcanonical成功は完了後に追記する。

証拠は`/tmp/codex/publish-tools-skills.5wTc8t/impeccable-apm/`、`impeccable-{deployment.log,ledger.json,user-check.log,packages.json}`。この段階ではbranch未公開・未merge・未配備。

## 分割branchの公開前検証結果

canonical対象HEADは `971ca0c9f92991ab8c948c488abcade0b2f9db0b`。このbranchで `verify-ai-tools.py --no-codex-build --shell wsl -- python3 scripts/verify-canonical.py` を実行した。全862件中841成功・21既定skip・失敗0、verifier／runner／commandの終了コードはすべて0。全Batsの実測は 1566.01 秒。Design Hook 13件とPlaywright runtime 2件の必須fixtureは15件すべてskipなしで成功した。

開始前後のHEAD、全tracked 602 fileのbytes／mode、runtime実体／hashは一致し、HEAD不一致と証拠照合エラーは0。6 AI CLIのsource-selected output・実path・実versionも照合した。Codexは既存 `/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1` を再利用し、Codex source buildは実行していない。

上記の分割sourceへのnative採用に加え、このbranchのskill 4.6.0 launcherとengine 0.1.15で全suiteを確認した。通常APMの更新を含まないmain baselineとの組合せでも、Design HookとPlaywrightの必須fixtureはすべて成功した。

分割後のStandards／Specレビューは各0件。レビュー対象は本canonical対象HEADのmain `300ffc8` との差分で、統合branchの結果は使用していない。

今回のcanonical証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/canonical-run.3njfer06/` の `before.json`／`after.json`／`result.json`／`runner-path`、AI CLI証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/ai-tools-5w_95t8e/`。集計・起動条件・公開前の不変照合は `/tmp/codex/publish-tools-skills.5wTc8t/impeccable/` に保存する。

検証後の追記は本結果記録だけとし、公開前に記録以外の全tracked内容と保存済みruntime実体／hashを再照合する。ARM2 systemの実機起動と認証・実モデル等の既定opt-in 21件は未検証。隔離APMの組織policy enforcementはwarning付きskipで、その適合は未検証。

この時点で全3 branchの分割検証は成功済み、topic push／PR作成へ進む。merge・live applyは未実施で、更新全体の配備完了とは扱わない。

## PR公開結果

この単位は [428](https://github.com/treflebonbon/dotfiles/pull/428) としてmain向けに公開済み。初回公開HEADは `7f11bfd49c6ab12ddd5f987391d2b3291ad0a690`。検証済みHEADからの差分は本検証記録だけで、記録以外の全tracked内容と13 runtime pathの実体／hashが一致した。

分割先の公開先は[通常APM #427](https://github.com/treflebonbon/dotfiles/pull/427)、[Impeccable #428](https://github.com/treflebonbon/dotfiles/pull/428)、[user Nix #429](https://github.com/treflebonbon/dotfiles/pull/429)。各PRの公開・merge・配備は個別状態として追跡する。いずれも未merge・未配備で、通常APM／Impeccableの共有lockとtest期待値はmerge順に応じて再整合する。更新全体の配備は未完了。
