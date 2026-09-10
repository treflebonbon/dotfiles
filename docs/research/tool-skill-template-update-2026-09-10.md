---
type: research
title: ツール・スキル・言語テンプレート更新の設計調査
description: 2026-09-10 の grill-with-docs で合意した更新範囲、候補、採用条件と検証範囲。
tags: [research, nix, tools, skills, templates]
timestamp: 2026-09-10
---

# ツール・スキル・言語テンプレート更新

Q1〜Q6の回答と設計全体の最終確認への同意を受け、設計を確定した。候補の列挙は採用や検証成功を意味しない。開始時の source は `6412429243a4326fa2fc748eae445f35f10fcdc9`、作業場所は既存の linked worktree `worktree/brave-meadow-0e68`。

仕様は [Issue #283](https://github.com/treflebonbon/dotfiles/issues/283) に公開し、`ready-for-agent` を付与した。31件のユーザーストーリー、19件の受入条件、検証範囲と実装入口を含む仕様の正本はIssueとし、本書は設計調査の記録として保持する。

## 確定した範囲

- Q1: 今回の更新を行う。更新手順の新規整備や継続的な自動更新は目的に含めない。
- Q2: メジャー版も候補とし、互換性と必要な移行内容を確認して採用を判断する。
- Q3: dotfiles 管理ツール全体を対象にする。AI CLI に加え、汎用ランタイム、シェル・Git・lint・テスト用ツールも棚卸しする。
- Q4: この repo の Go・Rust・Elixir/Erlang・Gleam・Perl・Bun の6言語テンプレートを対象にする。展開済みの別プロジェクトへの移行は含めない。
- Q5: 既存の配布経路で得られる版を優先する。未収録の最新版との差を記録し、追加の配布経路や固定パッケージが必要なものは、必要性を示して個別に判断する。
- Q6: 共通Node.jsは24 LTS系列を維持し、その系列で更新する。

外部から取得する「導入済み Agent Skill セット」と dotfiles 自身が所有する「ローカル skill」は、既存の [用語集](../../CONTEXT.md) の区別を維持する。ローカル skill に同梱されたツール依存はツールの棚卸しに含める。

## 更新経路と既存契約

| 対象 | 正本・現在の経路 | 検証上の境界 |
| --- | --- | --- |
| repo 編集用ツール | root `flake.nix` / `flake.lock`、`nixos-unstable` | lint・format・テスト環境への影響 |
| ユーザー環境 | `private_dot_config/nix-devshell/`、`nixpkgs-26.05-darwin` | 対応3 system の評価と実行可能な host での起動 |
| AI CLI | exact `llm-agents` snapshot `868527bc9eb4e8bee8610fa1d4027fbb37cfc012` | package の実際の版と品質 floor は別管理 |
| 外部スキル | `apm.yml` / `apm.lock.yaml` | 通常 payload、Matt Pocock、Impeccable の互換性ゲートを区別 |
| 個別固定ツール | Nix package 定義、npm manifest / lock | binary・wrapper・関連 skill の組み合わせ |
| 言語テンプレート | `templates/<lang>/flake.nix` | 6テンプレートを独立展開し、生成先で lock と起動を検証 |

[Architecture](../architecture.md)、[Skill harness](../../runtime/skill-harness.md)、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)、[ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) に基づく。APM lock は隔離した runtime layout で生成し、frozen install の前後で不変であることを確認する。worktree から live HOME へ配備せず、受入・merge 後に live source で反映する。

## npm の更新候補

2026-09-10 に公式 npm registry の `latest` を照会した値。現行欄は開始時の manifest / lock に基づく。

