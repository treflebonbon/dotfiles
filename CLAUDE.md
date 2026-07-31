# CLAUDE.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 編集は `chezmoi source-path` が示す source 内で行い、`chezmoi apply` で `~/` に反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。

`CLAUDE.md` は Claude Code 向け、`AGENTS.md` は Codex / OpenCode / Zed / Cursor 向けとして別々に保守する。home 配下の repo に共通する環境知識は `~/runtime/index.md`、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- コミットは Conventional Commits 形式にし、`cog verify` と lefthook pre-commit hook で検証する。
- Git 認証は HTTPS + `gh auth git-credential` を使う。
- ユーザーが結果を依頼し内容が確定した後は、非破壊な GitHub 定型書込みは二重確認しない。topic branch は `git-push-topic` で公開し、force-push は行わない。default branch の直接 push は明示承認後に `git-push-reviewed` を使い、merge、close/reopen/delete、release、workflow dispatch、repository settings/secrets は事前確認する。

## 設計→実装ワークフロー

1つの作業では1つの隔離 worktree を使う。Claude Code では `EnterWorktree`、Orca セッションでは Orca worktree、それ以外では `/to-worktree` を使い、以降の skill は同じ worktree で連続実行する。

- 要件未確定: `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`
- 要件確定済み: `implement` → `to-pr`
- raw issue: `triage` で ready-for-agent 化してから `implement`
- 再現・原因調査が必要なバグ: `diagnosing-bugs` → `code-review` → `to-pr`

自律実行範囲、Contract、Verification Matrix、Parent Reconciliation、各 skill のローカル上書きは `runtime/skill-harness.md` と関連 ADR を正本とする。特に次を守る:

- `triage` は推薦根拠の read-only 検証を先に実行できる。内容確定後の定型 issue/label 書込みは再確認せず、close/reopen/delete は確認する。
- Builder-Evaluator 内の `code-review` は既知の base（通常 `origin/main`）を使う。standalone で base が不明な場合は確認する。
- `gh-address-comments` は thread-aware な read/write を `gh-review-thread` に統一する。review コメントの修正依頼は、選択 thread 群を1つの Review Round として修正・検証・1 commit・`git-push-topic`・日本語返信・resolve まで行う承認を含む。

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
