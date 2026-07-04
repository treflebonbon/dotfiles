---
type: concept
title: Skill harness
description: apm 経由の外部 skill 群、mattpocock 設計→実装ワークフロー、chezmoi 配布のローカル skill（to-pr）、playwright-cli、Claude Code plugin の多層管理
tags: [skills, apm, mattpocock, playwright, claude-code, antigravity]
---

# Skill harness

軽量化のため superpowers を外し、workflow 層は mattpocock skills に置換した（→ [ADR-0002](../docs/adr/0002-mattpocock-over-superpowers.md)）。

## apm 管理の外部 skill

`apm.yml` / `apm.lock.yaml` が外部 skill を `~/.claude/skills/` へ展開する。`apm lock` で lockfile を再生成、`apm install --frozen` が `run_onchange_after_apm-install.sh.tmpl` から冪等に走る。

**mattpocock 設計→実装ワークフロー** (`mattpocock/skills/skills/engineering/`)。上流 README の promoted セット（User-invoked / Model-invoked の公式分類）に整合させて導入している。

_User-invoked_（明示起動のみ、orchestration 層。チェーン: `to-worktree → grill-with-docs → to-prd → to-issues → triage → to-pr`）:

- `setup-matt-pocock-skills` — **必須エントリポイント**。per-repo で issue tracker（GitHub / GitLab / local markdown / その他）、triage label 語彙、domain doc レイアウト（`CONTEXT.md` + `docs/adr/`）を構成し `docs/agents/*.md` を生成
- `grill-with-docs` — 対話しつつ `CONTEXT.md` と ADR を更新（`domain-modeling` に委譲）
- `to-prd` — 会話を PRD にして issue tracker へ publish
- `to-issues` — plan/PRD を vertical slice の issue に分解
- `triage` — issue を state machine（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）で捌く
- `ask-matt` — user-invoked skills の router（どのフローが合うか迷った時）
- `improve-codebase-architecture` — ball-of-mud レスキュー。deepening 機会を HTML レポートで提示

_Model-invoked_（実装フェーズで自動発火する discipline 層。上流ルール: user-invoked は他の user-invoked を呼ばない）:

- `tdd` — red-green-refactor
- `code-review` — Standards 軸 + Spec 軸の 2 軸並列レビュー
- `diagnosing-bugs` — ハードバグ / 性能回帰の診断ループ
- `domain-modeling` — `grill-with-docs` / `triage` が委譲する依存（`CONTEXT.md` + ADR 維持の実体）
- `codebase-design` — deep module 設計の共有語彙（interface / seam / testability）
- `prototype` — 設計質問に答える捨てプロトタイプ
- `research` — 一次情報リサーチを background agent で行い cited Markdown を残す

実装フェーズに user-invoked skill は無い: `triage` で `ready-for-agent` にした issue を agent に渡すと model-invoked 層が自動発火する。**非導入**: `implement` / `resolving-merge-conflicts`（上流 README 非掲載の unlisted skill。`implement` は tdd/code-review 発火で冗長な5行の糊）。`grilling`（productivity/Model-invoked、`grill-with-docs`/`grill-me` の共通ループ）は当初「README 非掲載」と誤認し非導入だったが、[ADR-0009](../docs/adr/0009-add-grilling-skill.md) で誤りと判明し導入済み。`grill-me`（productivity/User-invoked、no-codebase 向け）は [ADR-0002](../docs/adr/0002-mattpocock-over-superpowers.md) が軽量化のため意図的に除去したまま。

このワークフローは per-repo で完結する。ラベル provisioning は dotfiles では持たず、各 repo で `gh label create` または skill のランタイム挙動に任せる。domain doc は mattpocock ネイティブの `CONTEXT.md`/`docs/adr` を使い、この `runtime/` バンドルとは混ぜない（`runtime/` は home-wide ambient 知識専用）。

**apm のマルチランタイム配布**: `apm.yml` の `targets` は `claude` / `codex`（apm の `install` は `antigravity` target を非対応）。apm は全 skill を APM-native の共有ハブ `~/.agents/skills/` に必ず materialize し（target とは独立）、Claude 向けには `~/.claude/skills/` にも配備する。**Codex と Antigravity はどちらも `~/.agents/skills/` を global skills location として直接読む**（Codex は `codex debug prompt-input` で skill 可視性を実機確認済み）ため、apm skill は追加配線なしで 3 ランタイムに可視。`~/.codex/skills/` は Codex の native location だが apm 0.23 は配備せず、過去に配備された real dir が残っていても discovery は `~/.agents/skills/` 側が担う。

**apm lock の再生成は `$HOME` で行う**: apm の target 解決はカレントディレクトリ基準（repo には `.codex/` が無く codex target が inactive になる）。lock は `cd ~ && apm lock` で再生成し、**`apm install` で配備を済ませてから** `~/apm.lock.yaml` を repo へコピーする（install が新規配備時に deployed_files / deployed_file_hashes を lock へ追記するため、配備前の lock をコピーすると drift する）。lock は apm native 形式（single-quote）のまま保存し oxfmt で再整形しない（`lefthook.yml` で除外済み。再整形すると apm が runtime で書き戻して chezmoi と永続 drift する）。

