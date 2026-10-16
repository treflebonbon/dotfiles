# 通常APM PR分割・公開（2026-10-16）

## 現在の依頼と範囲

ユーザーの「ok」は提示済み3本文を使う通常APM・Impeccable・user NixのPR分割・検証・topic push・PR作成を承認する。Codexのビルドは禁止。merge・live applyは含まれない。先行の「PR公開は未依頼」という記録は実装phase時点の状態で、今回の承認で更新する。

baseはremote mainの`300ffc81704f04f09df33de62dbf348a48578b5d`。先行base `0ddac49`からの追加はHerdrの調査文書だけ。validated task worktree `/home/ubuntu/.codex/worktrees/591a/dotfiles`を継続利用し、branch `chore/update-apm-skills-20261016`で通常APMだけをmain向けに公開する。元の統合branch `chore/update-tools-skills-20261016`／`85756fb`は変更せず保持する。

ADR-0045 Decision 2–4、runtime/skill-harness.mdのnative lock／既存runtime再利用／PR公開、docs/conventions.mdの分割追跡と公開前全Batsを適用する。通常APMは採用済みsnapshotとAPM 0.33.0を使い、AI snapshotはCodexビルド禁止とcleanup回帰により今回不採用とする。

## 予定変更と分割対応

| 元のfile／部分 | このPRと対応先 |
| --- | --- |
| `apm.lock.yaml` | shadcn payloadとOrca2件のrevision-onlyだけ採用。Impeccable部分は`chore/update-impeccable-20261016`へ分離し、main baselineから別native lockを生成する。 |
| `apm.yml` | このPRでは不変。Impeccable pinは同Impeccable branchへ。 |
| `docs/research/update-tools-skills-20261016.md` | `f260884`時点の先行調査だけ採用し、現在の公開phaseは本記録を正本とする。統合状態のImpeccable／最終全suite追記は元branchに保持し、各単位の今回検証へ転記しない。 |
| `private_dot_config/nix-devshell/flake.lock` | `chore/update-user-nix-20261016`へ分離。 |
| `private_dot_config/nix-devshell/packages/impeccable.nix` | Impeccable branchへ分離。 |
| `runtime/skill-harness.md` | Impeccable現行版表記はImpeccable branchへ分離。 |
| `tests/apm-runtime.bats` | 通常APMのSHA／content hash期待値だけ採用。Impeccable期待値はImpeccable branchへ分離。 |
| `tests/impeccable-engine.bats` | Impeccable branchへ分離。 |

通常APM sourceは元実装`f260884`を新mainへ適用した`a7c7eca`。他2単位は対応branchを作成して個別検証後に公開し、未公開・未merge・未配備の間は更新全体の完了と扱わない。3件ともmain向けの独立PRとし、共有lock／test期待値はmerge順に応じた再整合が必要となる。

## このbranchの検証計画

source manifest／lockと先行通常APM runtimeのbyte一致を確認し、既存helperの空candidate planで全配布・両target各46 discovery・hash・frontmatter・追加削除0を再照合する。先行native generation／frozen hash不変／auditの証拠は参照元として明示する。今回branchでsource-selected CLI outputを`--no-codex-build --shell wsl`で確保し、3-system評価、2軸レビュー、canonical全suiteを実行する。統合branchの862件をこのbranchの成功として転記しない。

## 分割branchの公開前検証結果

canonical対象HEADは `6d8d6a38adeb6598020c50a243a58d2cf608e3f9`。このbranchで `verify-ai-tools.py --no-codex-build --shell wsl -- python3 scripts/verify-canonical.py` を実行した。全862件中841成功・21既定skip・失敗0、verifier／runner／commandの終了コードはすべて0。全Batsの実測は 1572.03 秒。Design Hook 13件とPlaywright runtime 2件の必須fixtureは15件すべてskipなしで成功した。

開始前後のHEAD、全tracked 603 fileのbytes／mode、runtime実体／hashは一致し、HEAD不一致と証拠照合エラーは0。6 AI CLIのsource-selected output・実path・実versionも照合した。Codexは既存 `/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1` を再利用し、Codex source buildは実行していない。

source manifest／lockと再利用runtime `/tmp/codex/update-tools-skills.PW07sN/ordinary-apm` のbyte一致を確認し、空candidate planの配布照合がexit 0。20 dependency、両target各46 skill、実bytes／hash／frontmatter、追加削除0を確認した。先行native生成・frozen no-rewrite・audit 10/10は同一lockの証拠として再利用する。元のledger比較もshadcn単独ownerの4 hashのみ変更、残る1,460 recordと全owner／active_owner不変を確認済み。今回の再照合は `/tmp/codex/publish-tools-skills.5wTc8t/ordinary-deployment.log`、元のnative証拠とledgerは `/tmp/codex/update-tools-skills.PW07sN/ordinary-apm/` と `ordinary-ledger.json`。

分割後のStandards／Specレビューは各0件。レビュー対象は本canonical対象HEADのmain `300ffc8` との差分で、統合branchの結果は使用していない。

今回のcanonical証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/canonical-run.yef80zn4/` の `before.json`／`after.json`／`result.json`／`runner-path`、AI CLI証拠は `/home/ubuntu/.codex/worktrees/591a/dotfiles/tmp/ai-tools-0mdyaw6w/`。集計・起動条件・公開前の不変照合は `/tmp/codex/publish-tools-skills.5wTc8t/ordinary/` に保存する。

検証後の追記は本結果記録だけとし、公開前に記録以外の全tracked内容と保存済みruntime実体／hashを再照合する。ARM2 systemの実機起動と認証・実モデル等の既定opt-in 21件は未検証。隔離APMの組織policy enforcementはwarning付きskipで、その適合は未検証。

この時点で全3 branchの分割検証は成功済み、topic push／PR作成へ進む。merge・live applyは未実施で、更新全体の配備完了とは扱わない。

## PR公開結果

この単位は [427](https://github.com/treflebonbon/dotfiles/pull/427) としてmain向けに公開済み。初回公開HEADは `38f33581f0a69b44b0d9074569e53edc8e1245e0`。検証済みHEADからの差分は本検証記録だけで、記録以外の全tracked内容と13 runtime pathの実体／hashが一致した。

分割先の公開先は[通常APM #427](https://github.com/treflebonbon/dotfiles/pull/427)、[Impeccable #428](https://github.com/treflebonbon/dotfiles/pull/428)、[user Nix #429](https://github.com/treflebonbon/dotfiles/pull/429)。各PRの公開・merge・配備は個別状態として追跡する。いずれも未merge・未配備で、通常APM／Impeccableの共有lockとtest期待値はmerge順に応じて再整合する。更新全体の配備は未完了。
