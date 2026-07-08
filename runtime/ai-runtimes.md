---
type: concept
title: AI runtimes
description: nix-devshell の AI ツールと Claude Code / Codex マルチランタイム設定、更新経路
tags: [ai, claude-code, codex, nix, llm-agents]
---

# AI runtimes

## nix-devshell の AI ツール

AI/LLM ツールは `github:numtide/llm-agents.nix` flake 経由で管理（`modules/ai.nix`）:

- **LLM CLI**: claude-code, codex, copilot-cli, antigravity
- **ワークフロー**: rtk

外部 skill / plugin は apm が担当する（→ [skill-harness](skill-harness.md)）。Nix devshell は CLI バイナリを供給する。

## Claude Code / Codex マルチランタイム

workflow パイプライン（mattpocock skills）は Claude Code の Skill tool 前提だが、汎用コーディングは Codex でも行える二刀流を維持する。

- **Claude**: `private_dot_claude/settings.json.tmpl` → `~/.claude/settings.json`。`language: japanese`、`effortLevel: xhigh`、`teammateMode: auto`、`model: sonnet` + `advisorModel: opus`（experimental advisor tool、下記参照）、deny ルール群、`enabledPlugins`（LSP / codex / security-guidance / claude-code-setup）。個人・端末差分は `~/.claude/settings.local.json`（管理外）。
- **Codex**: `private_dot_config/codex/`（config.toml / rules / AGENTS.md / hooks.json / environments）を `run_onchange_after_codex-*.sh.tmpl` が `~/.config/codex/` 経由で `~/.codex/`（`$CODEX_HOME`）へマージ配置する。宣言的設定のみ管理しローカル state は保全する。
- **AGENTS.md** — Codex / OpenCode / Zed / Cursor 向け指示（`~/AGENTS.md`、`private_dot_gemini/AGENTS.md` は Gemini 向け）。CLAUDE.md は Claude Code 向けに別管理。

MCP サーバーは `.mcp.json` / `private_dot_mcp.json` で設定（context7 / serena / effect-docs）。

## AI ツール更新の 2 経路

| 経路                | 対象                                       | 管理ファイル                                                            |
| ------------------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| nix devshell binary | claude-code / codex / copilot-cli / rtk 等 | `private_dot_config/nix-devshell/{flake.nix,modules/ai.nix,packages/*}` |
| APM skill / plugin  | 外部 skill / Claude marketplace plugin     | `apm.yml` / `apm.lock.yaml`                                             |

「AI ツールを更新したい」ときは両経路を確認する。

baseline は `modules/ai.nix` の `minClaudeCode` assert で床固定する（現 `2.1.204`）。床の根拠はモデル品質（Sonnet 5 default）＋ 多 agent ワークフロー・worktree 隔離の信頼性（error 伝搬・background daemon 安定化・worktree 隔離破れの修正）。

`llm-agents` flake input は 2026-07-06 に再度 `nix flake update` で最新化（claude-code 2.1.200 → 2.1.201 が追従、他の消費パッケージ [codex/copilot-cli/antigravity-cli/rtk/apm] は変化なし）。2.1.201 の変更点は「Sonnet 5 セッションで harness reminder の system role を廃止」のみで settings/workflow への影響なし、と確認した上でフロアは 2.1.200 のまま据え置いた。

2026-07-08、v2.1.204 の release note（`SessionStart` hook がヘッドレスセッションでイベントをストリーミングせず、リモートワーカーが hook 実行中に idle-reap してしまう不具合の修正）をきっかけに `nix flake update llm-agents` を実施し、claude-code 2.1.201 → 2.1.204 が追従（他の消費パッケージは変化なし）。今回は 2.1.201 のときと異なり、2.1.202-2.1.204 の変更点を確認した結果、この repo の床根拠（多 agent ワークフロー・worktree 隔離の信頼性）に直撃する修正が複数見つかったため、フロアを `2.1.200` → `2.1.204` へ引き上げた:

- worktree 隔離済み subagent が親 checkout でコマンドを実行してしまうバグ修正（2.1.203）— `to-worktree` が前提とする隔離保証そのものに関わる
- background daemon の auto-upgrade 失敗が実行中の全 background session を巻き添えに停止させるバグ修正（2.1.203）
- `claude agents` 復帰時に実行中の subagent を無言で停止し最初からやり直すバグ修正（2.1.203）
- 多数の git worktree を持つリポジトリでの `resuming a session` の遅延/メモリ肥大（2.1.202）、`Bash` の "argument list too long" 失敗（2.1.203）の修正 — `worktree-gc` が対象とする状況と重なる
- ヘッドレスセッションでの `SessionStart` hook イベントストリーミング不具合・idle-reap 誤爆の修正（2.1.204）

## claude-code 2.1.199 以降の挙動変更（設計→実装ワークフローへの影響）

`settings.json` は変更せず、認識だけ合わせる。ワークフロー側ドキュメント（CLAUDE.md の設計→実装ワークフロー / [skill-harness](skill-harness.md)）からはここを参照する。

