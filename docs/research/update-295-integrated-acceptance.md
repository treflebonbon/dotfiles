---
type: research
title: "Update #295: Integrated source acceptance"
description: 全更新の採否、親19・子57受入条件、統合検証と受入後の配備手順
tags: [update, verification, nix, apm, templates]
---

# 全更新のsource受入記録（Issue #295）

2026-09-10。親[#283](https://github.com/treflebonbon/dotfiles/issues/283)、子#286〜#295を同じvalidated worktree/branchで扱う。個別候補の採否は確定した。最終full Batsの再実行と本統合文書の2軸レビューは進行中であり、この時点では全体完了とはしない。live配備は受入・merge後に残す。

## 全対象の採否索引

各記録は旧版・入口で固定した候補・取得経路・採用値・維持/保留理由・実行証跡を含む。表の短縮revisionの完全値は各記録とsource lockを正本とする。

| 単位 | 採用・維持・保留 | 全件棚卸し・証跡 |
| --- | --- | --- |
| #286 | root nixpkgs d6524a…、TypeScript7.0.2、oxfmt0.67.0、oxlint1.82.0、OSV Action2.5.1/scanner2.3.8 | [採用記録](update-286-quality-tools.md) |
| #287 | stable nixpkgs104a7c…、Node24.19.0、Python3.13.15、gh2.100.0、kubectl1.36.3。Node24系列を維持 | [採用記録](update-287-user-environment.md) |
| #288 | AI snapshot e320800…、Claude2.1.267、Codex0.154.0、Antigravity1.2.0。FastMCP3.4.7、defuddle0.19.3、markitdown0.1.7。floor・モデル・権限維持 | [採用記録](update-288-ai-tools.md) |
| #289 | 通常17依存を全件比較。Remotion4.0.523のpayloadを更新。floating4件はrevision-only、本文不変のexact pinは維持 | [採用記録](update-289-ordinary-apm-skills.md) |
| #290 | skill/launcher4.3.1 cd12f866…＋固定engine0.1.5を同時採用。管理hookの配線・判断境界維持 | [採用記録](update-290-impeccable.md) |
| #291 | Matt1.2.3・25スキル、6654f6b6…維持。上流3cca18b3…の選択payload不変、ordered候補gateは適用外・未実施 | [採用記録](update-291-matt-pocock.md) |
| #292 | CLI0.1.19、Dogfood1.63.0。既存Nix Chromium1217/1228と互換。native executable解決だけを修正、WSL供給・所有権維持 | [採用記録](update-292-playwright-dogfood.md) |
| #293 | flyline1.8.0、gwq0.1.1、design.md0.4.0、waza0.38.7採用。gws0.22.5維持 | [採用記録](update-293-fixed-clis.md) |
| #294 | Rust1.98.1、Gleam OTP29採用。Go1.27.1はgolangci-lint非互換で保留しGo1.26.7維持。Elixir1.20.4/OTP29.0.6、Perl5.42.0、Bun1.3.13を既存channelで確認 | [採用記録](update-294-language-templates.md) |

通常APM17依存にImpeccableとMatt collectionを加えた全19 dependencyを確認し、hub/Claudeの43スキルを維持した。Playwright skillはNix所有、Dogfoodのツール依存はlocal skill所有のまま。CIは既存全Action pinを棚卸しし、OSV Actionだけを更新、出力互換性のためexport-resultsを明示した。6言語テンプレートは独立repoで解決し、ユーザーflakeのlockを流用していない。

未収録のBun/Node等やFastMCP/parserの上流との差、AI同梱ツールの維持値は各全件表に記録した。Go1.27.1の保留は実際のlint互換性に基づく。新しいchannel・override・installer・skill membershipは追加していない。

## 最終統合検証

| 検証 | 結果 | 実行コマンド・証跡 |
| --- | --- | --- |
| 採用sourceのNix評価/build | 確認済み | root全6shellとuser全6shell。最終userは`playwright-source-flake-check.log` / `playwright-source-wsl-build.json`。root defaultも既存browser経路でbuild済み |
| 最終source型検査・lint | 確認済み | root固定flake内で`tsc --noEmit`、変更TS/MJSの`oxlint`、`final-source-quality.log` exit0。各commitのlefthookも成功 |
| 隔離chezmoi dry-run | 確認済み | `verify-final-source-dry-run.py`、`final-source-dry-run-result.json`。init/apply --dry-run exit0、隔離HOME全パス・内容不変 |
| APM native再現性 | 確認済み | #290の実manifest由来install/frozen/audit。lock SHA256 `144bf375db3942b1185fc5d73ebcb4965121b27e52bed1ef40b717849fd93c53`。後続はAPM source不変、全配布hash一致 |
| 実Impeccable gate | 確認済み | `tmp/update-290/engine-hook-gate.log` 14/14、`managed-failure-gate.log` 1/1。最終fullも実engine/launcherを明示 |
| 実6言語template gate | 確認済み | `templates-all-green-result.json`、`templates-all-green-retry.log`。6/6、skip0。後続変更はtemplatesとhelperに影響しないため再利用 |
| 最終full Bats | 未確認・再実行中 | `run-final-regression-retry.py` → `final-regression-retry.log` / `final-regression-retry-result.json`。短い隔離TMPDIRで全676件を再実行 |
| 最終2軸review | 統合文書の追加確認待ち | `6412429...2d9aa85`はStandards規約違反0/smell0、Spec0。#295のcommit差分を両軸で追加確認 |

上の相対ログ名は原則`tmp/update-283/`に置く。ログはローカル一時証跡であり、PRの読者は各採用記録から版・結果・限界を確認できる。

初回の最終full Batsは676件を完走しexit1、668 TAP ok（うち19skip）・8失敗だった。annotation2件と既存GitHub/model/resolver/proxy socket6件が、二重の`nix develop`により深くなったTMPDIRでAF_UNIXパス上限に達した。Playwrightの同じ上限は旧CLIにも存在する。`final-failure-evidence/`と初回`final-regression-result.json`を保持し、同じannotation2件を短いTMPDIRで再実行して2/2 PASSを確認した。source・テスト期待値は変更せず、再fullでは最内側のshellで短い専用TMPDIRを明示する。初回を成功扱いしない。

APM関連の「41/41」は実ログどおり40実行PASS・1 runtime mount skipへ訂正した。sourceの`.agents`をruntimeがmountする条件はrootにも適用される。native APMの実体・ownership・discovery検証は別途成功しており、このskipで代替していない。

## 親19 ACのVerification Matrix

| AC（原文） | 種別 | 実行コマンドまたは既存証跡 | 結果 | 未確認理由 |
| --- | --- | --- | --- | --- |
| **#283-AC1 — 全対象の棚卸し**: repo編集用・ユーザー用の2 devShell、個別固定Nixパッケージ、npm依存、ローカルskill内のツール依存、全APM dependency、6言語テンプレート、CIの固定Actionについて、現行・候補・取得経路・採否・検証結果または未確認理由を記録する。 | CLI/infra | 全対象の採否索引と各単位の全件表 | 確認済み | — |
| **#283-AC2 — 既存経路の維持**: repo編集環境のunstable channel、ユーザー環境とテンプレートのstable channel、AI snapshotと個別固定パッケージの既存取得経路を維持する。別経路や新規overrideを必要とする候補は、必要性を示して個別判断に戻し、無断で追加しない。 | CLI/infra | 各flake/input/packageの差分と固定候補表 | 確認済み | — |
| **#283-AC3 — Node.js 24 LTS**: 共通Node.jsは24 LTS系列で更新し、26 Current系列へ変更しない。宣言と実際のpackage出力が一致する。 | CLI/infra | 最終shellのnode --version = v24.19.0、Node24属性 | 確認済み | — |
| **#283-AC4 — 候補の固定と採用根拠**: 各更新作業の入口で候補を確認し、そのrevision・版を固定して検証する。実行バイナリは安定版を候補とし、外部スキルは既存のexact pinまたはfloating dependencyの検証契約に従う。検証中に上流HEADを追い続けない。 | CLI/infra | 各単位の入口記録・完全revision・native lock | 確認済み | — |
| **#283-AC5 — AIツールの互換性**: 導入済みAIツールセットの実際の版・起動を確認する。品質floorはsnapshot版と自動同期せず、具体的な運用上の根拠がある場合だけ変更する。既存のモデル・権限・workflowの利用方針を維持する。 | CLI/infra | AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | — |
| **#283-AC6 — Nix環境の検証**: repo編集用・ユーザー用の該当devShellを対応3 systemで評価し、実行可能なhostでbuildと導入CLIの起動を確認する。他platformの評価、cache確認、実機実行を区別して報告する。 | CLI/infra | root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト、最終user全6shell | 確認済み | ARM実機なし。liveはmerge後 |
| **#283-AC7 — 言語候補の評価**: Go 1.27系とRust 1.98.1以降の互換な安定版を候補として評価する。Elixir/Erlang・Gleam・Perl・Bunも既存channel内で解決される版と上流との差を確認する。未収録版は理由付きで保留できるが、調査対象から省かない。 | CLI/infra | TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行。Go1.27.1実lint失敗を記録 | 確認済み | — |
| **#283-AC8 — 6テンプレートの独立動作**: Go・Rust・Elixir/Erlang・Gleam・Perl・Bunをそれぞれ独立した新規repoへ展開し、lock生成、3 system評価、hostでのdevShellと共通実行入口による言語起動を検証する。言語周辺ツールとの組み合わせも確認する。 | CLI/infra | TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#283-AC9 — npm品質ツールの整合**: TypeScriptのメジャー更新、lint・format関連依存を既存の品質ゲートで検証する。peer dependencyの整合とBun実行環境・型定義の整合を確認し、型定義だけを最新版へ揃えない。 | CLI/infra | root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin、最終source型検査・lint、Bun1.3.13/bun-types1.3.13 | 確認済み | — |
| **#283-AC10 — APM payloadの採否**: 全dependencyの選択payloadを比較し、実体差分とrevisionのみの差を区別する。選択payloadが不変のexact pinを新しさだけで動かさず、スキルのmembership・配布ownershipを維持する。 | CLI/infra | native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | — |
| **#283-AC11 — APMの再現性**: 隔離runtime内でnative lockを生成し、同じlayout・target・transportのfrozen install前後でlockが不変であること、audit成功、共有hubとClaude側のdiscovery・payload一致を確認する。生成lockの手編集や再整形に依存しない。 | CLI/infra | native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip、#290 native pair/source byte一致 | 確認済み | — |
| **#283-AC12 — Impeccableの同時採用**: 候補skill・launcher・固定engine・管理hookを同じ互換性ゲートで検証する。実engineを通してper-edit/Stop、provider出力、quiet・fail-open、設定・cacheの所有権、抑制操作の既存境界を確認し、片側だけを採用しない。 | CLI/infra | native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#283-AC13 — Matt Pocockの条件付きゲート**: 調査時点の選択payloadが不変なら現pinを維持する。実装入口で更新が必要になった場合は、managed full setの既存ordered gate全体を通し、部分採用しない。 | CLI/infra | whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合、候補変更条件は不成立 | 確認済み | 候補ordered gateは適用外・未実施 |
| **#283-AC14 — Playwrightの組み合わせ**: CLI、browser package、Dogfood runner、管理adapterの組み合わせを検証し、既存のbrowser所有権とWSL2境界を維持する。実機未確認の範囲を明記する。 | CLI/infra | 全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 確認済み | ARM実機なし。liveはmerge後 |
| **#283-AC15 — 補助CLIとCI Action**: 個別固定CLI、文書変換・設計用CLI、CIの固定Actionを評価する。Action自身の版と同梱ツールの版を区別し、既存wrapper・reusable workflowの契約と必要なasset/hashの整合を確認する。 | CLI/infra | 全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件、文書変換CLI、OSV Action/scanner別版とexport-results | 確認済み | — |
| **#283-AC16 — 回帰検証**: 変更に該当する既存品質ゲート、型検査、関連テスト、full Bats suite、必要な隔離chezmoi dry-runを実施する。失敗やskipを根拠なく成功として扱わず、必須の候補実体検証ができない変更は採用済みとしない。 | CLI/infra | 上記最終統合検証、再full・統合文書レビューの結果待ち | 未確認 | 最終再full・文書レビュー進行中 |
| **#283-AC17 — 失敗時の整合**: 失敗原因を調べ、既存契約を維持できる範囲の修正を行う。採用条件を満たせない場合は、その互換性単位の採用済み組み合わせを保持し、独立した他候補の結果と分けて報告する。 | CLI/infra | Go保留、Rust vtable/Gleam OTPのRED→GREEN、TS7 clean install、TMPDIR根因の記録 | 確認済み | — |
| **#283-AC18 — sourceとliveの区別**: validated task worktreeでsourceを変更・検証する。受入・merge前にliveへ配備しない。受入後はlive sourceから反映し、source側の検証結果と通常環境での最終確認を区別する。 | CLI/infra | validated worktree source、隔離dry-run HOME不変、下記live配備手順 | 確認済み | ARM実機なし。liveはmerge後 |
| **#283-AC19 — 完了記録**: 全対象の採用・維持・保留と根拠、ACごとの検証結果、未確認のplatform・実機動作、後続の配備手順をまとめ、影響を受けた正本文書と整合させる。 | CLI/infra | 本記録の全76 ACと採否索引、最終結果の確定待ち | 未確認 | 最終再full・文書レビュー進行中 |

## 子10件・57 ACのVerification Matrix

AC原文は公開済みticketとbyte/hash照合した計画から転記した。条件付きのMatt候補gateは、実体不変による条件評価を確認済みとし、実施したgateのPASSとは扱わない。

| AC（原文） | 種別 | 実行コマンドまたは既存証跡 | 結果 | 未確認理由 |
| --- | --- | --- | --- | --- |
| **#286-AC1**: repo編集用Nix input、npm品質依存、CI固定Actionを棚卸しし、各対象の採否と根拠を記録する。unstable channelとNode.js 24 LTSを維持する。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 確認済み | — |
| **#286-AC2**: TypeScriptのメジャー版を候補として、既存の型検査とlint・formatを通す。Ultracite・oxlint等のpeer条件と、Bun実行版・型定義の整合を確認する。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 確認済み | — |
| **#286-AC3**: 対応3 systemでrepo devShellを評価し、hostで該当shellと品質ツールを起動する。現時点の導入済みツールと互換性を保つための最小修正は本チケットに含める。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 確認済み | — |
| **#286-AC4**: OSV-Scanner Actionのpin実体と同梱scanner版を区別し、reusable workflowの既存入出力・権限契約を維持する。Action lintを通す。workflow dispatchは行わない。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 確認済み | — |
| **#286-AC5**: frozen install、型検査、該当品質ゲート、full Bats suiteで採用する組み合わせを検証し、失敗・skip・実機未確認の範囲を記録する。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#286-AC6**: 担当対象の採用・維持・保留をまとめ、後続のブラウザー検証が参照するrepo側browser packageの確定値も残す。 | CLI/infra | [#286記録](update-286-quality-tools.md)、root全6shell評価・WSL build、品質CLI、frozen npm、TS7型検査、Action lint/pin | 確認済み | — |
| **#287-AC1**: stable channelを維持して候補revisionを固定し、Nixから供給する汎用ランタイム・横断ツールを全て棚卸しする。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 確認済み | — |
| **#287-AC2**: Node.js 24 LTSを維持し、Python・Bunを含む他のランタイムは既存経路で解決される実際の版と上流との差を記録する。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 確認済み | — |
| **#287-AC3**: 対応3 systemのdefault/WSL devShellを評価し、hostの該当shellをbuild・起動する。WSL browser boundaryを維持する。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 確認済み | — |
| **#287-AC4**: 既存のAI snapshot、固定CLI、hook、browser adapterと同時に利用できることを確認する。必要な最小互換性修正を後続チケットへ先送りして、本チケットを不合格のまま完了しない。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 確認済み | — |
| **#287-AC5**: 既存のNix devShell・キャッシュ・起動契約テストとfull Bats suiteを実行し、採用する共通package集合を確定する。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#287-AC6**: 各汎用ツールの採否、対応systemの評価とhost実行の差、後続が参照するpackage集合とbrowser packageの確定値を記録する。 | CLI/infra | [#287記録](update-287-user-environment.md)、user全6shell評価・WSL build、75公開CLI probe、startup/floor/cacheテスト | 確認済み | — |
| **#288-AC1**: 実装入口でAI snapshot候補を一度確認してimmutable revisionへ固定し、全導入済みAI CLIの現行・候補・実際の版を記録する。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | — |
| **#288-AC2**: Codex/Herdrのdirect packageと他AI CLIのshared overlayを維持する。品質floorは具体的根拠がある場合だけ変更し、モデル・権限・workflow設定を維持する。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | — |
| **#288-AC3**: 同じsnapshotのpackage定義を参照するcode-review-graphと、FastMCP・parser・文書変換CLIの既存source-only経路を合わせて評価し、依存floorとCLI/MCPの既存動作を検証する。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | — |
| **#288-AC4**: 対応3 systemでNixを評価し、hostで該当shell build、各AI CLIのversion/help・起動、隔離Herdrの必要な起動確認を行う。cache確認と実機動作を区別する。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | ARM実機なし |
| **#288-AC5**: 後続で使うAPM binaryを確定し、現行skill payloadを隔離runtimeへfrozen配備できることを確認する。skill payload自体は本チケットで更新しない。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 確認済み | — |
| **#288-AC6**: 関連する実package出力・品質floor・起動テストとfull Bats suiteを通し、採用または維持するsnapshot、APM版、関連依存の根拠を記録する。 | CLI/infra | [#288記録](update-288-ai-tools.md)、AI全6shell評価・WSL build、25CLI/MCP probe、Herdr隔離起動終了、strict Codex設定検証 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#289-AC1**: ImpeccableとMattを除く全APM dependencyの選択payloadを比較し、実体変更とrevision-only変更、exact/floatingの違いを記録する。Orca/Herdrも対象に含む。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 確認済み | — |
| **#289-AC2**: payloadが不変のexact pinは新しさだけで進めず、互換性を確認した通常スキルを採用する。membership・cleanup・配布ownershipを維持する。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 確認済み | — |
| **#289-AC3**: 隔離runtimeで実manifestからnative lockを生成し、同じlayout・target・transportでのfrozen install前後でlockが不変であることを確認する。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 確認済み | — |
| **#289-AC4**: auditと共有hub/Claude側のdiscovery・payload一致を確認し、既存APM runtime・cache refresh・workflow契約テストを通す。生成lockは手編集・再整形しない。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 確認済み | — |
| **#289-AC5**: full Bats suiteと必要な隔離dry-runを実行し、非互換候補は直前の採用済み組み合わせを保持する。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#289-AC6**: 通常スキルの全採否と、Impeccable/Mattの後続単位が使う確定済みmanifest/lock baselineを記録する。 | CLI/infra | [#289記録](update-289-ordinary-apm-skills.md)、native APM install/frozen/audit、全17 selected tree、43/43 discovery・1,204配布hash・ownership、関連40 PASS/1 skip | 確認済み | — |
| **#290-AC1**: 安定releaseのskill/launcherとengineを候補として固定し、既存のAPMとNixの配布経路を維持する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#290-AC2**: 対応3 systemのasset/hashとNix評価、hostでの実engine起動を検証し、skill・engine・管理hookを同じ単位で採否する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#290-AC3**: 実engineを通してper-edit/Stop、Claude/Codex provider出力、quiet・timeout・fail-open、失敗出力の破棄を既存の公開入口から検証する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#290-AC4**: 設定/cacheの所有権、理由付きignore-value、file/rule全体の抑制に関する既存の判断境界を維持する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#290-AC5**: 隔離native lock・frozen no-rewrite・audit・discovery、関連hookテスト、full Bats suiteを通し、非Impeccable payloadの意図しないdriftを確認する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#290-AC6**: 片側だけの採用をせず、採否理由とMatt単位が参照する確定済みnon-Matt baselineを記録する。 | CLI/infra | [#290記録](update-290-impeccable.md)、native APM install/frozen/audit、56 selected files・3asset/hash、実engine14件＋managed failure1件、関連40 PASS/1 skip | 確認済み | — |
| **#291-AC1**: 実装入口で現pinと上流候補の選択payload・membershipを比較する。実体が不変ならexact pinを維持し、比較根拠を成果物として記録する。空commitや不要なpin更新を作らない。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | — |
| **#291-AC2**: 更新が必要な実体差分がある場合は、full setを一つのimmutable候補として既存ordered gate全体に通す。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | 実体不変のため候補採用条件は不成立。ordered gate未実施 |
| **#291-AC3**: 候補を採用する場合は隔離materialization、frozen no-rewrite、audit、discovery、workflow契約、full Bats suite、隔離dry-runを順序どおり実行する。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | 実体不変のため候補採用条件は不成立。ordered gate未実施 |
| **#291-AC4**: 採用時は非Matt lock/deploymentのdriftを判定し、作業用一時pinを含むlockを正式sourceへコピーしない。実manifest由来のnative lockで再現性を確認する。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | 実体不変のため候補採用条件は不成立。ordered gate未実施 |
| **#291-AC5**: 契約変更が必要な候補は現pinを維持して理由を記録する。維持のみの場合もAC13の条件評価と両targetのfull-set整合を示し、未実施の候補ゲートを成功とは報告しない。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | — |
| **#291-AC6**: 最終的な維持または更新の判断、根拠、確認済み/未確認の範囲を記録する。 | CLI/infra | [#291記録](update-291-matt-pocock.md)、whole skills tree/plugin blob同一、selected25/74files・両target148hash・198ledgerのread-only照合 | 確認済み | — |
| **#292-AC1**: Playwright CLI・配布skill・runner依存・browser package・adapterの現行と候補の組み合わせを棚卸しする。 | CLI/infra | [#292記録](update-292-playwright-dogfood.md)、全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 確認済み | — |
| **#292-AC2**: 既存の固定パッケージ経路でCLIとnpm lock/hashを更新し、Dogfood依存も互換性を確認して採用する。 | CLI/infra | [#292記録](update-292-playwright-dogfood.md)、全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 確認済み | — |
| **#292-AC3**: 対応3 systemのNix評価とhostの起動を確認し、default/WSLの既存入口、headless/headed選択、終了処理と所有権契約を維持する。 | CLI/infra | [#292記録](update-292-playwright-dogfood.md)、全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 確認済み | — |
| **#292-AC4**: 既存WSL adapter・Chrome所有権・Dogfoodテストと、実行可能な環境での実起動を確認する。未確認の実機範囲と理由を明記する。 | CLI/infra | [#292記録](update-292-playwright-dogfood.md)、全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 確認済み | ARM実機なし |
| **#292-AC5**: 関連品質ゲートとfull Bats suiteを実行し、共通基盤と組み合わせた採否を記録する。 | CLI/infra | [#292記録](update-292-playwright-dogfood.md)、全6shell評価・host build、native CLI/runner4件、WSL CLI/annotation/cleanup、実Dogfood14件＋契約107件 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#293-AC1**: 独立した固定CLIを漏れなく棚卸しし、対象ごとの現行・候補・配布経路を記録する。現行最新や更新不要なものも理由を残す。 | CLI/infra | [#293記録](update-293-fixed-clis.md)、全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件 | 確認済み | — |
| **#293-AC2**: 既存経路のrelease asset/hashまたはnpm lock/hashを候補に合わせ、対応systemの選択と既存コマンド名・aliasを維持する。 | CLI/infra | [#293記録](update-293-fixed-clis.md)、全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件 | 確認済み | — |
| **#293-AC3**: flylineのシェル連携、作業管理CLI、design.mdの入口、wazaの起動を、公開コマンドや既存の統合テストで確認する。外部アカウントへの書込みを検証の前提にしない。 | CLI/infra | [#293記録](update-293-fixed-clis.md)、全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件 | 確認済み | — |
| **#293-AC4**: 対応3 systemのNix評価、hostのbuild/起動、関連品質ゲートとfull Bats suiteを実施し、独立したCLIごとに採否を判断する。 | CLI/infra | [#293記録](update-293-fixed-clis.md)、全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#293-AC5**: 非互換候補は原因と維持・保留理由を残し、担当範囲の全対象について最終版と検証結果を記録する。 | CLI/infra | [#293記録](update-293-fixed-clis.md)、全3system×2shell評価・source host build/start、19公開CLI probe＋flyline PTY、関連9件 | 確認済み | — |
| **#294-AC1**: Goの新系列とRustの修正版を候補にし、他の4テンプレートも既存stable channel内の選択肢・実際の版・上流との差を記録する。 | CLI/infra | [#294記録](update-294-language-templates.md)、TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#294-AC2**: Goの言語周辺ツール、Elixir/Erlangの組み合わせ、Perlの別属性とperlnavigator等の互換性を確認する。未収録の候補は理由付きで保留する。 | CLI/infra | [#294記録](update-294-language-templates.md)、TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#294-AC3**: 6テンプレートをそれぞれ独立した新規repoへ展開し、生成先でlockを確定する。既存の共通実行入口の契約を維持する。 | CLI/infra | [#294記録](update-294-language-templates.md)、TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#294-AC4**: 実Nixモードの既存統合テストで3 systemを評価し、hostでdevShellと共通実行入口の両方から言語を起動する。opt-inテストのskipを成功として扱わない。 | CLI/infra | [#294記録](update-294-language-templates.md)、TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#294-AC5**: 関連品質ゲートと必要な回帰検証を行い、6言語全てについて採用・維持・保留と検証結果を記録する。 | CLI/infra | [#294記録](update-294-language-templates.md)、TEMPLATE_WITH_ENV_REAL_NIX=1で6独立repo・lock・3system・devShell/with-env・言語周辺ツール実行 | 確認済み | — |
| **#295-AC1**: 全対象の現行・候補・採用版、維持・保留理由を一つの結果として統合し、担当漏れ・重複・食い違いを解消する。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#295-AC2**: 19受入条件を個別証跡と統合sourceへ対応付け、packageの実際の版、APM payload、テンプレートの組み合わせを確認する。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#295-AC3**: 組み合わせが変わった範囲で全体回帰、Nix/CLI、APM再現性、hook、テンプレートの既存検証を実行する。個別成功を統合成功と取り違えない。新しい変更の影響を受けない証跡は再利用する。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#295-AC4**: 必要な隔離chezmoi dry-runを行い、3 system評価とhost実機動作、skip・未確認のplatformや機能を区別したVerification Matrixを作る。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#295-AC5**: 影響する正本文書を最終採否と整合させ、受入・merge後のlive sourceからの配備と通常環境確認の手順・残作業を記録する。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |
| **#295-AC6**: source側の完了とlive側の未実施/実施済みを区別して報告し、live非配備のままlive確認済みとは扱わない。 | CLI/infra | [#295記録](update-295-integrated-acceptance.md)、上記の最終統合検証、76 AC照合、source dry-runと配備手順 | 未確認 | 最終再full・統合記録レビュー進行中 |

## 未確認範囲と証跡の再利用

- hostはx86_64 Linux/WSL2。ARM LinuxとApple SiliconはNix評価・固定asset/hash/layout・該当cache確認までで、実機起動は未実施。通常WSLのWindows CDP経路と、WSLホスト上で明示したLinux native互換性probeを区別する。
- 初回fullの19skipはruntime mount1件、raw/isolated runtime・model/GitHub/MCP/dependencyのopt-in15件、実6言語template1件、with-env実Nix2件。templateの必須実体gateは別途6/6 PASS。残りは未実施として保持し、認証済みmodel/APIや新しいruntime境界の確認を主張しない。
- APM auditのorganization enforcementはremoteのない隔離cwdで適用外。local includeなし。管理対象target/discoveryの検証をskipした意味ではない。
- Impeccableの任意画像API、課金API・画像生成品質は未検証。上流engineの画像生成既定モデル変更は#290に明記した。管理Claude/Codexのモデル・権限選択は変更していない。
- 今回のfullに含まれない実6言語gate、各固定asset、native APM、AI/補助CLIの個別probeは、対応するsource/lockが後続で変更されていない範囲で再利用した。

## 受入・merge後のlive配備

以下は後続の手順であり、このtask worktreeでは実行していない。

1. PR受入・merge後、`chezmoi source-path`が示すlive sourceへ移動し、受入branchに対象commitが含まれることを確認する。通常の同期を行い、未mergeのtask worktreeからapplyしない。
2. 利用中のManaged Playwright/Dogfood sessionとDashboardを既存の通常終了手順で閉じ、`managed-chrome-owner status`で所有者を確認する。通常Chrome profileを変更しない。
3. 既存checkoutをTS6からTS7へ移す場合は、依存を使う処理を止め、既存node_modulesをsource外の新しい一時directoryへ退避してから新lockで`bun install --frozen-lockfile`する。Bun1.3.13のin-place更新で残るtsserver symlinkを避ける。退避物の削除はこの手順に含めない。
4. live sourceから`chezmoi diff`で差分を確認し、受入済みsourceに対して`chezmoi apply`する。既存のcache refresh・APM・local skill・Codex managed syncの配布経路を使う。lockを手編集したり、別installerで上書きしない。
5. 新しい通常shellでNode24、AI/補助CLI、Impeccable engine-probe、skill discovery、Playwrightの通常起動・終了を確認する。source側の各PASSとは別のlive確認記録として残す。配備で失敗した場合は原因・保持された採用pairを確認してから既存の再試行手順を使う。

本作業ではmerge、default branch push、workflow dispatch、Issue本文/状態変更、live applyを行っていない。最終PRは親と直接の子のAC coverageを照合してから作成し、Issueを閉じるAPIは呼ばない。
