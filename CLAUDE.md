# CLAUDE.md

chezmoi dotfiles repo。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。ログインシェルは bash。

**重要**: ファイル編集は chezmoi source（`chezmoi source-path` で確認。init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される）内で行う。`chezmoi apply` で `~/` に反映。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で反映。

`CLAUDE.md` is the Claude Code-facing instruction file. `AGENTS.md` is maintained separately for Codex / OpenCode / Zed / Cursor-facing guidance.

home 配下のどの repo でも共通するシェル環境・skill 配備・AI ランタイムの詳細は `~/runtime/`（Open Knowledge Format バンドル、home-wide 配備）を参照する。`runtime/index.md` を入口に markdown リンクで辿れる。dotfiles repo 自身の構造は `docs/architecture.md`、規約は `docs/conventions.md`（いずれも repo ローカル、home 非配備）を参照。意思決定記録（ADR）は `docs/adr/`（repo root、連番ファイル名）に一本化されている。

## Architecture

2 種類の flake devShell がある。混同しないこと: **リポジトリ自体** (`./flake.nix`, chezmoi 編集用) と **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix`, 汎用ランタイム+横断ツール)。詳細な役割分担・ツール追加先の判断は `docs/architecture.md` を参照。

## Conventions

- コミット: Conventional Commits 形式（`cog verify` で検証）
- Linting: lefthook pre-commit hook で自動実行（`lefthook.yml` 参照）
- 認証: HTTPS + `gh auth git-credential`。SSH は不使用。

## 設計→実装ワークフロー

シナリオに応じて3つのチェーンを使い分ける（ADR-0012）。**機能作業はまず `/to-worktree` で隔離 worktree に入ってから始める**（Claude Code は `EnterWorktree` ツール優先。カレント checkout を汚さない）。ただし Orca セッション内（`orca` CLI、Linux では `orca-ide` が利用可能な時）は Orca worktree（`orca-cli` skill）を優先し、`/to-worktree` はそれ以外の環境で使う（ADR-0011）。

- **要件未確定**: `to-worktree` → `grill-with-docs` → `to-prd` → `to-issues` → `triage` で issue を ready-for-agent にする（実装は下記いずれかのチェーンへ引き継ぐ）
- **要件確定済み実装**: `to-worktree` → `tdd` → `code-review` → `to-pr`（`to-issues` / `triage` を経由せず直接実装に入る）
- **バグ修正**: `to-worktree` → `diagnosing-bugs` → `code-review` → `to-pr`（同上）

いずれのチェーンも実装フェーズに user-invoked skill は無く、`tdd` / `code-review` / `diagnosing-bugs` / `domain-modeling` / `codebase-design` / `prototype` / `research` が **model-invoked で自動発火**する（上流ルール: user-invoked は他の user-invoked を呼ばない）。各 product repo で最初に `setup-matt-pocock-skills` を実行し issue tracker / triage label / domain doc を構成する。domain doc は各 repo の `CONTEXT.md` + `docs/adr/` を使い、この repo の `runtime/` とは混ぜない。`to-pr` は実装後に条件付きブラウザ AC 検証 + PR 作成を行う chezmoi ローカル skill。迷ったら `ask-matt`（router）。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`targets` は claude / codex。全 skill を APM-native の共有ハブ `~/.agents/skills/` へ必ず materialize（target 非依存）し、Codex / Antigravity は `~/.agents/skills/` を直接読むため追加配線なしで可視。hook を持たない外部 skill-only は apm 経由。lock 再生成は `cd ~ && apm lock`（詳細は `runtime/skill-harness.md`）
- **chezmoi ローカル skill**: apm 外の user-scoped private skill。`local-skills/<name>/` を SoT に `run_onchange_after_deploy-local-skills.sh.tmpl` が `~/.agents/skills` / `~/.claude/skills` / `~/.codex/skills` へ配備（orphan-cleanup の `preserve_local_skills` で保護）。例: `to-pr`
- **settings.json `enabledPlugins`**: hook を含む plugin（security-guidance / LSP / codex）の runtime 有効化
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

## Agent skills

### Issue tracker

GitHub Issues（`gh` CLI）。外部 PR は triage 対象外。See `docs/agents/issue-tracker.md`.

### Triage labels

5役割ともラベル名 = 役割名（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context（`CONTEXT.md` は必要になり次第 lazy に作成、`docs/adr/` は意思決定記録の唯一の置き場）。`runtime/` は別レイヤー（home-wide 配備の ambient 環境知識のみ、決定記録は持たない）。See `docs/agents/domain.md`.