| パッケージ | 現行 | 候補 | 一次情報 |
| --- | --- | --- | --- |
| TypeScript | 6.0.3 | 7.0.2 | [registry](https://registry.npmjs.org/typescript/latest) |
| oxfmt | 0.48.0 | 0.67.0 | [registry](https://registry.npmjs.org/oxfmt/latest) |
| oxlint | 1.71.0 | 1.82.0 | [registry](https://registry.npmjs.org/oxlint/latest) |
| Ultracite | 7.8.3 | 7.11.1 | [registry](https://registry.npmjs.org/ultracite/latest) |
| bun-types | 1.3.13 | 1.4.2 | [registry](https://registry.npmjs.org/bun-types/latest) |
| `@playwright/cli` | 0.1.17 | 0.1.19 | [registry](https://registry.npmjs.org/%40playwright%2Fcli/latest) |
| `@google/design.md` | 0.3.0 | 0.4.0 | [registry](https://registry.npmjs.org/%40google%2Fdesign.md/latest) |
| ローカル Dogfood runner の Playwright | 1.59.1 | 1.63.0 | [registry](https://registry.npmjs.org/playwright/latest) |

TypeScript 7 はコンパイラの基盤が変わるメジャー更新であり、版番号の更新だけで互換と判断しない（[公式リリース説明](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)）。この repo は `bunx tsc --noEmit` を品質ゲートに使う。Ultracite 7.11.1 の oxlint peer dependency は `^1.79.0` のため、現行 oxlint 1.71.0 を維持したまま同時採用可能とは扱わない。

Playwright は CLI の npm 依存、Nix の browser package、ローカル Dogfood runner、WSL2 の管理 adapter を横断するため、実際の組み合わせと既存の browser 所有権の契約を検証する。

## Nix と言語の候補

以下は配布元のソースと公式リリースの照合結果であり、この worktree での Nix 評価・build・起動はまだ実施していない。

AI snapshot の候補は [`e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9`](https://github.com/numtide/llm-agents.nix/tree/e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9)。収録 metadata は Claude Code 2.1.263 → 2.1.267、Codex 0.153.4 → 0.154.0、Antigravity 1.1.27 → 1.2.0。APM 0.30.0、Herdr 0.9.0、RTK 0.48.0 は不変。品質 floor は実体の版と自動同期せず、具体的な運用上の根拠がある場合だけ変更する。

テンプレートの共通 channel は調査時点の [`nixpkgs-26.05-darwin` revision `104a7c61006cd22d11c0379663afee90c62273ab`](https://github.com/NixOS/nixpkgs/tree/104a7c61006cd22d11c0379663afee90c62273ab) で確認した。テンプレートには lock を同梱せず、版番号を明記していない言語は生成先で解決する。

| 言語 | 現行テンプレートの選択 | 上流候補・判断材料 |
| --- | --- | --- |
| Go | `go_1_26` | 最新 stable は1.27.1。同 channel に `go_1_27` / 1.27.1 があり属性選択で更新可能。言語周辺ツールとの組み合わせは未検証（[公式履歴](https://go.dev/doc/devel/release)） |
| Rust | stable 1.98.0 | 1.98.1は誤コンパイル修正。rust-overlay に対応 manifest がある（[公式説明](https://blog.rust-lang.org/2026/09/03/Rust-1.98.1/)） |
| Elixir / Erlang | Elixir 1.20 / OTP 29 系 | 同 channel の1.20.4 / 29.0.6は調査時点の公式版と一致（[Elixir](https://elixir-lang.org/docs/)、[Erlang](https://www.erlang.org/downloads.html)） |
| Gleam | `gleam` | 同 channel の1.18.1は公式 release と一致（[release](https://github.com/gleam-lang/gleam/releases/tag/v1.18.1)） |
| Perl | `perl` | 同 channel の5.42.0に対して上流 stable は5.44.0。channel内の別属性の有無と perlnavigator 互換性は未確認（[公式履歴](https://perldoc.perl.org/5.44.0/perlhist)） |
| Bun | `bun` | 同 channel の1.3.13に対して公式版は1.4.2。配布元と上流の差をQ5で扱う（[公式](https://bun.sh/)） |

Go 1.26.8は1.26系列の最新であり、Go全体の最新 stable とは区別する。Bun 1.3 → 1.4 は semver 上の minor 更新。

共通 Node.js は source で `nodejs_24` を選んでいる。公式の現行分類は24がLTS、26がCurrentであり、Q6で24 LTS系列の維持を選択した（[公式リリース一覧](https://nodejs.org/en/about/previous-releases)）。

個別固定ツールの候補は flyline 1.3.0 → [1.8.0](https://github.com/HalFrgrd/flyline/releases/tag/v1.8.0)、gwq 0.0.5 → [0.1.1](https://github.com/d-kuro/gwq/releases/tag/v0.1.1)、waza 0.38.3 → [0.38.7](https://github.com/microsoft/waza/releases/tag/azd-ext-microsoft-azd-waza_0.38.7)。gws 0.22.5は調査時点で変更なし。

CIで使う OSV-Scanner Action も対象候補とする。現在の2 workflowのpinには `v2.3.8` コメントがあり、最新安定版 Action は [v2.5.1](https://github.com/google/osv-scanner-action/releases/tag/v2.5.1)。Action版と同梱scanner版は別で、v2.5.1はscanner 2.3.8を同梱する。採用時は既存pinの実体と reusable workflow の契約を照合する。

## 外部スキルの重点調査

- Matt Pocock: [現pinから上流HEADへの差分](https://github.com/mattpocock/skills/compare/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76...3cca18b368ae95cdbdebbff572ccafa662551015) は repo側の説明・link scriptであり、導入済み25スキルの本文・構成は不変。revisionの新しさだけを理由にexact pinを動かさない。
- Impeccable: 現在のskill 4.2.2 / engine 0.1.3に対し、[skill 4.3.1](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.3.1) / [engine 0.1.5](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.5) が安定版候補。launcherの失敗診断やStop findingの扱いが変わるため、既存の固定engine経路・fail-open・provider出力・設定の所有権を実engineで検証する。同じ互換性単位で採用し、片側だけの更新は行わない。
- Orca: [上流比較](https://github.com/stablyai/orca/compare/de0a91b99fc845c9510340786f807ea1c988859b...a067cccd38e38487772741ebf9d0ea4a8fed8644) で導入済み3スキルの `SKILL.md` は不変。runtime側が取得するguideの変更と、APM選択payloadの変更を区別する。
- Herdr: [v0.9.0](https://github.com/herdrdev/herdr/releases/tag/v0.9.0) が最新安定版であり、上流HEADでも選択skill本文は不変。既存pinを維持する。

この重点調査を全APM dependencyの検証完了とは扱わない。通常のAPM更新では残る依存もselected payloadを比較し、隔離lock生成・frozen no-rewrite・audit・discoveryで採否を確定する。

## 回答から導く実装方針

- repo編集環境は現在のunstable channel、ユーザー環境とテンプレートは現在のstable channelを維持して候補revisionを検証する。`llm-agents` と既存の個別固定パッケージは、それぞれの既存経路で更新する。新しい配布経路を足す変更は、Q5の個別判断に戻す。
- Goは `go_1_27`、Rustは1.98.1を候補とする。他の4テンプレートは同channelで解決される版を確認し、最新版との差を記録する。Perlの別属性の有無は実装入口で調べ、未収録なら保留する。言語以外の共通処理への依存revisionは、必要性を確認せず一律に動かさない。
- TypeScript 7、lint・format系、Playwright、補助CLIは今回の互換性検証の候補に含める。`bun-types` は実行するBunの系列との整合も確認し、型定義だけを最新版へ揃えない。
- 通常APM payloadとImpeccableは既存の別検証境界を維持する。Matt Pocock・Orca・Herdrのexact pinは、調査時点では選択payloadに変更がないため維持する。実装入口で新しい差分が見つかった場合は既存の採用ゲートを適用する。
- 候補は各更新作業の入口で再確認し、その時点のrevision・版を固定して検証する。検証中に上流HEADを追い続けない。
- 互換性を保つための設定・wrapper・テストの修正は候補と一緒に扱う。モデル・権限・workflowの利用方針を変える必要が生じた場合は、新しい判断点として提示する。
- 検証に失敗した候補は原因を調べ、既存契約を保って修正できる範囲を対応する。採用条件を満たせないものは直前の採用済み組み合わせを維持し、理由を残す。互換性を共有する組み合わせの片側だけを採用しない。

## 採用条件と検証範囲

これは実装で満たす条件であり、現時点の実行結果ではない。

| 条件 | 検証方法 | 記録する結果 |
| --- | --- | --- |
| 対象の取りこぼしを防ぐ | 2 devShell、個別Nix package、npm依存、ローカルskill内のツール依存、APM、6テンプレート、CIの固定Actionを棚卸し | 各対象の現行・候補・採用版または維持/保留理由 |
| Node.js 24 LTSと既存の配布経路を維持する | sourceの属性・input・lockと、実際のpackage版を照合 | revision、版、意図しないchannel/系列変更がないこと |
| Nix環境の互換性を維持する | rootとuser devShellで `nix flake check --no-build --all-systems`、hostの該当shell build、導入CLIの起動確認、関連Bats | 対応3 systemの評価とhost実行を区別し、他platformの実機未確認を明記 |
| 6テンプレートが独立して使える | `TEMPLATE_WITH_ENV_REAL_NIX=1 bats tests/template-with-env.bats`。各テンプレートを展開・lock生成し、3 system評価、hostでdevShellとwith-envを実行 | 各言語の実際の版と起動結果。opt-inテストのskipは検証成功にしない |
| npm更新後も品質ゲートが機能する | frozen install、`bunx tsc --noEmit`、変更に該当するlint/formatと既存テスト | TypeScript移行、peer dependency、Bunと型定義の整合 |
| APMを同じ内容で再配備できる | 隔離runtimeでnative lock生成、`apm install --frozen --target claude,codex --https` 前後のlock hash不変、`apm audit --ci`、両targetのdiscovery、関連Bats | selected payload差分、exact pinの採用根拠、materializationの一致 |
| Impeccableの既存hook契約を保つ | 候補skill/launcherと固定engineを同時に検証し、`tests/design-hook.bats`、`tests/impeccable-engine.bats` と関連hook検証を実engineで実行 | per-edit/Stop、provider出力、quiet/fail-open、設定・cacheの所有権 |
| Playwrightの組み合わせを維持する | CLI・browser package・Dogfood依存と管理adapterを照合し、関連テストおよび実行できる環境での起動を確認 | browser所有権とWSL2境界、実機未確認の範囲 |
| repository全体の回帰を防ぐ | 変更に該当するlefthook品質ゲート、全 `bun run test`、必要な隔離chezmoi dry-run | pass/fail/skipとその理由。既知の失敗を根拠なく例外化しない |

source側の更新・検証結果は、採用・維持・保留を全対象について説明できる形にまとめる。liveへの配備と通常環境の最終確認は受入・merge後にlive sourceで行い、source側の検証成功とは区別する。

## 共有理解の確認

ユーザーはQ1〜Q5の推奨案とQ6のNode.js 24 LTS系列を選択し、上記の実装方針・検証範囲をまとめた最終確認にも同意した。未回答の設計分岐はなく、`grill-with-docs` を完了する。具体的な候補の評価・採用は後続の実装作業で行い、本書の調査値と実際の採用結果を区別して記録する。

## チケット化と公開結果

ユーザーが粒度と依存関係を承認し、親仕様 [#283](https://github.com/treflebonbon/dotfiles/issues/283) の子Issueとして次の10件を公開した。全件に `ready-for-agent` を付与し、GitHubの親子関係と11本のblocking関係を設定した。

| Issue | 完了する範囲 | 先行して完了するIssue |
| --- | --- | --- |
| [#286](https://github.com/treflebonbon/dotfiles/issues/286) | repo編集用ツールとCI品質ゲートを更新する | なし |
| [#287](https://github.com/treflebonbon/dotfiles/issues/287) | Node.js 24 LTSを維持してユーザー共通環境を更新する | なし |
| [#288](https://github.com/treflebonbon/dotfiles/issues/288) | AIツールsnapshotと連動する解析・文書変換CLIを更新する | [#287](https://github.com/treflebonbon/dotfiles/issues/287) |
| [#289](https://github.com/treflebonbon/dotfiles/issues/289) | 通常の外部スキルを更新しAPM配備の再現性を確認する | [#288](https://github.com/treflebonbon/dotfiles/issues/288) |
| [#290](https://github.com/treflebonbon/dotfiles/issues/290) | Impeccableのスキルとengineを同時更新してhookを検証する | [#289](https://github.com/treflebonbon/dotfiles/issues/289) |
| [#291](https://github.com/treflebonbon/dotfiles/issues/291) | Matt Pocock managed setの互換性と採否を確定する | [#290](https://github.com/treflebonbon/dotfiles/issues/290) |
| [#292](https://github.com/treflebonbon/dotfiles/issues/292) | PlaywrightとDogfoodの実行環境を整合して更新する | [#286](https://github.com/treflebonbon/dotfiles/issues/286), [#287](https://github.com/treflebonbon/dotfiles/issues/287) |
| [#293](https://github.com/treflebonbon/dotfiles/issues/293) | シェル・作業管理・設計用の固定CLIを更新する | [#287](https://github.com/treflebonbon/dotfiles/issues/287) |
| [#294](https://github.com/treflebonbon/dotfiles/issues/294) | 6言語テンプレートを更新し独立した新規repoで検証する | なし |
| [#295](https://github.com/treflebonbon/dotfiles/issues/295) | 全更新の採否とsource受入結果を統合する | [#291](https://github.com/treflebonbon/dotfiles/issues/291), [#292](https://github.com/treflebonbon/dotfiles/issues/292), [#293](https://github.com/treflebonbon/dotfiles/issues/293), [#294](https://github.com/treflebonbon/dotfiles/issues/294) |

公開後に全件の本文・タイトル・ラベル・状態・親子関係・依存関係を承認済みの計画と照合した。親Issueの本文・タイトル・ラベル・状態・コメントは公開前と一致している。直ちに着手できるのは #286、#287、#294 である。これは計画の公開結果であり、更新の実装・採用結果ではない。
