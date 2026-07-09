# AGENTS.md

chezmoi dotfiles repo。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。ログインシェルは bash。

**重要**: ファイル編集は chezmoi source（`chezmoi source-path` で確認。init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される）内で行う。`chezmoi apply` で `~/` に反映。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で反映。

`AGENTS.md` is the Codex / OpenCode / Zed / Cursor-facing instruction file. `CLAUDE.md` is maintained separately for Claude Code-specific guidance.

home 配下のどの repo でも共通するシェル環境・skill 配備・AI ランタイムの詳細は `~/runtime/`（Open Knowledge Format で書かれた知識バンドル、`runtime/index.md` が入口）を参照する。dotfiles repo 自身の構造・規約は `docs/architecture.md` / `docs/conventions.md`、意思決定記録（ADR）は `docs/adr/`（いずれも repo ローカル）を参照する。

## Architecture

2 種類の flake devShell がある。混同しないこと: **リポジトリ自体** (`./flake.nix`, chezmoi 編集用) と **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix`, 汎用ランタイム+横断ツール)。詳細な役割分担・ツール追加先の判断は `docs/architecture.md` を参照。

## Conventions

- コミット: Conventional Commits 形式（`cog verify` で検証）
- PR タイトル: squash merge の commit title になるため Conventional Commits 形式にする。`[codex]` などの prefix は付けない。
- Linting: lefthook pre-commit hook で自動実行（`lefthook.yml` 参照）
- 認証: HTTPS + `gh auth git-credential`。SSH は不使用。

## 設計→実装ワークフロー

メインフロー1本 + on-ramp 2つで構成する（ADR-0014、上流 `ask-matt` の main-flow/on-ramp 構造に整合）。**機能作業はまず `/to-worktree` で隔離 worktree に入ってから始める**（`git worktree add .worktrees/<topic>`。カレント checkout を汚さない）。ただし Orca セッション内（`orca` CLI、Linux では `orca-ide` が利用可能な時）は Orca worktree（`orca-cli` skill）を優先し、`/to-worktree` はそれ以外の環境で使う（ADR-0011）。**worktree は一度だけ入る** — 以降のスキルは同一 worktree/セッション内で連続実行し、都度 `to-worktree` には戻らない。

- **メインフロー**: `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`。要件がすでに確定している小さな作業では `grill-with-docs` / `to-spec` / `to-tickets` を省略し `implement` から直接入ってよい。`to-tickets` までを **Planner**、`implement`（内部で `tdd` / `code-review` を使う）を **Builder-Evaluator** と呼ぶ（`CONTEXT.md`）。Planner は人間との協働を維持するが、Builder-Evaluator は ticket をまたいで同一 worktree/branch 内なら止まらずループしてよい（単一セッション単位ではない — smart zone に達したら `/handoff` で別セッションへ）: `tdd` の green slice commit・`code-review` 後の修正 commit は確認なしで行い（根拠は ADR-0019 / ADR-0022）、ticket の AC からシームが一意に導出できればシーム確認も省略する（曖昧な場合や ticket 非経由では従来どおり確認）。対象 worktree/branch の全 ticket が完了したら `to-pr` を一度だけ実行する（AFK 運用時は自律呼出し可、通常運用は完了報告のうえユーザーの `/to-pr` 呼出しを待つ）。push / PR 作成の確認は変更しない。巨大で曖昧な作業は `wayfinder` で調査・決定 ticket の map を作ってから Planner / Builder-Evaluator へ合流する。
- **on-ramp**（メインフロー外から issue/バグが持ち込まれる入口）:
  - raw な issue（bug report・降ってきた要望等、`to-tickets` を経由していないもの）→ `triage` → ready-for-agent 化 → `implement` へ合流。`triage` は `to-tickets` の産出物には使わない（すでに ready-for-agent なため）
  - ハードなバグ（再現・原因調査が必要）→ `diagnosing-bugs` → `code-review` → `to-pr`。raw な報告として届いた場合はまず `triage` を通してから `diagnosing-bugs` へ

実装フェーズの user-invoked entrypoint は `implement`。`tdd` / `code-review` / `resolving-merge-conflicts` / `diagnosing-bugs` / `domain-modeling` / `codebase-design` / `prototype` / `research` は **model-invoked discipline** として必要時に自動発火する。各 product repo で最初に `setup-matt-pocock-skills` を実行し issue tracker / triage label / domain doc を構成する。domain doc は各 repo の `CONTEXT.md` + `docs/adr/` を使い、この repo の `runtime/` とは混ぜない。`to-pr` は実装後に条件付きブラウザ AC 検証 + PR 作成を行う chezmoi ローカル skill。迷ったら `ask-matt`（router）。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

実装中（`tdd` サイクル）に UI 要素を指差してその場で変更を指示したい場合は、実行ランタイムの要素指差しフィードバック機能を使う（Codex app（in-app browser）: Annotation Mode / Orca IDE: Design Mode / Claude Code: `claude-in-chrome`）。プレーンな Codex CLI（ターミナル）セッションにはこの機能は無い点に注意。ランタイム検出ロジックは不要 — エージェントは自身の実行ランタイムが何を持つか把握している。`playwright-cli` の代替ではなく、人間主導で UI を直接指差せる場合の追加の対話チャネル（ADR-0017）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`targets` は claude / codex。全 skill を共有ハブ `~/.agents/skills/` へ必ず materialize（target 非依存）し、Codex / Antigravity は `~/.agents/skills/` を直接読むため追加配線なしで可視。lock 再生成は `cd ~ && apm lock`（詳細は `runtime/skill-harness.md`）
- **chezmoi ローカル skill**: apm 外の user-scoped private skill。`local-skills/<name>/` を SoT に `run_onchange_after_deploy-local-skills.sh.tmpl` が各ランタイム skill dir へ配備。例: `to-pr`（実装完了後に条件付きブラウザ AC 検証 + PR 作成。Codex / Antigravity からも利用可）。`to-worktree` の使い方は上の「設計→実装ワークフロー」節を参照
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

Codex 固有の設定（config.toml / rules / hooks / environments）は `private_dot_config/codex/` を編集し、`run_onchange_after_codex-*.sh.tmpl` が `~/.codex/`（`$CODEX_HOME`）へマージ配置する。
