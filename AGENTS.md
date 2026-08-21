# AGENTS.md

chezmoi dotfiles repo。ログインシェルは bash。

**重要**: 編集は `chezmoi source-path` が示す source 内で行い、`chezmoi apply` で `~/` に反映する。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source に戻す。

`AGENTS.md` は Codex / OpenCode / Zed / Cursor 向け、`CLAUDE.md` は Claude Code 向けとして別々に保守する。home 配下の repo に共通する環境知識は `~/runtime/index.md`、この repo の構造・規約・判断は `docs/architecture.md`、`docs/conventions.md`、`docs/adr/` を参照する。

## Architecture

flake devShell は、リポジトリ編集用の `./flake.nix` と、汎用ランタイム・横断ツール用の `private_dot_config/nix-devshell/flake.nix` を分けている。ツールの追加先は `docs/architecture.md` で判断する。

## Conventions

- コミットと PR タイトルは Conventional Commits 形式にし、PR タイトルへ `[codex]` などの prefix を付けない。`cog verify` と lefthook pre-commit hook で検証する。
- Git 認証は HTTPS + `gh auth git-credential` を使う。
- ユーザーが結果を依頼し内容が確定した後は、非破壊な GitHub 定型書込みは二重確認しない。topic branch は `git-push-topic` で公開し、force-push は行わない。default branch の直接 push は明示承認後に `git-push-reviewed` を使い、merge、close/reopen/delete、release、workflow dispatch、repository settings/secrets は事前確認する。

## 設計→実装ワークフロー

1つの作業では1つの隔離 worktree を使う。Orca セッションでは Orca worktree を優先し、それ以外では `/to-worktree` を使う。以降の skill は同じ worktree で連続実行する。

- 要件未確定: `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`
- 要件確定済み: `implement` → `to-pr`
- raw issue: `triage` で ready-for-agent 化してから `implement`
- 再現・原因調査が必要なバグ: `diagnosing-bugs` → `code-review` → `to-pr`

## v1.2.3 workflow contract

- `grilling` は frontier round 単位で、依存関係が解決済みの質問をまとめて推奨付きで提示し、各 round の人間の回答を待つ。事実は環境から調べ、decision は推測して進めない。`AGENTS.md` と `CLAUDE.md` は別管理だが、共有する workflow / safety contract は整合させる。
- phase boundary の公式5択は `Continue → /clear → /handoff → Subagent → /compact`。次 phase が現 phase を primary source として必要、または smart zone（目安 ~150k tokens）に収まるなら `Continue`。context が無関係なら `/clear`。portability が必要な場合だけ `/handoff`。AFK の scoped task は `Subagent`。同じ harness / directory の relevant context は `/compact` で引き継ぐ。
- Builder-Evaluator は同じ worktree/branch で ticket をまたいで継続できる。ticket 境界でも同じ harness / directory なら `/compact`、portability が必要な場合だけ `/handoff` とし、既存の tdd / code-review / Verification Matrix / `to-pr` 一回の境界を維持する。
- model-invoked discipline は current repository の実装契約内で動く。外部書込みは親 Contract または明示的に起動した user-invoked skill の範囲に限り、機密情報・credential・CI secret を読み出し、出力、commit、無断変更しない。権限拡大や permission bypass は推測せず、runtime profile に従い必要ならユーザーへ戻す。
- `prototype` の logic path は single self-contained HTML とし、build / server 不要で、inline pure logic、free-play、guided walkthroughs、操作後の全 state 表示を持つ。決定を本実装へ反映した後も prototype 全体を throwaway branch に primary source として残し、implementation issue から参照する。main branch には decision だけを残す。

自律実行範囲、Contract、Verification Matrix、Parent Reconciliation、各 skill のローカル上書きは `runtime/skill-harness.md` と関連 ADR を正本とする。特に次を守る:

- `triage` は推薦根拠の read-only 検証を先に実行できる。内容確定後の定型 issue/label 書込みは再確認せず、close/reopen/delete は確認する。
- Builder-Evaluator 内の `code-review` は既知の base（通常 `origin/main`）を使う。standalone で base が不明な場合は確認する。
- `gh-address-comments` は thread-aware な read/write を `gh-review-thread` に統一する。review コメントの修正依頼は、選択 thread 群を1つの Review Round として修正・検証・1 commit・`git-push-topic`・日本語返信・resolve まで行う承認を含む。

実装依頼の入口は `implement`。必要な discipline skill（`tdd`、`code-review`、`diagnosing-bugs` など）は実装中に適用する。

## ブラウザ操作ツール

ブラウザ操作は `playwright-cli` skill を使い、Chrome MV3 拡張は persistent Chromium context で検証する。`tdd` 中に人間が UI 要素を指差す場合は、実行ランタイムの要素指差しフィードバック機能を追加チャネルとして使う。役割の違いは ADR-0017 を参照する。

## Skill 配布経路の選択

- 外部 skill / plugin は `apm.yml` / `apm.lock.yaml`
- user-scoped private skill は `local-skills/<name>/`
- CLI バイナリは nix devshell

配備先や lock 再生成手順を変更する前に `runtime/skill-harness.md` を読む。Codex 固有設定は `private_dot_config/codex/` を編集し、`run_onchange_after_codex-*.sh.tmpl` で `$CODEX_HOME` へ反映する。
