# 汎用検証 helper の採否・実装（2026-10-14）

## 依頼と範囲

承認済みの「保留中の汎用検証 helper を既存手順との重複と継続利用から採否整理する」依頼に基づき、2 helper を repo 内の限定した手動入口として採用する。checkout は `/home/ubuntu/orca/workspaces/dotfiles/decide-verification-helpers-20261014`、branch は `dev/decide-verification-helpers-20261014`、base は #405 採用後の `1813c865897e0b8977a12a7b698977e6eafb00b2`。readiness と同 session の model／effort／cwd は親が照合済みで、子も Git 所属を自分の環境から確認した。

[更新追跡規約](../conventions.md#ツールスキル更新の追跡とレビュー)、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の独立した更新単位・検証境界、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) の独立 floor 判定、[ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の Matt 専用 gate を維持する。

read-only の `decision.json` を親が照合し、`parent-decision-confirmation.json` の `confirmed:true` と10 file scope を確定した。この照合は追加ユーザー承認ではない。対象は `scripts/verify-ai-tools.py`／`scripts/verify-apm-deployment.mjs`、対応する2 Bats、`docs/conventions.md`／`runtime/skill-harness.md`、本記録と既存の一般 Nix／root npm／studio 記録への現在追跡だけとする。

参考成果 `864880c0498d9b274c506183a2087f0863d674f7` は読み取り資料として使い、当該 helper／tests だけを内容確認して採用した。`docs/architecture.md` の Codex 説明・参照変更、一般的な test lifecycle 規約変更、Matt の過去研究参照置換は今回への採用を却下する。Nix／npm／APM の依存・pin・lock、AI／Codex 設定、cleanup patch、studio source／dist、production browser 環境、既存 runner／gate／CI の配線は変更しない。

## 採否と変更前後

| 候補 | 採否 | 既存 gate との差と維持費 |
| --- | --- | --- |
| AI helper | 採用 | 品質 floor tests は package output の採否を検査する。helper は shellHook 前の HOME／全 XDG 分離と、実 PATH が source-selected output を選ぶことを検査する。6 CLI の pname／bin mapping を維持する費用があるため、更新時の手動入口とする。 |
| APM helper | 採用 | native audit は現在 lock と配備の整合を検査する。helper は accepted dependency と計画した候補集合・追加／削除を比較する。native layout に追従する費用はあるが、通常更新と frozen runtime 再利用で一時 script を複製する手順を減らせる。 |

変更前は両 helper と tests が source に存在せず、分割 PR で参照版を Git 管理外へコピーしていた。#397／#399／#400／#402 に AI probe の利用記録があり、#398 の APM plan・配備 log、#404／#405 の参照コピーと実行 evidence を読み取り確認した。#405 の一時 AI helper にだけある output 不在停止 guard は、未キャッシュ環境の利用まで一律に拒否するため常設版へ移植しない。#401 のモデル設定単位での helper 実利用は未確認で、全 PR が同じ版を実行したとは断定しない。

AI helper は不正 JSON、欠落／重複 metadata、型・path 欠損でも原文・診断・exit 1 を保存して shell と後続コマンドを開始しない。評価失敗・version 失敗・後続コマンドの非0終了も evidence に保持する。評価／起動 subprocess のシグナル終了は `128 + signal` の shell 終了コードへ揃え、呼出元と保存した終了コードを一致させる。同じ版の旧 output 拒否、shellHook 前の HOME／全 XDG 分離、6 CLI 照合、`--` 以降の引数は参照版の契約を維持する。

APM helper は読取り処理を維持し、`{"candidates":[]}` を含む object 形式を案内する。directory を含む `deployed_files` の追加／削除は事前計画と完全一致を要求する。候補外 dependency の変更は、更新前に `ref`／`resolved_ref` を持たない floating dependency の `resolved_commit` だけを許容する。通常 guide に SKILL 用 frontmatter は要求せず、`SKILL.md` の name／description、実 bytes／hash、runtime 外 path／symlink、両 hub discovery を検査する。

root lock metadata と owner／active_owner／共有 owner ledger の前後比較、計画した候補の期待 revision／版／package type、payload の意味、未記録 file 全体、対話 loader は helper の責務外である。生成・frozen no-rewrite・native audit と独立 ledger 比較、Matt ordered gate を継続する。再利用する runtime は source pair と byte 一致を先に確認する。helper の PASS を全 lock 不変・live 配備完了と混同しない。

## 今回の検証

AI の不正 JSON に関する新テストは参照版で exit-code 欠落を検出して red となり、診断・原文・終了コード保存の最小修正後に green となった。初回 helper 関連は25件（25 pass／0 fail／0 skip）。この件数は既存参考版18件と別の今回結果であり、後段 canonical の件数へ合算しない。既存 APM／floor／devShell 契約を含む関連検証は83件（83 pass／0 fail／0 skip）、exit 0、96.779秒で成功した。TAP plan は1つで、1–83の連続番号、bailout なしを確認した。

採用した AI helper から現 source の user／repo 両 wsl devShell を shellHook 前から HOME／全 XDG で隔離し、6 CLI の絶対 output と実版を照合した。Claude 2.1.296、Codex 0.162.1、Copilot 1.0.96、Antigravity 1.3.3、APM 0.33.0、Herdr 0.9.3が一致し、helper／後続 probe は exit 0。既存の cleanup patch 付き Codex output `/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1` を再利用し、Rust 再 build を開始していない。

同環境で source-selected Playwright browser-free output `/nix/store/r1mia04ilacqdfh4blbgb3hibpjsclap-playwright-cli-0.1.22` と Impeccable engine `/nix/store/8d2qywl01wrwpvykrgxg5r9jg7gxw981-impeccable-0.1.14` の path／実版を確認した。source pair と byte 一致する既存 frozen runtime `/tmp/fixed-clis-apm.mHuaBN` を採用 APM helper で読み取り照合し、20 dependency、両 target 各46 skill、追加0／削除0、exit 0。lock SHA-256 `df0f5c410d795058a44fcdf5fdc59462881753df609d74a94c6b4d4a205da968` は前後不変だった。今回は APM 再解決・frozen install・audit を実行しておらず、既存の成功を今回の成功へ転記しない。

実起動後の初回一時 probe は、Copilot の正式 version 出力末尾の句点を版番号の続きと誤判定して exit 1 となった。helper の6 CLI 照合と起動は成功していた。probe のみ訂正し、初回 log／result と runtime を保持して再確認した。source の変更や test assertion の緩和による回避はしていない。

証拠は Git 管理外 `tmp/verification-helpers-20261014/` の `decision.json`／`parent-decision-confirmation.json`、`red-metadata.tap`／`green-metadata.tap`、`helper-related-result.json`／`related-tests-result.json`、`implementation-runtime-result.json`／`implementation-runtime-launch-result.json` と各 log に保持する。修正後の `helper-related-after-signal-result.json`／`red-signal.tap`／`green-signal.tap` も同 directory に保存する。初回実装 HEAD の evidence は `implementation-round-1/` に分けて保持し、修正後の結果と混同しない。実装 commit 後の完全 HEAD、関連／format／runtime／独立レビュー結果は同 directory へ保存して親へ返す。

初回実装 `63a245e` の独立レビューは Standards 0件／Spec 1件だった。Spec は subprocess のシグナル終了時に evidence が `-15`、呼出元の終了コードが241となる不一致を指摘した。CLI 回帰テストで red を確認し、既存 runner と同じ `128 + signal` への変換を評価・起動両経路へ加えて green にした。修正後の helper は26件（26 pass／0 fail／0 skip）、exit 0、5.698秒で成功した。評価と起動の signal 終了は両方143となり、後続 command は抑止された。実 source runtime の再照合も exit 0、27.866秒で成功し、6 CLI・Playwright・Impeccable・既存 APM 配備と lock 不変を再確認した。同じ修正後 HEAD を両軸で再レビューする。未変更の APM／floor／devShell 契約の初回83件は履歴として保持し、修正後 helper の件数へ合算しない。

2回目の `a3adf31` レビューは Standards 1件／Spec 0件。Standards の重複指摘に従い、終了コード変換を同じ script 内の小さな関数へまとめた。共通化後の helper26件（26 pass／0 fail／0 skip、exit 0、5.742秒）と実 source runtime（exit 0、27.189秒）が成功し、正常終了・評価／起動 signal・保存された終了コード・後続 command 抑止を維持した。2回目の evidence は `implementation-round-2/`、最終 helper 結果は `helper-related-final-result.json`／`helper-related-final.tap` に保存する。

## 次の gate と残る境界

関連検証と commit hook を通した同じ実装 HEAD を、Standards／Spec の独立並列 subagent（両方 `gpt-6-luna`／`xhigh`）でレビューする。現在要件・今回採否・適用 ADR と過去参考を区別し、指摘修正後の同 HEAD で両軸0件を確認する。

canonical は実装 HEAD の `parent-confirmation.json` に `confirmed:true` が保存された後に開始する。現 phase では未実施で、過去の769件等を固定期待や今回成功へ使わない。全 suite では新 tests 分も含め plan／pass／skip／fail、各 exit／duration／hash、全 tracked 前後不変、実 Design Hook13件＋Playwright runtime2件の skip0 を実測する。既定 opt-in skip を維持し、成功後は結果文書だけを追記する。topic 公開・通常 PR はその後で、現在の対応先 PR は未確定である。

#397–405 は base へ source 採用済みだが、親の #405 merge 照合時に両 live hub の studio4files は旧版だった。子による live 配備照合・apply は未実施。未キャッシュ Linux の Codex single-job source build、root braces audit exit 1 と magicast 内旧 bundle は未解消のまま維持する。ARM／Darwin 実機、認証／実モデル、APM 組織 policy、GitHub 最新 CI も今回未確認で、更新全体を完了扱いにしない。

## 最終レビュー・親照合・canonical 全 Bats（2026-10-14）

最終実装 HEAD は `6346cd8c714dd659c1581e648cb4a974ac5c3ed1`。同 HEAD を独立並列の Standards／Spec（両方 `gpt-6-luna`／`xhigh`）で再レビューし、両軸0件を確認した。親は scope10 file・clean・現 source byte・helper26件・quality／runtime／APM pair を独立照合し、同 HEAD の `parent-confirmation.json` に `confirmed:true` を保存した。

同 source／test／依存／環境を固定して canonical `lefthook run test` を一度実行し、実測795件（774 pass／21 skip／0 fail）、runner／canonical／launcher exit 0 で成功した。TAP plan は1つ、1–795の連続番号、bailout なし。canonical 本体は985.622秒、環境準備・probe を含む launcher は1013.468秒で、計測境界を区別する。初回83関連は signal 修正前、現 helper26件は修正後の別試行として保持し、過去769件等も含め今回の件数へ合算していない。

開始前に現 source の user／repo 両 wsl devShell を shellHook 前から HOME／全 XDG で隔離し、6 AI output／実版、source-selected Playwright browser-free／Impeccable engine と source pair に一致する既存 frozen APM runtime を照合した。実 Design Hook13件＋Playwright runtime2件は全 suite 内で通過・skip0。全586 tracked file の前後 SHA-256 が一致し、HEAD／clean も不変だった。Nix／npm／APM の再解決や live 配備は行っていない。

21 skip は実 Herdr／Bash 3.2、認証・実モデル／MCP、専用隔離 runtime／dependency gateway、6言語独立生成、public Nix app の既定 opt-in。ARM／Darwin 実機と live studio 配備も未確認で、skip を成功へ含めない。未キャッシュ Linux の Codex source build 要件、root braces audit exit 1、magicast 内旧 bundle と APM 組織 policy／OSV 判定制限を維持する。

TAP は `tmp/test-run.ZwVj2h/tap.log`、SHA-256 は `06e218f24c8f39bc2732636c321bf74f2171a668bda65e1bd7e93b24dd004630`。同 directory に setup／environment／exit-code、今回 evidence に `full-result.json`／`canonical-source-before.json`／`canonical-source-check.json`／`canonical-required-fixtures.json`／`canonical-environment.json`／`canonical-runtime-result.json`／`canonical{,-launch}.exit` と各 log を保持する。成功後は今回の結果・対応先文書だけを確定し、実行 source／test／deps／環境の不変を照合して canonical を反復しない。通常 PR の対応先と公開時 HEAD／CI は次の公開記録へ追記する。merge／apply は行わない。

## 通常 PR の公開結果（2026-10-14）

[通常 PR #406](https://github.com/treflebonbon/dotfiles/pull/406) を実 remote default `main` 向け OPEN・非 draft で作成した。実装・修正・結果記録を `git-push-topic` で非 force 公開し、作成時の local／upstream／actual remote／PR HEAD `213231d3a1f9e2a67d0bf12cc8ca4f0ddbd797f6`、英語 Conventional title `feat: add manual verification helpers`、確定した日本語3節本文の byte 一致を確認した。必須の4研究リンクは公開 HEAD の GitHub blob URL として本文へ設定した。

作成時 HEAD の [scan-pr / osv-scan](https://github.com/treflebonbon/dotfiles/actions/runs/38560910821/job/115841445231) は SUCCESS、[osv-scanner](https://github.com/treflebonbon/dotfiles/runs/115841570111) は NEUTRAL。code-scanning は main の `osv-scanner-full.yml` configuration が PR 側に見つからず、新規 alerts を判定できない警告で、同 check の annotations は0件だった。scan 実行成功と判定制限を区別し、脆弱性なしとは扱わない。workflow の変更は追加しない。

この対応先追記は結果文書だけの変更として同 topic へ commit／push する。最新公開 HEAD の CI と local／upstream／actual remote／PR HEAD、clean、本文 byte／研究 blob byte を最後に照合し、本文の必須研究リンクをその最終 HEAD へ揃える。今回の canonical は一度だけで、582非結果 tracked file・実行 source／test／deps／環境の不変を確認して再利用する。merge／apply は未実施で、helper は未 merge・未配備のまま。更新全体の完了や既報の root／Codex 制限解消とは区別する。
