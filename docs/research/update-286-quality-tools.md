---
type: research
title: Issue 286 — repo 編集用ツールと OSV Action の更新記録
description: 固定した unstable・npm・OSV 候補、互換性検証、TypeScript 7 移行時の生成状態修復
tags: [nix, npm, typescript, oxc, osv, updates]
---

# Issue 286 の採用・検証記録

2026-09-10。対象は [#286](https://github.com/treflebonbon/dotfiles/issues/286)、親仕様は [#283](https://github.com/treflebonbon/dotfiles/issues/283)。両 Issue の本文全体とコメントを取得し、コメントがないこと、Testing Decisions が承認済みであることを確認した。

担当は root `flake.nix` / `flake.lock`、`package.json` / `bun.lock`、必要な npm 品質設定、OSV の 2 workflow、本記録。ユーザー環境・templates・共有 `tests/nix-devshell.bats`・runtime 文書は別担当。commit・stage・push・PR・最終二軸 review・full Bats は coordinator が直列化する。live skill と chezmoi apply は対象外。

## 候補を固定した根拠

作業入口で GitHub API、npm registry、固定 revision の Nixpkgs package source を直接取得した。設計ノートの版番号を採用根拠にはしていない。以後の検証は下記の exact version / revision を対象とし、上流 HEAD を追い直さない。

| 対象 | 変更前 | 固定候補 | 配布経路・判断 |
| --- | --- | --- | --- |
| root nixpkgs | `64c08a7ca051951c8eae34e3e3cb1e202fe36786` | `d6524aaca2ff07876657ae2b323f24be4874944b` | `nixos-unstable` を維持。lock 更新と実 Nix 検証は coordinator が実施 |
| TypeScript | 6.0.3 | 7.0.2 | npm 安定版を反映。既存 `tsc --noEmit` が成功 |
| npm oxfmt | 0.48.0 | 0.67.0 | npm 安定版を反映。既存 config で成功 |
| npm oxlint | 1.71.0 | 1.82.0 | npm 安定版を反映。既存 config で成功 |
| Ultracite | 7.8.3 | 7.11.1 | npm 安定版を反映。OXC peer 条件が整合 |
| bun-types | lock 1.3.13 / 宣言 `^1.1.30` | 1.3.13 | 実行 Bun と一致する exact pin にする。上流 1.4.2 の型だけは採用しない |
| brace-expansion override | 5.0.9 | 5.0.9 | registry の安定版と一致。既存 override を維持 |
| OSV Action | 2.3.8 / `9a498708959aeaef5ef730655706c5a1df1edbc2` | 2.5.1 / `6e4298ebc4db23e847df9b2e2de2939d6f066c67` | 公式 release tag が指す commit に 2 workflow を更新 |
| Action 内の scanner | 2.3.8 | 2.3.8 | Action の版と区別。scanner の版更新とは報告しない |

一次資料: [nixpkgs 候補 commit](https://github.com/NixOS/nixpkgs/commit/d6524aaca2ff07876657ae2b323f24be4874944b)、[TypeScript 7 の公式説明](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)、[TypeScript package metadata](https://registry.npmjs.org/typescript/7.0.2)、[oxfmt](https://registry.npmjs.org/oxfmt/0.67.0)、[oxlint](https://registry.npmjs.org/oxlint/1.82.0)、[Ultracite](https://registry.npmjs.org/ultracite/7.11.1)、[bun-types](https://registry.npmjs.org/bun-types/1.3.13)、[OSV Action release](https://github.com/google/osv-scanner-action/releases/tag/v2.5.1)。

## root Nix tool inventory

旧版は固定 revision の package source から読んだ値。候補版は coordinator が実 Nix で対応 3 system の default / wsl を評価した `tmp/update-283/root-all-systems-candidate.json` と照合済み。package 出力の評価・host 実行とは分ける。`mkShell.packages` は `nativeBuildInputs` に入るため、実評価の inventory は `nativeBuildInputs ++ buildInputs` を列挙する。

| package | 旧 source の版 | 候補 package 出力の版 | 上流との差・判断 |
| --- | --- | --- | --- |
| chezmoi | 2.70.3 | 2.72.1 | [公式安定版](https://github.com/twpayne/chezmoi/releases/tag/v2.72.1)と一致 |
| lefthook | 2.1.5 | 2.1.12 | [公式安定版](https://github.com/evilmartians/lefthook/releases/tag/v2.1.12)と一致 |
| cocogitto | 7.0.0 | 7.0.0 | [公式安定版](https://github.com/cocogitto/cocogitto/releases/tag/7.0.0)を維持 |
| shellcheck | Haskell package から継承 | 0.11.0 | [上流安定版](https://github.com/koalaman/shellcheck/releases/tag/v0.11.0)と実 package 出力が一致 |
| shfmt | 3.13.1 | 3.14.1 | [公式安定版](https://github.com/mvdan/sh/releases/tag/v3.14.1)と一致 |
| actionlint | 1.7.12 | 1.7.12 | [公式安定版](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)を維持 |
| ghalint | 1.5.6 | 1.5.6 | [公式安定版](https://github.com/suzuki-shunsuke/ghalint/releases/tag/v1.5.6)を維持 |
| pinact | 3.9.2 | 4.1.1 | [公式安定版](https://github.com/suzuki-shunsuke/pinact/releases/tag/v4.1.1)と一致 |
| Nix oxfmt | 0.45.0 | 0.61.0 | npm 0.67.0 との差を維持。lefthook は従来どおり `bunx oxfmt` を使用 |
| nixfmt | Haskell package から継承 | 1.4.0 | [公式安定版](https://github.com/NixOS/nixfmt/releases/tag/v1.4.0)と一致 |
| gitleaks | 8.30.1 | 8.30.1 | [公式安定版](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1)を維持 |
| bats + support / assert libraries | bats 1.12.0 | bats 1.14.0 | [公式安定版](https://github.com/bats-core/bats-core/releases/tag/v1.14.0)。既存 withLibraries 経路を維持 |
| nodejs_24 | 24.15.0 | 24.19.0 | 24 LTS 属性を維持。26 Current へ変更しない |
| bun | 1.3.13 | 1.3.13 | [上流 1.4.2](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.2)は未収録。新規 override を追加しない |
| python3 + python-dotenv | package set から解決 | python3-3.14.7-env | 既存 withPackages 経路。dotenv の import smoke は coordinator の実起動 gate に含める |
| with-env | repo の実装 | 同じ repo の実装 | 配布入口を維持。起動 probe は引数なしの usage を確認し、dotenv を読む実行はしない |
| git | 2.54.0 | 2.55.0 | 既存 Nixpkgs package 経路 |
| playwright-driver | 1.59.1 | 1.61.1 | [上流 1.63.0](https://github.com/microsoft/playwright/releases/tag/v1.63.0)との差を記録。別経路へ変更しない |

package source の正本は [旧 revision](https://github.com/NixOS/nixpkgs/tree/64c08a7ca051951c8eae34e3e3cb1e202fe36786/pkgs)と[候補 revision](https://github.com/NixOS/nixpkgs/tree/d6524aaca2ff07876657ae2b323f24be4874944b/pkgs)。wrapper が継承する版は文字列から推測して確定しない。

root lock は coordinator が更新済みで、`original.ref = nixos-unstable` と候補 revision を確認した。narHash は `sha256-2V9GZGvPfrNzxFozhI9dcqV+c3QdA8YZrvAAzqEB+dI=`、lastModified は `1788881743`。`flake.nix` 自体の変更は不要だった。

`tmp/update-283/root-candidate-flake-check.log` は全 3 system の default / wsl、with-env package / app、formatter、template output の評価成功を記録する。with-env app の `meta` 欠落 warning はあるが、評価失敗ではない。各 WSL 出力は browser path が null、download skip が 1。host WSL の build は `tmp/update-283/root-wsl-build.json` の `/nix/store/2mbz6lys1cv895d1dhbipc93xdw9aj5w-nix-shell.drv` → `/nix/store/g33idmhw54m7svp843iwmla5casqx150-nix-shell` として成功した。

後続の browser 検証向け固定値: 候補の [driver.nix](https://github.com/NixOS/nixpkgs/blob/d6524aaca2ff07876657ae2b323f24be4874944b/pkgs/development/web/playwright/driver.nix) は Playwright **1.61.1**。[browsers.json](https://github.com/NixOS/nixpkgs/blob/d6524aaca2ff07876657ae2b323f24be4874944b/pkgs/development/web/playwright/browsers.json) は Chromium / headless shell **1228 / 149.0.7827.55**、Firefox **1532 / 151.0**、WebKit **2311 / 26.5**（platform override あり）、ffmpeg **1011**。これは source metadata の確認であり、browser 起動結果ではない。WSL shell は従来どおり browser package を含めない。

## npm の実体・peer・移行

worker の実行環境は WSL2 x86_64-linux、Bun **1.3.13**、Node **24.18.0**。この Node の値は起動済み worker の環境であり、root 候補の Node 24.19.0 を実行したという意味ではない。

隔離した旧構成と新構成の両方で frozen/install、`tsc --noEmit`、既存の 3 root TypeScript config の oxlint、oxfmt を実行した。候補の TypeScript native binary も実際に起動し、7.0.2 を確認した。TypeScript config、OXC config、lefthook の変更は不要だった。

Ultracite 7.11.1 の installed peer 条件は `oxfmt >=0.40.0` / `oxlint ^1.79.0`。選択した 0.67.0 / 1.82.0 は双方を満たす。OXC の Node 条件は `^20.19.0 || >=22.12.0` で Node 24 が適合する。使用していない optional peer（ESLint、Biome、Svelte、vite-plus、oxlint-tsgolint 等）は導入しない。`bun-types` 1.3.13 の実体は Bun 実行版と一致し、transitive `@types/node` 25.6.0 は既存 lock から不変。root の型検査対象は品質設定 3 ファイルで、新しい Node API の利用を加えていない。

### TypeScript 6 → 7 の clean reinstall

coordinator の full Bats が `chezmoi: stat .../node_modules/.bin/tsserver: no such file or directory` で失敗した。TypeScript 7 の package は `tsc` のみを公開し、旧 `tsserver` は廃止されている。Bun **1.3.13** で旧 lock 6.0.3 → 新 lock 7.0.2 の frozen install を実行すると、install は 0 で終わるが、旧 `tsserver` symlink が残ることを隔離 fixture で再現した。

赤: 旧構成の install 後は dangling link 0 件、新構成への in-place frozen install 後は `.bin/tsserver` が dangling になり、installed CLI link の解決確認が失敗する。緑: 生成した `node_modules` を source 外へ退避し、新 lock から clean frozen install すると dangling link 0 件、`tsserver` 不在、`tsc --noEmit` 成功となる。project config とテストは弱めず、互換用 `tsserver` コードも追加しない。

共有 root の修復は full Bats 停止後に coordinator の明示指示で実施した。旧生成物は `/tmp/nix-shell.2VWWVm/nix-shell.faRWAp/update-286-ts6-dependencies.n2xc_a2h/node_modules` に保存し、削除していない。別 filesystem への単純 rename は `EXDEV` となったため、cross-filesystem move で退避した。

この更新を別の既存 checkout に入れるときも、Bun 1.3.13 では、依存を使用する処理を止めてから `node_modules` を **chezmoi source 外**の新しい一時ディレクトリへ退避し、新 lock の `bun install --frozen-lockfile` で再作成する。source 配下の退避では、chezmoi の走査対象に dangling symlink が残り得る。退避物の削除はこの手順に含めない。

root clean install と隔離 install の前後で `bun.lock` SHA-256 はともに **`6c1692d7caf644789aa2b52c5c298f6d2c78d0c850ea7065d1629cd9ca1d57a3`** で不変。root install 時、worker は `.env` の自動読込みをアクセス制限で拒否した（内容は取得していない）。以後の install 検証は manifest と lock だけを複製した独立 cwd を使う。型検査等の起動は `bun --no-env-file x --no-install ...` を使う。

## OSV の契約と red → green

候補 tag の実体は `6e4298ebc4db23e847df9b2e2de2939d6f066c67`。その reusable workflow は scanner / reporter action の `baa4139e56d6312335d899e6ba045fa16d1d3d0b` を参照し、container tag は Action の `v2.5.1`。公式 release 説明の scanner は **2.3.8** である。[旧版からの公式差分](https://github.com/google/osv-scanner-action/compare/9a498708959aeaef5ef730655706c5a1df1edbc2...6e4298ebc4db23e847df9b2e2de2939d6f066c67)を確認した。

新版は `export-results` 入力を追加し、既定値 false で JSON output の公開を省略する。旧版は無条件に公開していた。pin だけを更新した候補に対し、既存の結果 output が有効である契約を検証すると失敗した。両 caller に `with: { export-results: true }` を指定して同じ確認が通過した。

両 workflow の trigger、既存入力の有効既定値、`results` / `old-results` / `new-results` の出力定義、必要な `actions: read` / `contents: read` / `security-events: write` 権限を照合した。SARIF と脆弱性検出時の失敗は従来どおり有効。新しい workflow dispatch は行わない。

## Verification Matrix

| 親 AC / 検証 | コマンド・証跡 | 状態 |
| --- | --- | --- |
| AC1–4 / candidate 固定 | `gh api repos/NixOS/nixpkgs/commits/nixos-unstable`、公式 release / npm registry、固定 revision の package source | PASS。上記 exact 候補で固定 |
| AC9 / 旧 npm baseline | 隔離 cwd で旧 `bun install --frozen-lockfile`、`bunx tsc --noEmit`、既存 root config の lint / format | PASS |
| AC9 / 候補 npm | 新 manifest / native Bun lock、clean frozen install、`bun --no-env-file x --no-install tsc --noEmit`、oxlint、oxfmt | PASS。実行 Bun 1.3.13 / worker Node 24.18.0 |
| AC9 / no-rewrite | frozen install 前後の SHA-256、installed package / peer metadata | PASS。上記 lock hash 不変 |
| AC15 / OSV contract | `.tmp/update-286/check-workflow-contract.mjs`（upstream 旧・候補 payload と caller を照合） | RED → GREEN。出力の opt-in 指定で解決 |
| AC15 / workflow lint | `actionlint .github/workflows/osv-scanner-{pr,full}.yml`、`ghalint run`、`pinact run --check --verify` | PASS。worker は actionlint 1.7.12 / ghalint 1.5.6 / pinact 3.9.2 |
| AC17 / TS7 移行 | 隔離した旧→新 frozen install、dangling bin 確認、生成物退避後の clean install | RED → GREEN。root も修復済み |
| AC16 / Codex config 再検証 | `bats --filter … tests/codex-config.bats`、`tmp/update-283/ts7-clean-install-regression.log` | coordinator で 2/2 PASS。worker の setup 失敗は別記 |
| AC3・6 / 3 system × default/wsl | `nix flake check --no-build --all-systems`、`nativeBuildInputs ++ buildInputs` の package 出力。`tmp/update-283/root-candidate-flake-check.log` / `root-all-systems-candidate.json` | coordinator で全 6 shell PASS。Node 24.19.0、Bun 1.3.13 |
| AC6 / host WSL build | `nix build .#devShells.x86_64-linux.wsl`、`tmp/update-283/root-wsl-build.json` | coordinator で PASS |
| AC6・9・15 / host WSL 起動・統合品質ゲート | `.tmp/update-286/verify-root-nix.sh` の隔離 HOME、CLI 起動、frozen install、npm / Action lint | PASS。固定済みlockに対して `tmp/update-283/verify-root-nix-locked.sh` を実行し、CLI起動、隔離frozen install、型検査・lint・format、workflow検証を完了した |
| AC16 / full Bats | coordinator の `tmp/update-283/t2-full-bats.log` | 復旧後のfull suiteはexit0。674件中643実行PASS、31件skip（`tmp/update-283/t2-full-bats-recovered.log` / result JSON）。必須の実hookと6テンプレートは別実行でPASS |
| AC18–19 / source・完了記録 | 本記録、担当ファイルの差分、coordinator の統合 review | source側の統合検証・review完了（[#295](update-295-integrated-acceptance.md)）、live 未配備 |

worker は `nix eval --json --expr '1 + 1'` に成功したが、旧・候補の `nix flake metadata --json github:NixOS/nixpkgs/<rev>` は Unix socket 作成の `Operation not permitted` で失敗した。coordinator から、自身の runtime では Nix が使用可能であると確認された。これは候補の不具合や据置理由にはせず、worker からの Nix 実体検証だけを未確認とする。別 store や permission 変更による回避はしない。

同様に worker の Codex config 再検証は setup の `git rev-parse --git-common-dir` が失敗し、本体に到達しなかった。生成状態修復後、coordinator が次の同じ 2 テストを実行し、双方の成功 log を worker も確認した。

```bash
bats --filter 'codex-worktree accepts metadata pointers relative|Codex config managed fragment exists without local state tables' tests/codex-config.bats
```

coordinator 用 script は独立 HOME、固定 candidate override、6 評価の JSON、WSL build log、各品質 CLI の起動、Node 24 と browser-free WSL の条件、frozen install と npm / workflow gate をまとめる。出力先は `.tmp/update-286/coordinator-nix/`。worker の個別 log は `.tmp/update-286/logs/`、一次資料の取得物は `.tmp/update-286/upstream/`。scratchpad が提示されていないため、この明示した repo-local scratch と runtime の書込み可能な TMPDIR を使用した。

## 共有工程への引継ぎ

root lock の更新、3 system の評価、host WSL build と Codex config の回帰確認は完了した。固定済みlockに対するend-to-end起動・品質検証も成功した（`tmp/update-283/root-quality-end-to-end.log`）。復旧後のfull Batsは基盤の回帰検証として成功した。他更新単位を合わせた最終full Bats・全source品質・dry-run・二軸reviewは [#295](update-295-integrated-acceptance.md) に記録した。3 system の評価だけでは aarch64 Linux / Darwin の実機起動済みとはしない。

`tests/nix-devshell.bats` の更新、full Bats、統合 commit と二軸 review、最終 PR は coordinator が担当する。TS7 移行の生成状態修復以外に、本 slice による共有テスト・runtime 文書の変更要求は現時点でない。受入・merge 後の live source からの配備と通常環境での確認は別工程として残す。

full suiteの2回目は、中断した自身のテスト用Chromeの残存所有権で9件、検証環境の`FORCE_COLOR=0`によるCRG JSONの装飾で1件が失敗した。呼出元PIDの消滅とこのworktree専用profileをWindowsのInspectで確認し、既存CDP helperで通常終了後、`managed-chrome-owner recover`で復旧した。色変数を未設定にした同じCRG MCPテストは成功した。配布コードやassertionの緩和は行わず、3回目のfull suiteはexit0、終了後のownerはnullだった。
