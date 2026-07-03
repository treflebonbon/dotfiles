# AGENTS.md

chezmoi dotfiles repo。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。ログインシェルは bash。

**重要**: ファイル編集は chezmoi source（`chezmoi source-path` で確認。init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される）内で行う。`chezmoi apply` で `~/` に反映。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で反映。

`AGENTS.md` is the Codex / OpenCode / Zed / Cursor-facing instruction file. `CLAUDE.md` is maintained separately for Claude Code-specific guidance.

アーキテクチャ・意思決定の詳細は `~/okf/`（Open Knowledge Format バンドル、`okf/index.md` が入口）を参照する。

## Architecture

2 種類の flake devShell がある。混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（lint / format / test 一式）。`cd "$(chezmoi source-path)"` で direnv が自動ロード。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム + 横断ツール + AI ツール。`nix-direnv` で評価結果をキャッシュ。プロジェクト言語の toolchain は per-repo `flake.nix` が供給する。

新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。

ツール追加は用途で使い分ける: chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`、横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/`、プロジェクト言語ツール → per-repo flake / `templates/<lang>/`。

## Conventions

- コミット: Conventional Commits 形式（`cog verify` で検証）
- PR タイトル: squash merge の commit title になるため Conventional Commits 形式にする。`[codex]` などの prefix は付けない。
- Linting: lefthook pre-commit hook で自動実行（`lefthook.yml` 参照）
- 認証: HTTPS + `gh auth git-credential`。SSH は不使用。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`targets` は claude / codex。全 skill を共有ハブ `~/.agents/skills/` へ必ず materialize（target 非依存）し、Codex / Antigravity は `~/.agents/skills/` を直接読むため追加配線なしで可視。lock 再生成は `cd ~ && apm lock`（詳細は `okf/skill-harness.md`）
- **chezmoi ローカル skill**: apm 外の user-scoped private skill。`local-skills/<name>/` を SoT に `run_onchange_after_deploy-local-skills.sh.tmpl` が各ランタイム skill dir へ配備。例: `to-worktree`（機能作業の入口で `git worktree add .worktrees/<topic>` により隔離。カレント checkout を汚さない）/ `to-pr`（実装完了後に条件付きブラウザ AC 検証 + draft PR 作成。Codex / Antigravity からも利用可）
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

Codex 固有の設定（config.toml / rules / hooks / environments）は `private_dot_config/codex/` を編集し、`run_onchange_after_codex-*.sh.tmpl` が `~/.codex/`（`$CODEX_HOME`）へマージ配置する。

## Resources

詳細は `~/okf/`（architecture, shell-environment, skill-harness, ai-runtimes, conventions, decisions）を参照。
