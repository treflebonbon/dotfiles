# user Nix PR分割・公開（2026-10-16）

## 現在の依頼と範囲

ユーザーの「ok」は提示済み3本文を使う通常APM・Impeccable・user Nixの分割・検証・topic push・PR作成を承認する。Codexのビルドは禁止、merge・live applyは対象外。baseはmain `300ffc81704f04f09df33de62dbf348a48578b5d`。同じvalidated worktree `/home/ubuntu/.codex/worktrees/591a/dotfiles`のbranch `chore/update-user-nix-20261016`を使う。

docs/conventions.mdの分割追跡・公開前全Bats・新規Codex build前の停止、runtime/skill-harness.mdのruntime再利用とPR公開、ADR-0045の更新単位の独立性を適用する。元の統合branch `chore/update-tools-skills-20261016`／`85756fb`と実装`6ec4da4`は参考資料。統合全suiteの結果をこのbranchの成功へ転記しない。

## 予定変更と分割対応

| 元のfile／部分 | このPRと対応先 |
| --- | --- |
| `apm.lock.yaml` | mainを維持。通常APMは`chore/update-apm-skills-20261016`、Impeccableは`chore/update-impeccable-20261016`へ分離。 |
| `apm.yml` | mainを維持。Impeccable branchへ分離。 |
| `docs/research/update-tools-skills-20261016.md` | 元branchに保持し、このPRには追加しない。現在の範囲・今回検証は本記録を正本とする。 |
| `private_dot_config/nix-devshell/flake.lock` | 直下stable nixpkgsだけ`240fddad`→`7529d323`を採用。 |
| `private_dot_config/nix-devshell/packages/impeccable.nix` | mainを維持し、Impeccable branchへ分離。 |
| `runtime/skill-harness.md` | mainを維持し、Impeccable branchへ分離。 |
| `tests/apm-runtime.bats` | mainを維持し、通常APM／Impeccable各branchへ分離。 |
| `tests/impeccable-engine.bats` | mainを維持し、Impeccable branchへ分離。 |

直接packageのversion変更はtmux 3.6a→3.7bのみ。AI snapshot／品質floor／Codex cleanup patchとsingle-job設定、言語・Node・AI補助source、root flake lockは同じ入力を使う。他2単位は対応branchを用意し、公開・merge・配備を個別に追跡する。3件はmain向けの独立PRで、通常APMとImpeccableの共有lockはmerge順に応じて再整合する。

## このbranchの検証計画

source manifest／lockとmain baselineの隔離frozen runtimeをbyte一致させ、既存helperの空candidate planで全配布・両target各46 discovery・hash・frontmatter・追加削除0を照合する。baseline frozen installはlock SHA-256不変、audit 10/10を今回確認済み。source-selected CLIを`--no-codex-build --shell wsl`で起動し、tmux実版、3-system評価、2軸レビュー、canonical全suiteをこのbranchで確認する。ARM実機と既定opt-inの未検証を明記する。

## 分割branchの公開前検証結果

canonical対象HEADは `9258f64407b502de5c643339b2635351c5fead31`。このbranchで `verify-ai-tools.py --no-codex-build --shell wsl -- python3 scripts/verify-canonical.py` を実行した。全862件中841成功・21既定skip・失敗0、verifier／runner／commandの終了コードはすべて0。全Batsの実測は 1558.35 秒。Design Hook 13件とPlaywright runtime 2件の必須fixtureは15件すべてskipなしで成功した。

開始前後のHEAD、全tracked 602 fileのbytes／mode、runtime実体／hashは一致し、HEAD不一致と証拠照合エラーは0。6 AI CLIのsource-selected output・実path・実versionも照合した。Codexは既存 `/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1` を再利用し、Codex source buildは実行していない。

source manifest／lockとmain baselineの隔離frozen runtime `/tmp/codex/publish-tools-skills.5wTc8t/base-apm` のbyte一致を確認し、空candidate planの配布照合がexit 0。20 dependency、両target各46 skill、実bytes／hash／frontmatter、追加削除0を確認した。今回のfrozen installはlock SHA-256不変、audit 10/10。user flakeの3-system checkはexit 0、rootは同じ入力のcommon checkを参照する。証拠は `user-nix-deployment.log`、`user-nix-flake-check.log`、`common-root-check.log`、`base-apm/`（いずれも `/tmp/codex/publish-tools-skills.5wTc8t/` 配下）。source-selected tmuxの実起動は `user-nix/tmux-smoke.json` に記録し、`tmux 3.7b` と一致した。

分割後のStandards／Specレビューは各0件。レビュー対象は本canonical対象HEADのmain `300ffc8` との差分で、統合branchの結果は使用していない。

今回のcanonical証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/canonical-run.gzsnig7p/` の `before.json`／`after.json`／`result.json`／`runner-path`、AI CLI証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/ai-tools-iuhjcvon/`。集計・起動条件・公開前の不変照合は `/tmp/codex/publish-tools-skills.5wTc8t/user-nix/` に保存する。

検証後の追記は本結果記録だけとし、公開前に記録以外の全tracked内容と保存済みruntime実体／hashを再照合する。ARM2 systemの実機起動と認証・実モデル等の既定opt-in 21件は未検証。隔離APMの組織policy enforcementはwarning付きskipで、その適合は未検証。

この時点で全3 branchの分割検証は成功済み、topic push／PR作成へ進む。merge・live applyは未実施で、更新全体の配備完了とは扱わない。
