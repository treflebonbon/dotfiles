# CLAUDE.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 実装は validated task worktree 内の source を編集する。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi diff` を確認し、変更した対象を `chezmoi apply <配備先パス>` で `~/` へ反映する。無関係な差分は反映せずユーザーへ報告する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。パス指定 apply で動かない script・Codex の同期・隔離 session からの手順は `docs/architecture.md` の編集・配備ルールを読む。

この `CLAUDE.md` / `AGENTS.md` は dotfiles repo を編集するための指示で、home へは配備しない（`.chezmoiignore`）。全 repo 共通の指示は `private_dot_claude/CLAUDE.md`（Claude Code）と `private_dot_config/codex/AGENTS.md`（Codex）に置き、repo 直下とグローバルの各ファイルは別々に保守し、共有する workflow / safety contract は整合させる。home 配下の repo に共通する環境知識は `~/runtime/index.md`（source は `runtime/`）、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- Git 認証は HTTPS + `gh auth git-credential` を使う。
- この dotfiles repo では、topic branch の push・PR 公開前に validated task worktree で `lefthook run test` を実行する（指示・文書 Markdown だけの変更なら `scripts/test-docs.sh` でよい）。通していない tree の push は `pre-push` hook が全 Bats を走らせるため5〜8 分ほど待たされる。Bats の実行・進捗確認・ログ・opt-in 検証の手順は先に `docs/conventions.md` を読む。

## Skill 配布経路の選択

- 11件の Agent Skill と共用 CLI・契約・browser 資産の正本は公開 `treflebonbon/skills`。dotfiles の固定 pin は `private_dot_config/nix-devshell/skills-plugin.json`、導入確認は `sync-skills-plugin` が担う。
- 第三者 skill は `apm.yml` / `apm.lock.yaml` から別途導入し、独自 dependency resolver や payload の dotfiles 内コピーは作らない。hook を含む別の Claude plugin は `private_dot_claude/settings.json.tmpl` の `enabledPlugins` で管理する。
- dotfiles は固定版の選択、runtime ごとの公式導入・設定、Nix / 端末固有の配線、移行前コピーの安全な撤去を所有する。契約と復旧は [ADR-0082](docs/adr/0082-extract-local-skills-to-public-repository.md) と `runtime/skill-harness.md` を読む。

配備先や lock 再生成手順を変更する前に `runtime/skill-harness.md` を読む。

## Agent skills

### Issue tracker

GitHub Issues（`gh` CLI）。外部 PR は triage 対象外。See `docs/agents/issue-tracker.md`.

### Triage labels

5役割ともラベル名 = 役割名（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context（`GLOSSARY.md` は必要になり次第 lazy に作成、`docs/adr/` は意思決定記録の唯一の置き場）。`runtime/` は別レイヤー（home-wide 配備の ambient 環境知識のみ、決定記録は持たない）。See `docs/agents/domain.md`.
