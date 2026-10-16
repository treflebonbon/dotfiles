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
