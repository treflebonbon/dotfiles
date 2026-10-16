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
