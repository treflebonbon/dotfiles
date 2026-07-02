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

mattpocock skills（`grill-with-docs` → `to-prd` → `to-issues` → `triage` → `tdd`）を使う。各 product repo で最初に `setup-matt-pocock-skills` を実行し issue tracker / triage label / domain doc を構成する。domain doc は各 repo の `CONTEXT.md` + `docs/adr/` を使い、この repo の `okf/` とは混ぜない。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`~/.claude/skills/` へ展開。hook を持たない skill-only は apm が唯一の管理点
- **settings.json `enabledPlugins`**: hook を含む plugin（security-guidance / LSP / codex）の runtime 有効化
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

## Resources

詳細は `~/okf/`（architecture, shell-environment, skill-harness, ai-runtimes, conventions, decisions）を参照。
