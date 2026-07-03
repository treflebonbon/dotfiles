# CLAUDE.md

chezmoi dotfiles repo。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。ログインシェルは bash。

**重要**: ファイル編集は `~/.local/share/chezmoi/` 内で行う。`chezmoi apply` で `~/` に反映。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で反映。

`CLAUDE.md` is the Claude Code-facing instruction file. `AGENTS.md` is maintained separately for Codex / OpenCode / Zed / Cursor-facing guidance.

アーキテクチャ・意思決定の詳細は `~/okf/`（Open Knowledge Format バンドル）を参照する。`okf/index.md` を入口に markdown リンクで辿れる。

## Architecture

2 種類の flake devShell がある。混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（lint / format / test 一式）。`cd ~/.local/share/chezmoi` で direnv が自動ロード。加えて per-repo flake の `templates` output（go/rust/elixir/perl/gleam/bun）を公開する。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム（node / python3 / bun）+ 横断ツール + AI ツール。`nix-direnv` で評価結果をキャッシュ。プロジェクト言語の toolchain（go/rust/elixir/perl/gleam）は持たず、per-repo `flake.nix` が供給する。

新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。テンプレ実体は `templates/<lang>/`。

ツール追加は用途で使い分ける: chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`、横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/`、プロジェクト言語ツール → per-repo flake / `templates/<lang>/`。

## Conventions

- コミット: Conventional Commits 形式（`cog verify` で検証）
- Linting: lefthook pre-commit hook で自動実行（`lefthook.yml` 参照）
- 認証: HTTPS + `gh auth git-credential`。SSH は不使用。

## 設計→実装ワークフロー

mattpocock skills の user-invoked チェーン（`grill-with-docs` → `to-prd` → `to-issues` → `triage` → `to-pr`）を使う。実装フェーズに user-invoked skill は無く、`triage` で ready にした issue を渡すと `tdd` / `code-review` / `diagnosing-bugs` / `domain-modeling` / `codebase-design` / `prototype` / `research` が **model-invoked で自動発火**する（上流ルール: user-invoked は他の user-invoked を呼ばない）。各 product repo で最初に `setup-matt-pocock-skills` を実行し issue tracker / triage label / domain doc を構成する。domain doc は各 repo の `CONTEXT.md` + `docs/adr/` を使い、この repo の `okf/` とは混ぜない。`to-pr` は実装後に条件付きブラウザ AC 検証 + draft PR 作成を行う chezmoi ローカル skill。迷ったら `ask-matt`（router）。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`targets` は claude / codex。全 skill を APM-native の共有ハブ `~/.agents/skills/` へ必ず materialize（target 非依存）し、Codex / Antigravity は `~/.agents/skills/` を直接読むため追加配線なしで可視。hook を持たない外部 skill-only は apm 経由。lock 再生成は `cd ~ && apm lock`（詳細は `okf/skill-harness.md`）
- **chezmoi ローカル skill**: apm 外の user-scoped private skill。`local-skills/<name>/` を SoT に `run_onchange_after_deploy-local-skills.sh.tmpl` が `~/.agents/skills` / `~/.claude/skills` / `~/.codex/skills` へ配備（orphan-cleanup の `preserve_local_skills` で保護）。例: `to-pr`
- **settings.json `enabledPlugins`**: hook を含む plugin（security-guidance / LSP / codex）の runtime 有効化
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

## Resources

詳細は `~/okf/`（architecture, shell-environment, skill-harness, ai-runtimes, conventions, decisions）を参照。
