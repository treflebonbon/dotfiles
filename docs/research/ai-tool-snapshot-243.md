---
type: research
title: Issue 243 の Tool Snapshot 更新
description: AI ツール更新の第1単位の採用候補、互換性確認と後続の配備境界。
tags: [research, nix, llm-agents, herdr, apm]
timestamp: 2026-09-08
---

# Issue #243 — Tool Snapshot

[Issue #243](https://github.com/treflebonbon/dotfiles/issues/243) の第1更新単位。baseline は `df13f205fca26277b323c7bb5cb7d36c960775be`、実装場所は Orca linked worktree `chore-ai-impeccable`。Tool Snapshot、通常の APM payload、Impeccable 移行を別 PR とし、後続は前段の merge 済み baseline から始める。Issue 全体の完了をこの単位の完了と同一視しない。

## Contract

- 目的: 導入済み AI ツールを immutable snapshot へ更新し、既存の手動利用・設定・品質 floor を維持する。
- 対象 AC: AC1–5、AC15、AC16 の source 側。全 AC の対応は下表に記録する。
- 非目標: APM skill manifest / lock、Impeccable engine / hook、Matt Pocock、共有 nixpkgs、別 pin の補助 CLI、モデル・権限設定の変更。live HOME への配備も後段とする。
- 検証境界: 実際の Nix devShell / package 出力、隔離した CLI と Herdr server。既存 APM lock の新版 binary での再配備も隔離する。
- 入口: `private_dot_config/nix-devshell/flake.nix` / `flake.lock`、`modules/ai.nix`、`tests/herdr.bats` / `tests/nix-devshell.bats` / `tests/ai-quality-floor.bats`。
- 判断済み trade-off: Codex / Herdr は固定 input の direct package、他は shared overlay を維持する。cache 確認、host build、他 platform の評価を区別する。

## Snapshot と release 判断

実装入口で `gh api repos/numtide/llm-agents.nix/commits/HEAD` を一度実行し、default branch HEAD が候補と同じ [`868527bc9eb4e8bee8610fa1d4027fbb37cfc012`](https://github.com/numtide/llm-agents.nix/commit/868527bc9eb4e8bee8610fa1d4027fbb37cfc012)（2026-09-07 22:20:13 UTC）と確認した。追加の release 収録は待っていない。更新する3 release の GitHub metadata はすべて `prerelease: false`。

| package                     | baseline | candidate |
| --------------------------- | -------- | --------- |
| Claude Code                 | 2.1.261  | 2.1.263   |
| Codex                       | 0.153.4  | 0.153.4   |
| Copilot CLI                 | 1.0.83   | 1.0.83    |
| Antigravity CLI             | 1.1.27   | 1.1.27    |
| Herdr                       | 0.8.2    | 0.9.0     |
| RTK                         | 0.48.0   | 0.48.0    |
| APM                         | 0.29.0   | 0.30.0    |
| code-review-graph（別 pin） | 2.3.8    | 2.3.8     |

`nix flake lock ./private_dot_config/nix-devshell` で生成した lock は source URL と同じ `original.rev` / `locked.rev` を持つ。shared nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` と `nixpkgs-ai-sources` は不変。llm-agents 内部の nixpkgs は upstream lock に従い `5545adfa` → `0af3d140` へ進むため、同版の Codex も derivation identity は変わる。

[Claude 2.1.263 の release note](https://github.com/anthropics/claude-code/releases/tag/v2.1.263) は一般的な修正・信頼性改善の記載に留まる。新しい最低版を必要とする具体的根拠は追加されていないため、Claude 2.1.261 / Codex 0.153.4 の品質 floor と既存モデル設定を維持する。

[APM 0.29.1–0.30.0 の CHANGELOG](https://github.com/microsoft/apm/blob/v0.30.0/CHANGELOG.md) は credential の送信先制限、実行・配備失敗の報告、ownership / cache / prune の修正を含む。native installer の checksum 必須化と既定 prefix の変更は、Nix が binary を供給する本構成では installer 移行を必要としない。新 target は追加せず `claude,codex` を明示する。

## Herdr の既定値と動作

[Herdr 0.9.0 の release note](https://github.com/herdrdev/herdr/releases/tag/v0.9.0) と [config source](https://github.com/herdrdev/herdr/blob/v0.9.0/src/config/model.rs) を照合した。`update.manifest_check = true` と標準の状態検出を維持する。remote machine、追加 integration、自動起動の設定は追加しない。

専用 HOME / XDG config・state・data・cache・runtime / socket と tmux server で実際の Herdr 0.9.0 を手動起動し、pane `w1:p1` の `sleep 300` が detach / reconnect 後も同じ PID で動くことを確認した。検証用 server の停止後に `running: false`、再起動後に `running: true` / `version: 0.9.0` を確認し、最後に検証用 server と端末を停止した。通常利用中の server / pane は操作していない。

`herdr server agent-manifests --json` で bundled Claude `2026.09.04.1` / Codex `2026.09.05.1` を確認した。[上流の回帰例](https://github.com/herdrdev/herdr/blob/v0.9.0/src/detect/manifest/tests.rs) を public CLI `herdr agent explain --file … --agent … --json` に渡し、Claude の background shell を残した idle / foreground working、Codex の update chooser の blocked / 過去の chooser 出力の idle を4/4で確認した。実 AI session の全状態や remote manifest 更新の成功まではこの検証の対象にしていない。

画像機能は上流既定を採用する。[`terminal.kitty_graphics` の既定値](https://github.com/herdrdev/herdr/blob/v0.9.0/src/config.rs) を変えず、実 server の `pane.graphics.info` が `feature_disabled` でなく `pane_graphics_info` と `pane_visible: true` を返すことを確認した。tmux / xterm-256color 上で文字入力・再接続に問題はなかった。Kitty 対応の実端末における画像の描画品質・端末別互換性は未確認であり、API の有効性と区別する。

## 既存 APM payload との互換性

Nix が供給する APM 0.30.0 を隔離 cwd / HOME で実行し、baseline の manifest / lock を使った `apm install --frozen --target claude,codex --https` を2回と `apm audit --ci` を確認した。両 install と audit は成功し、lock SHA-256 は `1d833fb947eb39a0e8a5a817530ca43e7c6d996b5ec0a65fdd45f5e5f53da010` から不変。Claude / Codex の42/42 skillを配備し、両 target の `SKILL.md` は全件一致した。source の APM manifest / lock は変更していない。

Audit は10/10で、organization policy は `treflebonbon/.github-private` が見つからないため enforcement を skip したという warning がある。これは取得成功や組織 policy への適合を証明しない。今回の互換性確認は既存 lock の frozen replay であり、AC7 が次単位に要求する新しい final manifest の native lock 生成を代替しない。ログは `apm-smoke-0.log` / `apm-smoke-1.log` / `apm-smoke-2.log`、discovery は `apm-discovery.json`。

## Verification Matrix

証跡はこの worktree の `tmp/issue-243/` に保存する。ローカルの一時ログであり、恒久的な成果物ではない。

| AC                    | 種別         | 実行コマンドまたは確認方法                                                                                                                                       | 結果          | 未確認理由                                                                 |
| --------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | -------------------------------------------------------------------------- |
| AC1 更新単位          | workflow     | baseline `df13f20` から Tool Snapshot のみを変更                                                                                                                 | 第1単位       | 後続2単位はこの単位の merge 後                                             |
| AC2 snapshot          | infra        | 入口の HEAD 確認、release metadata、source / lock / 実 package metadata の照合                                                                                   | 成功          | —                                                                          |
| AC3 対応環境          | infra / CLI  | `nix flake check ./private_dot_config/nix-devshell --no-build --all-systems`、全6出力 metadata、host 両 devShell の build / `nix develop` から7 CLI version/help | 成功          | aarch64-linux / aarch64-darwin は実機なし                                  |
| AC4 floor / 設定      | infra        | 品質 floor の既存7テスト、管理設定と AI module の不変性                                                                                                          | 成功          | —                                                                          |
| AC5 Herdr             | CLI          | 隔離 TUI、detach / reconnect / server restart、状態検出4 fixture、graphics API                                                                                   | 成功          | 画像の実端末描画、実 AI session の全状態、remote manifest 更新成功は未確認 |
| AC6 通常スキル        | APM          | manifest / lock を baseline から維持                                                                                                                             | 後続単位      | Tool Snapshot merge 後に実装                                               |
| AC7 native lock       | APM          | 本単位では lock を再生成しない                                                                                                                                   | 後続単位      | 更新済み APM による final manifest の native materialization は次単位      |
| AC8 discovery         | APM          | 現行 payload を維持                                                                                                                                              | 後続単位      | 更新した payload の discovery は次単位                                     |
| AC9 Orca guidance     | workflow     | 現行 payload / ローカル契約を維持                                                                                                                                | 後続単位      | Orca payload の更新と guide 確認は次単位                                   |
| AC10 Impeccable 配布  | infra        | skill / engine を変更しない                                                                                                                                      | 後続単位      | 通常スキル単位の merge 後                                                  |
| AC11 global hook      | API          | 現行管理 hook を維持                                                                                                                                             | 後続単位      | 新 engine に対する実体検証は第3単位                                        |
| AC12 hook 動作        | API          | 現行管理 hook を維持                                                                                                                                             | 後続単位      | 同上                                                                       |
| AC13 fail-open / 所有 | API          | 現行管理 hook / project 所有境界を維持                                                                                                                           | 後続単位      | 同上                                                                       |
| AC14 実 engine gate   | API          | 新 engine の materialization は実施しない                                                                                                                        | 後続単位      | 同上。skip を移行成功としない                                              |
| AC15 回帰             | tests / docs | 関連36/36、full Bats 517/517（skipなし）、型検査、Nix / Markdown format、変更 Herdr テストの ShellCheck                                                          | 必須検証成功  | 追加 ShellCheck は baseline と同じ40指摘。下記参照                         |
| AC16 配備境界         | workflow     | linked worktree 検証、`chezmoi source-path` が primary checkout を指すことを確認                                                                                 | source 側成功 | live apply と通常環境の最終確認は受入・merge 後                            |

Codex / Herdr の direct output は3 systemすべて `nix path-info --store https://cache.numtide.com` で cache に存在する。host は Herdr を cache から取得し、Claude / APM の取得・package 作成と2つの shell derivation を build した。cache 確認を他 platform の native 起動や source build の成功とは扱わない。

Herdr の期待版を先に0.9.0へ更新したテストは baseline 0.8.2 に対して失敗し、更新後の出力を評価する。初回の依存取得ログが `run` の結合出力に混ざって JSON parse を失敗させたため、`--separate-stderr` で Nix の JSON stdout と診断を分離した。検証項目を削除したり warning を成功条件にしたりしていない。

関連 Bats は `env -u FORCE_COLOR bats tests/herdr.bats tests/ai-quality-floor.bats tests/nix-devshell.bats` で36/36成功。`run` の flag が要求する Bats 1.5.0 を明示した後の `tests/herdr.bats` 再実行も成功し、version warning は解消した。`nix develop .#wsl --command nixfmt --check private_dot_config/nix-devshell/flake.nix`、`bunx tsc --noEmit`、変更 Markdown の oxfmt、`tests/herdr.bats` の ShellCheck が成功した。

Full suite は `env -u FORCE_COLOR IMPECCABLE_HOOK_RUNTIME="$PWD/tmp/issue-243/apm-runtime/.agents/skills/impeccable/scripts/hook.mjs" bun run test` で517/517成功、skipは0件。新版 APM が materialize した既存 Impeccable 4.1.2 runtime の10テストも実行しており、Rust engine 移行の検証とは区別する。full suite の開始後に Bats 最低版宣言を追加したため、`full-suite.log` には修正前の BW02 が残る。修正後の `herdr-green.log` は警告なく成功している。

追加で `tests/nix-devshell.bats` 全体に実行した ShellCheck は40件の既存指摘で不合格だった。主に文字列内の他言語の変数に対する SC2016 と、Bats の途中の `!` assertion に対する SC2314。baseline と candidate の診断 JSON を file名以外の全fieldで比較し、完全一致を確認した。対象外の既存テストを今回一括修正せず、新しい指摘がないことを `shellcheck-comparison.json` に残す。repository の必須 ShellCheck hook は `.sh` が対象であり、`.bats` はこの追加確認の対象である。

後続の Impeccable 単位では、Issue 本文に自己完結している配布判断と ADR-0052 を source に含める。本単位は旧 manifest / lock と管理 hook を保持し、engine / skill の片側だけを採用しない。
