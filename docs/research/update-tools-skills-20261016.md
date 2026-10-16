# ツール・スキル更新（2026-10-16）

## 現在の依頼と更新境界

今回の要件原文は「$implement ツールとスキルの更新」。`implement` に従い、調査・実装・検証・2軸レビュー・commitまで進める。PR公開・merge・live applyは依頼に含まれない。

開始点はmain `0ddac49`。Codex native worktree `/home/ubuntu/.codex/worktrees/591a/dotfiles`、branch `chore/update-tools-skills-20261016` でphysical root・HEAD・clean・worktree Git dir・common dirを確認した。live sourceはprimary checkoutを指す。

ADR-0045 Decision 1–4に従い、Tool Snapshot、通常APM、Impeccable、Mattを独立した更新単位として扱う。同ADRの2026-09-01 amendmentではTool Snapshotの先行mergeを通常APM採用の前提とする。`docs/conventions.md` の更新追跡・新規source build前の方針確認、ADR-0047の独立品質floor期待値、ADR-0053のengine分離も適用する。過去initiativeの検証結果や承認は今回の結果・承認として扱わない。

## 計画

- 導入済みAI snapshot、全20 APM dependency、一般Nix／npm／固定CLIの更新候補を調べる。
- Tool Snapshotは入口で確認したdefault HEAD `64f24d6169b8e5996e0c3a3ae696bdf11806b34e` に固定する候補。pin／native lock／関連期待値／採用理由だけを変更し、既存バイナリのsandbox回帰とcache可用性を先に確認する。
- 通常APMは全selected subtreeを比較し、実差分のあるexact pinのみ候補とする。floatingのrevision-onlyとpayload変更を区別し、隔離runtimeのnative lock／frozen不変／audit／両target配布を検証する。
- Impeccableはskill／engineとDesign Hook gateを一組で判断する。Mattは公式full setが同一revisionのため更新不要の見込み。
- 新しいlogicや汎用helperを追加せず、変更に必要な既存testの独立期待値・runtime採用記録を揃える。source buildが必要な候補は、既存配布経路を確認し所要時間と継続保守の負担を提示してから方針を合わせる。

## 候補調査

| 対象 | 現行 | 候補／状況 |
| --- | --- | --- |
| llm-agents snapshot | `998b9f26` | `64f24d61`、調査中 |
| Claude Code | 2.1.296 | 2.1.301 |
| Codex | 0.162.1、cleanup patch付き | 0.163.0、配布binaryの回帰確認前 |
| Copilot CLI | 1.0.96 | 1.0.98 |
| Antigravity CLI | 1.3.3 | 1.3.6 |
| Herdr | 0.9.3 | 0.9.5 |
| APM／code-review-graph | 0.33.0／2.3.9 | 同版 |
| Matt／Remotion／Modern Web Guidance | 現行exact pin | default HEADと一致、pin維持 |
| Impeccable | `d631a882`／engine 0.1.14 | HEAD `5bf0a069`、selected payload比較前 |

## ユーザーによる追加制約

「codexのビルドはしない」を適用する。Codex 0.163.0の既存cleanup patch付き候補output `/nix/store/0gggxysjq2d4p4nb7vz97nvw7raxld46-codex-0.163.0` はローカルにもNumtide cacheにも存在しない。新規source buildを実行せず、ADR-0045の単位全体のfallbackに従ってAI snapshotと品質floorを維持する。candidateの評価と `--max-jobs 0` のcache取得確認はsource buildとは区別する。Tool Snapshotを変更しないため、通常APMは開始点の採用済みAPM 0.33.0で進める。

## 検証・採否

Impeccable候補4.6.0／engine 0.1.15は3 systemの公式release assetを固定hashで取得した。候補launcherとx86_64-linux実binaryを使うDesign Hook gateは13件全通過・skipなし・exit 0。公式release assetの取得でありソースビルドは行っていない。

一般Nixはrootの`nixpkgs`とuser flakeの直下`nixpkgs`だけを更新候補とする。固定された言語・Node・AI補助sourceは実解決版を比較し、版が変わらないpinは維持する。Tool Snapshot配下の推移的inputは変更しない。対象fileは両`flake.lock`と本記録、必要な関連期待値に限る。

通常APMの隔離生成と一般ツールの候補調査を継続する。過去branchの成功を今回の結果へ転記しない。

### 通常APMの採用

APM 0.33.0でsource外のHOME／cwd／全XDGを分離し、実manifestからnative lockを生成した。全20 dependencyの前後fieldを比較し、shadcn `30a58d44`→`c2477f31` のpayload変更と、Orca computer-use／orchestration `1b9a408b`→`9c863a6f` のrevision-onlyだけを採用する。後者のselected content hashは不変。Matt・Remotion・Modern Web Guidanceのdefault HEADは現行exact pinと一致する。orca-cliも最新HEADのselected `SKILL.md`がpinの配備bytesと同一なのでexact pinを維持する。Herdrのskillはbinary 0.9.3との対応を保ち、0.9.5へ単独更新しない。

shadcnの実差分は`SKILL.md`と`rules/chat.md`の2 fileで、Trace／CodeBlockを用いるassistant activity／tool outputの指針を追加する。採用済みfileのhashをbase lockへ照合してから候補と比較した。新規／削除fileは0。

同じruntimeのfrozen installはexit 0でlock SHA-256不変、auditは10/10・exit 0。Git remoteのない隔離cwdで組織policy enforcementはwarning付きskipとなり未検証。既存配布helperは20 dependency・両target各46 skill・全file bytes／hash／frontmatter・追加0／削除0を検証した。root metadataは不変、1,464 ledger recordのうちshadcn単独ownerの4 content hashだけが変わり、残る1,460 recordと全owner／active_ownerは不変。sourceにはnative lockをそのままコピーし、独立test期待値だけを更新した。

証拠は`/tmp/codex/update-tools-skills.PW07sN/ordinary-apm/`のgeneration／frozen／audit logとlock-sha256、同親のordinary-deployment／ordinary-ledgerに保持する。source lockの再整形は行っていない。

### 一般ツール候補

固定CLIのflyline 1.9.0／gwq 0.1.2／waza 0.38.10／gws 0.22.5は最新tagと一致し、Playwright CLI 0.1.22／design.md 0.4.0もregistryの最新版と一致する。root npmはminimum release ageを適用した範囲で更新なし。studioの直接依存もmanifestがregistryのwanted／latestと一致する。既存packageや生成distを書き換えない。

root `nixos-unstable`候補`55bfb4d7`とuser stable候補`7529d323`を評価し、全直接packageのversionを開始点と比較した。rootのversionは全て不変なのでrevision-onlyのlock更新を採用せず開始lockを維持する。userの直接packageで変わる版はtmux 3.6a→3.7bのみ。user lockの直下`nixpkgs`だけを更新し、llm-agents subtree、言語／Node／AI補助sourceは不変にする。root／userの3-system flake checkはexit 0（実機buildではなく評価）。証拠はgeneral-metadata.jsonと各flake-check.log。

通常APMの関連検証`tests/apm-runtime.bats`／`tests/apm-cache-refresh.bats`は全件通過・exit 0。root TypeScriptの`bunx tsc --noEmit`もexit 0。全suiteとcommit済み差分の2軸レビューは全更新単位が揃ってから一度行う。