**その他 apm skill（保持）**: web-design-guidelines, react-best-practices, composition-patterns, react-view-transitions, shadcn, find-skills, skill-creator, pdf, frontend-design, supabase-postgres-best-practices, remotion, modern-web-guidance, empirical-prompt-tuning, effect-ts。

## chezmoi 配布のローカル skill

apm 外の user-scoped private skill は chezmoi で配布する。ソースは `local-skills/<name>/`（`.chezmoiignore` で `~/` へ直接 deploy せず SoT のみ）、`run_onchange_after_deploy-local-skills.sh.tmpl` が各ランタイムの skill dir へ `rsync` で materialize する:

- `~/.agents/skills/<name>/` — 共有ハブ。Antigravity / Codex はここを直接読む
- `~/.claude/skills/<name>/` — Claude
- `${CODEX_HOME:-~/.codex}/skills/<name>/` — Codex native location（`~/.agents/skills/` で可視のためフェイルセーフ）

deploy は `run_onchange_after_apm-install`（alphabetical 先行）の後に走り apm 配備を上書きしない。`run_onchange_before_remove-orphan-claude-skills.sh.tmpl` は `~/.claude/skills/` の real dir を wipe するため、ローカル skill 名を同スクリプトの `preserve_local_skills` allowlist に登録して除外する（両者の skill 名リストは一致させること）。

構造は **flat な `local-skills/<name>/`**（SKILL.md + references/ + 必要なら scripts/ 同梱で完結）。hooks / agents / marketplace 登録を要するメガパッケージ型の 3層 plugin 構造（`plugins/<ns>/{claude,codex,common}` 型）は不採用: あの構造の必然性は hooks + agents + bin + marketplace 登録というメガパッケージ要件にあり、skill-only なら不要。将来分離したくなったら `local-skills/` ごと新 repo に切り出して apm pin 化すればよい。

現行のローカル skill:

- `to-worktree` — ワークフローチェーンの入口。機能作業を始める前に隔離 worktree を用意する（Claude Code は `EnterWorktree` ツール優先、他ランタイムは `git worktree add .worktrees/<topic>`）。`.worktrees/` 配下に作るため放置分は `worktree-gc` が回収する
- `to-pr` — 実装完了後（user-invoked チェーンの最後尾）に、変更が browser-observable なら `playwright-cli` で AC を検証し、そうでなければ検証を skip して draft PR を開く。スクリーンショットは既定で埋め込まず、ユーザーが明示確認した場合のみ `.github/pr-assets/` に commit し PR 本文へ SHA 固定 blob URL で載せる。重量級の evidence schema / verdict gate / hero 選定は持ち込まない。
- `dogfood-to-issues` — 同梱の Playwright dogfood runner で web アプリ / Chrome MV3 拡張を隔離 worktree で dogfood し、承認された finding だけを GitHub Issue 化。issue 作成で完了し、実装へは続かない（triage → model-invoked フローへ）。`scripts/runtime-preflight.sh` 同梱
- `harness-feedback` — Codex / Claude の transcript JSONL を分析し、skill/agent 指示と実際の実行の乖離パターンを検出して小さな指示修正を提案
- `marp` — markdown を Marp CLI で PDF スライド化（marp-cli は nix devshell 配備済み）
- `md-agents-review` — AGENTS.md / Codex rules の対話式レビュー（trim / progressive disclosure）
- `md-claude-review` — プロジェクト CLAUDE.md の対話式レビュー（humanlayer ベストプラクティス基準）
- `rop` — Railway Oriented Programming の two-track パターン強制（Elixir / Gleam / Rust / Effect-TS の言語別 references 同梱）
- `worktree-gc` — 緊急時（fd/inotify 枯渇）の repo-local worktree 手動 GC。`scripts/worktree-gc.sh` 同梱。SessionStart 自動 GC hook は持ち込まない（手動起動のみ）

移植元スキルの `eval.yaml` / `tasks/`（skill 評価ハーネス）は持ち込まない。

## playwright-cli

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショットは `playwright-cli` skill を優先する。nix devshell のローカル package（`private_dot_config/nix-devshell/packages/playwright-cli.nix`、vendored `@playwright/cli`）を `modules/ai.nix` の shellHook が `~/.agents/skills/playwright-cli` へ symlink 配備する。agent-browser は削除した。`to-pr` の browser-observable 検証もこの skill を使う。

## Claude Code plugin の二層管理

プラグインは「配置（物流）」と「runtime 有効化」を別レイヤーで管理する:

- `apm.yml` — 外部 plugin / skill の取得（hook を持たない外部 skill-only は apm 経由）
- **chezmoi ローカル skill** — apm 外の user-scoped private skill（上記「chezmoi 配布のローカル skill」）。マルチランタイムへ materialize する自作 skill はこの経路
- `settings.json` `enabledPlugins` — runtime 有効化フラグ。hook を含む plugin（`security-guidance` / LSP 群 / `codex`）はここで有効化する
- `settings.json` `extraKnownMarketplaces` — 外部 marketplace 宣言（現状 `openai-codex` のみ）

`~/.claude/plugins/` 配下の `known_marketplaces.json` / `installed_plugins.json` / `cache/` は Claude Code の runtime state なので git/chezmoi では管理しない。

関連: [ai-runtimes](ai-runtimes.md) / [conventions](../docs/conventions.md)
