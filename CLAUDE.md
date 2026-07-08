# CLAUDE.md

chezmoi dotfiles repo。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。ログインシェルは bash。

**重要**: ファイル編集は chezmoi source（`chezmoi source-path` で確認。init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される）内で行う。`chezmoi apply` で `~/` に反映。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で反映。

`CLAUDE.md` is the Claude Code-facing instruction file. `AGENTS.md` is maintained separately for Codex / OpenCode / Zed / Cursor-facing guidance.

home 配下のどの repo でも共通するシェル環境・skill 配備・AI ランタイムの詳細は `~/runtime/`（Open Knowledge Format バンドル、home-wide 配備）を参照する。`runtime/index.md` を入口に markdown リンクで辿れる。dotfiles repo 自身の構造は `docs/architecture.md`、規約は `docs/conventions.md`（いずれも repo ローカル、home 非配備）を参照。意思決定記録（ADR）は `docs/adr/`（repo root、連番ファイル名）に一本化されている。

## Architecture

2 種類の flake devShell がある。混同しないこと: **リポジトリ自体** (`./flake.nix`, chezmoi 編集用) と **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix`, 汎用ランタイム+横断ツール)。詳細な役割分担・ツール追加先の判断は `docs/architecture.md` を参照。

## Conventions

- コミット: Conventional Commits 形式（`cog verify` で検証）
- Linting: lefthook pre-commit hook で自動実行（`lefthook.yml` 参照）
- 認証: HTTPS + `gh auth git-credential`。SSH は不使用。

## 設計→実装ワークフロー

メインフロー1本 + on-ramp 2つで構成する（ADR-0014、上流 `ask-matt` の main-flow/on-ramp 構造に整合）。**機能作業はまず `/to-worktree` で隔離 worktree に入ってから始める**（Claude Code は `EnterWorktree` ツール優先。カレント checkout を汚さない）。ただし Orca セッション内（`orca` CLI、Linux では `orca-ide` が利用可能な時）は Orca worktree（`orca-cli` skill）を優先し、`/to-worktree` はそれ以外の環境で使う（ADR-0011）。**worktree は一度だけ入る** — 以降のスキルは同一 worktree/セッション内で連続実行し、都度 `to-worktree` には戻らない。

- **メインフロー**: `grill-with-docs` → `to-prd` → `to-issues` → `tdd` → `code-review` → `to-pr`。要件がすでに確定している小さな作業では `grill-with-docs` / `to-prd` / `to-issues` を省略し `tdd` から直接入ってよい。`to-issues` までを **Planner**、`tdd`↔`code-review` を **Builder-Evaluator** と呼ぶ（`CONTEXT.md`）。Planner は人間との協働を維持するが、Builder-Evaluator は `to-issues` が生成した issue をまたいで同一 worktree/branch 内なら止まらずループしてよい（**単一の連続セッションが単位ではない** — smart zone、~120k トークンに達したら `/handoff` で別セッションへ移ってよく、複数セッションが同一 worktree/branch を扱うことも許容される）: `tdd` の各 green slice、および `code-review` でブロッキングな指摘が無いことを確認した後の修正差分は、いずれも**確認なしで commit する**（permission mode による分岐は設けない。commit 確認は人間が不在の AFK 運用でこそ機能せず、安全機構として成立しないため——詳細は ADR-0018）。対象 issue の AC からシームが一意に導出できる場合は `tdd` のシーム確認も省略する（AC 単体で判断がつかない曖昧なケースや、issue を経由しない単体呼び出しでは従来どおり確認する）。review integrity は人間の目視ではなく、worktree 隔離・自動テスト（`tdd` の red-green 必須化・`lefthook` の pre-commit hook）・`to-pr` が最後に開く PR のレビューという3層で担保する。対象 worktree/branch 上の全 issue が完了したら `to-pr` を一度だけ実行する（issue ごとの個別 PR は作らない）。AFK 運用が明示指示された場合はエージェントが自律的に `to-pr` まで進めてよく、そうでない通常運用では完了報告のうえユーザーの明示的な `/to-pr` 呼び出しを待つ。push / PR 作成自体の確認は変更しない。
- **on-ramp**（メインフロー外から issue/バグが持ち込まれる入口）:
  - raw な issue（bug report・降ってきた要望等、`to-issues` を経由していないもの）→ `triage` → ready-for-agent 化 → `tdd` へ合流。`triage` は `to-issues` の産出物には使わない（すでに ready-for-agent なため）
  - ハードなバグ（再現・原因調査が必要）→ `diagnosing-bugs` → `code-review` → `to-pr`。raw な報告として届いた場合はまず `triage` を通してから `diagnosing-bugs` へ

いずれの経路も実装フェーズに user-invoked skill は無く、`tdd` / `code-review` / `diagnosing-bugs` / `domain-modeling` / `codebase-design` / `prototype` / `research` が **model-invoked で自動発火**する（上流ルール: user-invoked は他の user-invoked を呼ばない）。各 product repo で最初に `setup-matt-pocock-skills` を実行し issue tracker / triage label / domain doc を構成する。domain doc は各 repo の `CONTEXT.md` + `docs/adr/` を使い、この repo の `runtime/` とは混ぜない。`to-pr` は実装後に条件付きブラウザ AC 検証 + PR 作成を行う chezmoi ローカル skill。迷ったら `ask-matt`（router）。

## ブラウザ操作ツール

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショット取得は `playwright-cli` skill を使う。Chrome MV3 拡張の検証は Playwright の persistent Chromium context を使う。`browser-use` は明示指定がある場合のみ（`uv tool run browser-use@<version>`）。

実装中（`tdd` サイクル）に UI 要素を指差してその場で変更を指示したい場合は、実行ランタイムの要素指差しフィードバック機能を使う（Codex app（in-app browser）: Annotation Mode / Orca IDE: Design Mode / Claude Code: `claude-in-chrome`）。プレーンな Codex CLI（ターミナル）セッションにはこの機能は無い点に注意。ランタイム検出ロジックは不要 — エージェントは自身の実行ランタイムが何を持つか把握している。`playwright-cli` の代替ではなく、人間主導で UI を直接指差せる場合の追加の対話チャネル（ADR-0017）。

## Skill 配布経路の選択

- **APM 経由** (`apm.yml` / `apm.lock.yaml`): 外部 skill / plugin。`targets` は claude / codex。全 skill を APM-native の共有ハブ `~/.agents/skills/` へ必ず materialize（target 非依存）し、Codex / Antigravity は `~/.agents/skills/` を直接読むため追加配線なしで可視。hook を持たない外部 skill-only は apm 経由。lock 再生成は `cd ~ && apm lock`（詳細は `runtime/skill-harness.md`）
- **chezmoi ローカル skill**: apm 外の user-scoped private skill。`local-skills/<name>/` を SoT に `run_onchange_after_deploy-local-skills.sh.tmpl` が `~/.agents/skills` / `~/.claude/skills` / `~/.codex/skills` へ配備（orphan-cleanup の `preserve_local_skills` で保護）。例: `to-pr`
- **settings.json `enabledPlugins`**: hook を含む plugin（security-guidance / LSP / codex）の runtime 有効化
- **nix devshell**: CLI バイナリ（AI ツール / playwright-cli）

## Agent skills

### Issue tracker

GitHub Issues（`gh` CLI）。外部 PR は triage 対象外。See `docs/agents/issue-tracker.md`.

### Triage labels

5役割ともラベル名 = 役割名（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context（`CONTEXT.md` は必要になり次第 lazy に作成、`docs/adr/` は意思決定記録の唯一の置き場）。`runtime/` は別レイヤー（home-wide 配備の ambient 環境知識のみ、決定記録は持たない）。See `docs/agents/domain.md`.
