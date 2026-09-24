# CLAUDE.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 実装は validated task worktree 内の source を編集する。`chezmoi source-path` が示す live source は配備元の確認にのみ使い、`chezmoi apply` は受入後に live source から実行して `~/` へ反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。

`CLAUDE.md` は Claude Code 向け、`AGENTS.md` は Codex / OpenCode / Zed / Cursor 向けとして別々に保守する。home 配下の repo に共通する環境知識は `~/runtime/index.md`、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- コミットと PR タイトルは Conventional Commits 形式にする。
- Git 認証は HTTPS + `gh auth git-credential` を使う。
- ユーザーが結果を依頼し内容が確定した後は、非破壊な GitHub 定型書込みは二重確認しない。`to-pr` 呼出しまたは AFK 完了許可は、本文で宣言済みの missing native edge の追加だけを承認対象に含む。topic branch は `git-push-topic` で公開し、force-push は行わない。default branch の直接 push は明示承認後に `git-push-reviewed` を使い、merge、close/reopen/delete、release、workflow dispatch、repository settings/secrets は事前確認する。

## 設計→実装ワークフロー

実装は task worktree で行い、作成・選択は実行環境の native 機構に任せる。作業開始時の確認、Herdr / Orca / Claude Code / Codex の起動経路、Git 管理情報を参照できない場合の復旧は `runtime/skill-harness.md` の「Worktree の開始と復旧」を読む。以降の phase は同じ checkout で続ける。

- 要件未確定: `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`
- 要件確定済み: `implement` → `to-pr`
- raw issue: `triage` で ready-for-agent 化してから `implement`
- 再現・原因調査が必要なバグ: `diagnosing-bugs` → `code-review` → `to-pr`

## Matt Pocock workflow contract

`grilling` / cross-skill 呼出し / phase boundary（`Continue → /clear → /handoff → Subagent → /compact`）/ Builder-Evaluator の継続条件 / model-invoked discipline / `prototype` lifecycle の詳細契約、および `triage` / `code-review` / `gh-review-thread` / `empirical-prompt-tuning` のローカル上書きは `runtime/skill-harness.md` の「apm 管理の外部 skill」「Managed workflow semantics と local safety boundary」と関連 ADR を正本とする。

実装依頼の入口は `implement`。必要な discipline skill（`tdd`、`code-review`、`diagnosing-bugs` など）は実装中に適用する。

## ブラウザ操作ツール

通常のブラウザ操作は `playwright-cli` skill を使い、Chrome MV3 拡張は persistent Chromium context で検証する。`tdd` 中に人間が UI 要素を指差す場合は、利用可能な `claude-in-chrome` を追加チャネルとして使う。役割の違いは ADR-0017 を参照する。

## Skill 配布経路の選択

外部 skill / plugin は `apm.yml` / `apm.lock.yaml`、user-scoped private skill は `local-skills/<name>/`、hook を含む Claude plugin は `private_dot_claude/settings.json.tmpl` の `enabledPlugins`、CLI バイナリは nix devshell で管理する。

配備先や lock 再生成手順を変更する前に `runtime/skill-harness.md` を読む。

## Agent skills

### Issue tracker

GitHub Issues（`gh` CLI）。外部 PR は triage 対象外。See `docs/agents/issue-tracker.md`.

### Triage labels

5役割ともラベル名 = 役割名（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context（`CONTEXT.md` は必要になり次第 lazy に作成、`docs/adr/` は意思決定記録の唯一の置き場）。`runtime/` は別レイヤー（home-wide 配備の ambient 環境知識のみ、決定記録は持たない）。See `docs/agents/domain.md`.
