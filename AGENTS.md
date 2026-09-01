# AGENTS.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 実装は validated task worktree 内の source を編集する。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi apply` して `~/` へ反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。

`AGENTS.md` は Codex / OpenCode / Zed / Cursor 向け、`CLAUDE.md` は Claude Code 向けとして別々に保守する。home 配下の repo に共通する環境知識は `~/runtime/index.md`、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- コミットと PR タイトルは Conventional Commits 形式にし、PR タイトルへ `[codex]` などの prefix を付けない。`cog verify` と lefthook pre-commit hook で検証する。
- Git 認証は HTTPS + `gh auth git-credential` を使う。
- ユーザーが結果を依頼し内容が確定した後は、非破壊な GitHub 定型書込みは二重確認しない。topic branch は `git-push-topic` で公開し、force-push は行わない。default branch の直接 push は明示承認後に `git-push-reviewed` を使い、merge、close/reopen/delete、release、workflow dispatch、repository settings/secrets は事前確認する。

## 設計→実装ワークフロー

Worktree Entry Point は validated task worktree から workflow を始める共通契約とする。Orca では agent session の開始前に Orca native worktree を作成・選択し、Agent Picker から built-in agent を起動する。local file の変更につながる engineering flow は current checkout が linked worktree か read-only に検証し、primary checkout なら編集や外部書込みを始めず、Orca native worktree から新しい agent session を開始するよう案内する。非 Orca runtime では `/to-worktree` を使い、以降の skill は同じ checkout で続ける。

- 要件未確定: `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`
- 要件確定済み: `implement` → `to-pr`
- raw issue: `triage` で ready-for-agent 化してから `implement`
- 再現・原因調査が必要なバグ: `diagnosing-bugs` → `code-review` → `to-pr`

Matt Pocock skill の workflow / safety contract、phase boundary、自律実行範囲、Contract、Verification Matrix、Parent Reconciliation、ローカル上書きを判断するときは `runtime/skill-harness.md` と関連 ADR を読む。

## ブラウザ操作ツール

Orca 内蔵 page は `orca-cli`、外部 Web page の自動操作は `playwright-cli` または CDP、外部 browser window や native app の OS/window-level 操作は `computer-use` を使う。Chrome MV3 拡張は persistent Chromium context で検証する。`tdd` 中に人間が UI 要素を指差す場合は、実行ランタイムの要素指差しフィードバック機能を追加チャネルとして使う。役割の違いは ADR-0017 を参照する。

## Skill 配布経路の選択

- 外部 skill / plugin は `apm.yml` / `apm.lock.yaml`
- user-scoped private skill は `local-skills/<name>/`
- CLI バイナリは nix devshell

配備先や lock 再生成手順を変更する前に `runtime/skill-harness.md` を読む。Codex 固有設定は `private_dot_config/codex/` を編集し、`run_onchange_after_codex-*.sh.tmpl` で `$CODEX_HOME` へ反映する。