- **subagent が既定で background 実行**（2.1.198）— 委譲中も本流が進み完了通知が来る。`teammateMode: auto` と整合。
- **worktree 完了時に自動 commit / push / draft PR**（2.1.198）— `claude agents` 起動の background agent は worktree でのコード作業を終えると停止して尋ねず自動で draft PR を開く。`to-worktree` → `to-pr` の想定と重なるので二重 PR に注意。
- **stacked slash-skill が先頭 5 個までロード**（2.1.199）— `/skill-a /skill-b ...` で先頭 skill だけでなく先頭 5 個を全ロード。user-invoked チェーンの連結起動に効く。
- **subagent の error 伝搬修正**（2.1.199）— rate-limit / API error を「成功」と誤報せず親へ正確に伝える。多 agent 実行の信頼性が上がる。
- **Explore agent が main model を継承**（opus cap, 2.1.198）／**`/agents` wizard 削除**（`.claude/agents/` 直接編集 or Claude に依頼）。
- **default permission mode が `"default"` → `"Manual"` へ変更**（2.1.200）— `settings.json.tmpl` は `defaultMode` を明示していないため、この変更をそのまま受ける。`skipDangerousModePermissionPrompt` / `skipAutoPermissionPrompt` は 2.1.200 でも設定として残存しており、動作に競合はない（インストール済みバイナリの文字列を確認済み）。
- **AskUserQuestion がアイドルでも既定で自動継続しなくなった**（2.1.200）— `CLAUDE_AFK_TIMEOUT_MS` でアイドル自動継続へオプトイン可能だが、選択は自分で行いたいため意図的に設定せず、既定（自動継続しない）のままにしている。
- **background session の安定化**（2.1.200）— sleep/resume 後や stale セッション再開時の途中終了、stale daemon による乗っ取りを修正。
- **`/review <pr>` が単一パスに戻り、複数エージェントレビューは `/code-review <level> <pr#>` に変更**（2.1.202）— `code-review` は Claude Code 本体の built-in skill 名でもあり、この repo は同名の `code-review` skill（mattpocock 経由 vendored、`~/.claude/skills/code-review`）を導入済み。2.1.204 バイナリの文字列解析で「同名の project skill は built-in skill を完全に shadow する（例外は project-specific な追記を許す `verify` のみ）」という設計文言を確認済み。`code-review` は例外に含まれないため、この repo の `/code-review` は常にこの repo 自身の Standards/Spec レビュー skill が実行され、ネイティブの multi-agent ultra-review には衝突しない。
- **worktree 隔離済み subagent が親 checkout でコマンドを実行してしまう不具合を修正**（2.1.203）— `to-worktree` が前提とする隔離保証そのものに関わるバグ。
- **background daemon の auto-upgrade 失敗が実行中の全 background session を巻き添えに停止させる不具合を修正**（2.1.203）。
- **`claude agents` 復帰時に実行中の subagent を無言で停止し最初からやり直してしまう不具合を修正**（2.1.203）— 進行中の作業が黙って失われる問題。
- **多数の git worktree を持つ repo でのセッション再開の遅延/メモリ肥大**（2.1.202）・**`Bash` の "argument list too long" 失敗**（2.1.203）を修正 — `worktree-gc` が対象とする「worktree が溜まった」状況と重なる。
- **background agent の working directory が削除/置換/無効化された場合、crash-loop せず明確なエラー1回で失敗するよう変更**（2.1.203）— `worktree-gc` が worktree を回収した後もその worktree で agent が生きていたケースに対応。
- **ヘッドレスセッションで `SessionStart` hook のイベントがストリーミングされず、リモートワーカーが hook 実行中に idle-reap してしまう不具合を修正**（2.1.204）。

### Advisor tool（experimental, 2.1.200 時点でも undocumented）

`settings.json.tmpl` の `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` + `advisorModel: "opus"` で、より高性能なモデル（advisor）が会話全体を読んで途中で助言する [Advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)（Anthropic API 側の beta 機能）を Claude Code 本体にも既定で有効化している。

- GitHub Release Notes（v2.1.200 時点）に記載が一切ない undocumented な機能。インストール済みバイナリの文字列解析で存在と挙動を確認: env var 未設定でも内部の段階的ロールアウトフラグ（`tengu_sage_compass2`）で一部セッションは既に有効化されうる。env var を明示すると (a) そのロールアウトフラグをバイパスして強制 ON、(b) `advisorModel` の互換性チェック（advisor はベースモデル以上の能力が必要、という catalog 上の rank 比較）も丸ごとスキップされる。
- 緊急停止用に `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` という kill switch も存在する。
- advisor 呼び出しは advisor モデルのレートで別課金され、コスト・レイテンシが増える（`effortLevel: xhigh` と方向性は同じだが二重に効く）。
- `tengu_sage_compass2` フラグや互換性チェックのバイパス挙動は、公式ドキュメントではなくインストール済みバイナリの文字列解析から得た非公式情報。claude-code の floor bump 時にはこの節も併せて再検証し、内部実装が変わっていないか確認すること。
- 2026-07-08、床上げ（2.1.200→2.1.204）に伴い 2.1.204 バイナリ（`.claude-wrapped`）を `strings` で再検証。kill switch（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL`）→ env var バイパス（`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL`）→ `tengu_sage_compass2` フラグ判定、advisorModel のランク互換性チェックという構造は変化なし。v2.1.204 の GitHub Release Notes にも記載なし（undocumented のまま）。
- 経緯・判断根拠は [ADR-0005](../docs/adr/0005-advisor-tool-default-enable.md) を参照。

関連: [architecture](../docs/architecture.md) / [skill-harness](skill-harness.md)
