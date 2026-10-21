# AGENTS.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 実装は validated task worktree 内の source を編集する。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi apply` して `~/` へ反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。

この `CLAUDE.md` / `AGENTS.md` は dotfiles repo を編集するための指示で、home へは配備しない（`.chezmoiignore`）。全 repo 共通の指示は `private_dot_claude/CLAUDE.md`（Claude Code）と `private_dot_config/codex/AGENTS.md`（Codex）に置き、repo 直下とグローバルの各ファイルは別々に保守し、共有する workflow / safety contract は整合させる。home 配下の repo に共通する環境知識は `~/runtime/index.md`（source は `runtime/`）、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- Git 認証は HTTPS + `gh auth git-credential` を使う。
- この dotfiles repo では、topic branch の push・PR 公開前に validated task worktree で `lefthook run test` を実行する（指示・文書 Markdown だけの変更は `scripts/test-docs.sh`）。Bats の実行・進捗確認・ログ・opt-in 検証の手順は先に `docs/conventions.md` を読む。

## Skill 配布経路の選択

- 外部 skill / plugin は `apm.yml` / `apm.lock.yaml`
- user-scoped private skill は `local-skills/<name>/`
- CLI バイナリは nix devshell

配備先や lock 再生成手順を変更する前に `runtime/skill-harness.md` を読む。Codex 固有設定は `private_dot_config/codex/` を編集し、`run_onchange_after_codex-managed-sync.sh.tmpl` で `$CODEX_HOME` へ反映する。

## Agent skills

Issue tracker は GitHub Issues（`gh` CLI、外部 PR は triage 対象外）、triage ラベル名は役割名と同一、domain docs は single-context。詳細は `docs/agents/issue-tracker.md`、`docs/agents/triage-labels.md`、`docs/agents/domain.md` を読む。
