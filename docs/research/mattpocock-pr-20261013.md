# Matt Pocock後続PR（2026-10-13）

## 現在の依頼と受入境界

ユーザーの「推奨案で進めて」は、保留Matt Pocockを公式27 skillの一組として独立PRへ仕上げ、検証・2軸レビュー・commit・`git-push-topic`・PR作成まで進める承認である。merge、chezmoi apply、他更新単位の公開は含まない。同じnative checkout `/home/ubuntu/orca/workspaces/dotfiles/update-mattpocock-20261013`、branch `dev/update-mattpocock-20261013`、開始HEAD `e333f8a74dc467447e2e4e33aa8ddd531e61ed26` で全phaseを続ける。physical root、branch、HEAD、clean、worktree Git dir、common dirの読み取り確認は成功した。raw isolation adapterへ再起動しない。

適用するのはADR-0042 Decision 1–7のordered gateとDecision 8のnative lock採用、ADR-0045 Decision 4の独立更新単位、ADR-0071の公式27 membership、runtimeのworkflow／安全境界、conventionsの追跡・canonical全suite契約である。親のmodel／effortは変更せず、レビューsubagentは `gpt-6-luna`／`xhigh` とする。

## 候補と予定変更

accepted pin `b0618bc436ad893b3c5e84e55fba86586d34a404` から固定候補 `49dd158d1076134a641b33efb035946536778336` へ進める。新しいupstream HEADは追わない。公式27 membershipとcross-skill契約を維持し、selected差分の `wizard/template.sh` を隔離library fixtureで検証する。外部サービスへのwizard操作は実行しない。

予定変更は `apm.yml` のMatt pin、実manifestから生成する `apm.lock.yaml`、`tests/apm-runtime.bats`／`tests/mattpocock-update-gate.bats`／`tests/workflow-contract.bats` の独立期待値、`runtime/skill-harness.md` の採用記録、本記録と既存3分割記録の追跡である。上流本文、配備先、一般Nix、npm、汎用helperは編集しない。

## 分割で外した変更と対応先

統合成果 `864880c0498d9b274c506183a2087f0863d674f7` と `docs/research/update-tools-skills-20261011.md` のMatt採用節は読み取り参考資料である。過去の769／787件や過去gate成功は今回の結果へ転記しない。元差分の各fileは既存 [Snapshot記録](tool-snapshot-pr-20261013.md)／[通常APM記録](ordinary-apm-pr-20261013.md)／[Impeccable記録](impeccable-pr-20261013.md) に保持し、同fileの部分採用と保留を区別する。

| 更新単位・差分 | 対応先と状態 |
| --- | --- |
| Tool Snapshot／品質floor／FD patch適用終了／cleanup維持 | PR #397、merge `ef64dd3b`。merge・配備済みという引継ぎを受け、開始sourceと照合する。 |
| 通常APM18依存 | PR #398、merge `7af6a0a`。merge・配備済みという引継ぎを受け、候補外として維持する。 |
| Impeccable skill 4.5.2／engine 0.1.14 | PR #399、merge `e333f8a`。merge・配備済みという引継ぎを受け、候補外として維持する。 |
| Matt pin／native lock／独立期待値／runtime採用記録 | このbranch／本記録で実装・検証・レビュー・公開する。未merge・未配備。 |
| root／user一般Nix・言語取得元／6テンプレート／architecture・conventionsの残差分 | 統合成果 `864880c` に保持。後続PR未作成・未配備。 |
| npm／studio package・lock・dist／Playwright package・lock | 統合成果 `864880c` に保持。後続PR未作成・未配備。 |
| fixed CLI（flyline／gwq／waza／Playwright） | 統合成果 `864880c` に保持。後続PR未作成・未配備。 |
| 汎用verify helper／tests／braces記録／統合調査記録の残差分／runtime helper案内 | 統合成果 `864880c` に保持。後続PR未作成・未配備。必要なhelperはGit管理外tmpへ読み取り取得し、配布しない。 |

開始HEADと統合成果の43 file差分を照合した（`tmp/matt-scope-plan.json`）。上記6 fileはMatt部分だけ採用し、既存3分割記録は削除せず追跡を追記する。残る34 fileの対応は以下のとおり。保留の参照先はすべて統合成果 `864880c` で、後続PRは未作成である。

| 今回取り込まないfile | 扱い・対応先 |
| --- | --- |
| `bun.lock`、`package.json` | npm単位へ保留。 |
| `local-skills/domain-modeling-studio/package.json`、`local-skills/domain-modeling-studio/package-lock.json`、`local-skills/domain-modeling-studio/dist/studio.html`、`local-skills/domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` | studio開発依存・生成物の単位へ保留。 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package.json`、`private_dot_config/nix-devshell/packages/playwright-cli-agent/package-lock.json` | Playwright package単位へ保留。 |
| `flake.lock`、`private_dot_config/nix-devshell/flake.lock`、`private_dot_config/nix-devshell/flake.nix` | 一般Nix・言語取得元の単位へ保留。既存AI snapshotは維持する。 |
| `templates/bun/flake.nix`、`templates/elixir/flake.nix`、`templates/gleam/flake.nix`、`templates/go/flake.nix`、`templates/perl/flake.nix`、`templates/rust/flake.nix`、`templates/go/DEVELOPMENT.md`、`templates/rust/DEVELOPMENT.md` | 言語テンプレート単位へ保留。 |
| `private_dot_config/nix-devshell/packages/flyline.nix`、`private_dot_config/nix-devshell/packages/gwq.nix`、`private_dot_config/nix-devshell/packages/waza.nix`、`private_dot_config/nix-devshell/packages/playwright-cli.nix` | 固定CLI単位へ保留。 |
| `scripts/verify-ai-tools.py`、`scripts/verify-apm-deployment.mjs`、`tests/verify-ai-tools.bats`、`tests/verify-apm-deployment.bats` | 汎用helperの配布・testsは保留。読み取り参考のtmpコピーだけ使用する。 |
| `docs/architecture.md`、`docs/conventions.md` | 一般Nix・言語説明や検証入口の残差分を保留。現在の規約を適用する。 |
| `docs/research/braces-response-20261013.md`、`docs/research/update-tools-skills-20261011.md` | 元の調査履歴を参考として保持。今回の実行結果は本記録に置く。 |
| `docs/adr/0045-separate-llm-agents-and-apm-update-units.md` | PR #397の最新snapshot・cleanup採用判断を維持。統合版の古いsnapshot記述への置換は採用しない。 |
| `runtime/ai-runtimes.md` | PR #397の採用記録を維持。一般Nix等の残履歴は保留し、過去snapshotへの置換は採用しない。 |
| `tests/nix-devshell.bats` | PR #397の分割記録参照を維持。Playwright 0.1.22の期待値は固定CLI単位へ保留。 |

同file内で外す差分は、`tests/apm-runtime.bats` のOrca floating revision（native生成結果に必要な場合だけ今回の実解決値を反映）、`runtime/skill-harness.md` の汎用helper案内である。manifest／lockの他19依存は今回の実比較に従い、丸コピーしない。

## 検証計画

source外のHOME／cwd／全XDGとaccepted lockから実APMの専用入口 `tests/mattpocock-update-gate.sh` を実行する。非Matt一時pin、source-selected APM版照合、native生成、候補外・共有owner ledger drift拒否、frozen hash不変、audit、両targetの27 discovery／workflow payload、workflow・cleanup tests、全Bats、isolated chezmoi dry-runのsnapshot不変を順序どおり確認する。fake fixtureは実gate成功の代用にしない。失敗時はaccepted pairを維持する。

Decision 1–7成功後、新しい隔離runtimeで実unpinned candidate manifestから `scripts/generate-apm-lock.sh` を実行し、frozen／audit／実bytes・deployment／non-Matt19 selected hash・ledger不変を確認してnative lockだけを採用する。native floating revision-onlyは理由と状態を記録し、候補外payload更新は別単位へ保留する。

型・format・関連tests後にcommit済み差分を2軸レビューする。指摘を閉じた採用後のsource-selected隔離環境でcanonical `lefthook run test` を一度実行し、TAP plan／連続番号／pass・skip・fail・exitを保存する。実Design Hook runtimeを開始時から明示し、opt-in skipをpassへ合算しない。結果追記だけでは全suiteを反復しない。最終記録・review・commit・cleanを照合後、topic公開と日本語本文のPR作成まで行う。更新全体の完了とこのPRの完了は区別する。

## このbranch自身のordered gateとnative採用

固定候補の公式compareは2コミット差で、配布対象の変更は `skills/engineering/wizard/template.sh` の1 fileのみ。plugin manifest version `1.3.1` と公式27 membershipは不変だった。候補archiveのlibrary部分だけを隔離fixtureへ読み込み、全体の `bash -n`、引用値round-trip、plain double-quoted値の復号、unsafe値拒否、`write_env` のshell変数反映、0600権限をassertした。外部サービス操作は実行していない（`tmp/matt-upstream-comparison.json`、`tmp/matt-wizard-check.log`）。ステージを `run_wizard` にまとめた差分も確認した。

source-selected APM 0.33.0は `/nix/store/wq2wcjgmpcn370kmsszpyx8fyk1wz7x3-apm-0.33.0/bin/apm` で一致した。source外 `/tmp/nix-shell.ZTd7Sm/mattpocock-20261013-44eywnaq` 配下のHOME／cwd／全XDGで、実入口 `tests/mattpocock-update-gate.sh` をfakeなしで実行し、Decision 1–7は順序どおり成功、exit 0。非Matt一時pinと生成版照合、候補外・共有owner drift拒否、frozen lock不変、audit 10/10、両targetの公式27と全46 skill discovery／workflow payload、関連77件（77通過・skip 0・失敗0）、採用前の全769件（747通過・22 skip・失敗0）、chezmoi dry-run前後のHOME snapshot不変を確認した。

gateのlock SHA-256は `757229f7898d446718524e9969c71cdfd672317cad3f6b0246ed3f28dae19cce`。TAP plan 77／769、各番号の連続性、結果件数、失敗0、exit 0と全6 phaseの順序を別途照合した。証拠は `tmp/matt-ordered-gate.log`／同 `.exit`、`tmp/matt-gate-result.json` と保持runtime `gate-tmp/nix-shell.LlSv3z/nix-shell.9kYwI2/mattpocock-update-gate.OKaNaD`。実Design Hook launcherとengineを開始時から明示し、未materializeのskipはなかった。ここでは候補payload評価と、accepted sourceのrepository regressionを区別する。採用後canonical全suiteの成功とは扱わない。

Decision 8では別runtime `native/` の実unpinned candidate manifestとaccepted lockから共通generatorを実行した。一時pinや `--update` は使わず、APM 0.33.0のnative lockを生成。初回auditは一時ランチャーが `TMPDIR` をproject tree内に置いたため拒否された（`native/audit.log`、`tmp/matt-native.log.exit`＝1）。scratchをproject tree外 `native-scratch/` へ修正し、同じ生成物を再auditして10/10成功、exit 0となった。失敗を除外・黙認せず、初回ログを保持している。candidate payloadやlockの手修正はしていない。

frozen前後のnative lock SHA-256は `df0f5c410d795058a44fcdf5fdc59462881753df609d74a94c6b4d4a205da968` で不変。Matt content hashは `sha256:049d4dfaaf2d783feedaf677626385d0dee10a47734f7d86cd006b7258c79aa3`、native `package_type` は `marketplace_plugin` を維持した。19 non-Matt dependencyはrevisionを含む全field不変で、floating revision-only movementも0件だった。両target各46 skill、全配備bytes／file hash／SKILL frontmatter／余剰・不足を照合し、追加0・削除0。全1,464 owner ledgerの構成・owners／active_ownerは不変で、Matt単独所有212 recordのうちwizard 2 fileのhashだけが変わった。共有ownerを含む他recordは全field不変。

成功後の実manifest／native lockだけをsourceへコピーし、Matt pin／hashの独立期待値とruntimeの現行採用記録を更新した。gate用一時pin lock、参考統合lock、汎用helper案内は取り込んでいない。証拠は同runtimeの `native/{generation.log,frozen.log,lock-before,lock-after,audit.log,audit-retry.log,deployment.log,comparison.json}`、`tmp/matt-native-finish.log`／同 `.exit`。auditの組織policy enforcementは隔離cwdにGit remoteがないためwarning付きskipで、baseline 10 checksとは区別する。

## 採用後の個別検証とレビュー入口

`tests/apm-runtime.bats`／`tests/mattpocock-update-gate.bats`／`tests/workflow-contract.bats` はsource-selected user／repo devShellの隔離HOME／全XDGで53件（53通過・skip 0・失敗0）、exit 0。TAP planと1から53の連続番号を照合した（`tmp/matt-individual.log`／同 `.exit`、`tmp/matt-individual-result.json`）。root `bunx tsc --noEmit`、変更manifest／MarkdownのOXC format、`git diff --check`は成功。source manifest／native lockのbytesはDecision 8の生成物と一致する。新しい配布logic／helperは追加せず、pin・期待値の更新には既存fixtureを使った。

採用差分10 fileをcommitし、fixed point `e333f8a74dc467447e2e4e33aa8ddd531e61ed26` のcommit済み差分をStandards／Specへ渡す。現在の承認要件、適用ADR、予定変更、外した全差分と対応先、過去統合成果の参考扱いを区別する。指摘を閉じた後に採用後canonical全suiteを実行し、以下へ結果を追記する。
