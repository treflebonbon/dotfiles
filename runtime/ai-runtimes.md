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

- **Claude**: `private_dot_claude/settings.json.tmpl` → `~/.claude/settings.json`。`language: japanese`、`effortLevel: xhigh`、`teammateMode: auto`、`model: sonnet` + `advisorModel: opus`（experimental advisor tool、下記参照）、deny ルール群、`enabledPlugins`（LSP / codex / security-guidance / claude-code-setup）。既存 `PreToolUse` に加え、quiet な Impeccable Design Hook を user-global `PostToolUse` として持つ。個人・端末差分は `~/.claude/settings.local.json`（管理外）。
- **Codex**: `private_dot_config/codex/`（config.toml / rules / AGENTS.md / hooks.json / environments）を `run_onchange_after_codex-*.sh.tmpl` が `~/.config/codex/` 経由で `~/.codex/`（`$CODEX_HOME`）へマージ配置する。managed `hooks.json` は共有ハブの Impeccable runtime を quiet な `PostToolUse` で呼ぶ。宣言的設定のみ管理しローカル state は保全する。
- **AGENTS.md** — Codex / OpenCode / Zed / Cursor 向け指示（`~/AGENTS.md`、`private_dot_gemini/AGENTS.md` は Gemini 向け）。CLAUDE.md は Claude Code 向けに別管理。

MCP サーバーは `.mcp.json` / `private_dot_mcp.json` で設定（context7 / serena / effect-docs）。

## AI ツール更新の 2 経路

| 経路                | 対象                                       | 管理ファイル                                                            |
| ------------------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| nix devshell binary | claude-code / codex / copilot-cli / rtk 等 | `private_dot_config/nix-devshell/{flake.nix,modules/ai.nix,packages/*}` |
| APM skill / plugin  | 外部 skill / Claude marketplace plugin     | `apm.yml` / `apm.lock.yaml`                                             |

「AI ツールを更新したい」ときは両経路を確認する。

baseline は `modules/ai.nix` の `minClaudeCode` / `minCodex` assert で床固定する（現 `2.1.216` / `0.144.6`）。床の根拠はモデル品質・metadata の正確性（Sonnet 5 default / GPT-5.6 context window）＋ 多 agent ワークフロー・worktree 隔離の信頼性（error 伝搬・background daemon 安定化・worktree 隔離破れの修正）。

`llm-agents` flake input は 2026-07-06 に再度 `nix flake update` で最新化（claude-code 2.1.200 → 2.1.201 が追従、他の消費パッケージ [codex/copilot-cli/antigravity-cli/rtk/apm] は変化なし）。2.1.201 の変更点は「Sonnet 5 セッションで harness reminder の system role を廃止」のみで settings/workflow への影響なし、と確認した上でフロアは 2.1.200 のまま据え置いた。

2026-07-08、v2.1.204 の release note（`SessionStart` hook がヘッドレスセッションでイベントをストリーミングせず、リモートワーカーが hook 実行中に idle-reap してしまう不具合の修正）をきっかけに `nix flake update llm-agents` を実施し、claude-code 2.1.201 → 2.1.204 が追従（他の消費パッケージは変化なし）。今回は 2.1.201 のときと異なり、2.1.202-2.1.204 の変更点を確認した結果、この repo の床根拠（多 agent ワークフロー・worktree 隔離の信頼性）に直撃する修正が複数見つかったため、フロアを `2.1.200` → `2.1.204` へ引き上げた:

- worktree 隔離済み subagent が親 checkout でコマンドを実行してしまうバグ修正（2.1.203）— `to-worktree` が前提とする隔離保証そのものに関わる
- background daemon の auto-upgrade 失敗が実行中の全 background session を巻き添えに停止させるバグ修正（2.1.203）
- `claude agents` 復帰時に実行中の subagent を無言で停止し最初からやり直すバグ修正（2.1.203）
- 多数の git worktree を持つリポジトリでの `resuming a session` の遅延/メモリ肥大（2.1.202）、`Bash` の "argument list too long" 失敗（2.1.203）の修正 — `worktree-gc` が対象とする状況と重なる
- ヘッドレスセッションでの `SessionStart` hook イベントストリーミング不具合・idle-reap 誤爆の修正（2.1.204）

2026-07-10 JST、`nix flake update llm-agents` を実施し、`llm-agents.nix` は 2026-07-08 commit (`bd0f91f`) から 2026-07-09 commit (`89b3d6e`) へ進んだ。追従した CLI は `claude-code` 2.1.204 → 2.1.205 と `antigravity-cli` 1.0.16 → 1.1.0。`codex` 0.143.0 / `apm` 0.24.0 / `rtk` 0.43.0 は変化なし。v2.1.205 は release note 上、auto mode の session transcript 改ざん防止、background agent の状態表示・`claude attach`・session-to-PR linking、Windows worktree removal、file watcher crash の修正を含む。いずれも agent 実行の安全性・観測性・worktree 隔離の事故回避に関わるため、フロアを `2.1.204` → `2.1.205` へ引き上げた。Antigravity 1.1.0 については package metadata で version 追従を確認し、追加の dotfiles 設定変更は不要と判断した。

2026-07-10 JST、OpenAI Codex 0.144.0 の release note で GPT-5.6 系表示名更新を確認した。`nix flake update llm-agents` で `llm-agents.nix` を 2026-07-09 commit (`dc712c5`) まで進めても `codex` は 0.143.0 のままだったため、`private_dot_config/nix-devshell/modules/ai.nix` では upstream package definition を使いながら `version` / source `hash` / `cargoHash` だけを local override し、`minCodex = "0.144.0"` を追加した。Codex の管理 config は `model = "gpt-5.6-terra"` へ切り替えた。

2026-07-10 JST、`numtide/llm-agents.nix#6643` が merge され、`nix flake update llm-agents` で `llm-agents.nix` は 2026-07-09 commit (`89b3d6e`) から 2026-07-10 commit (`d17493b`) へ進んだ。package metadata は `claude-code` 2.1.206、`codex` 0.144.1、`copilot-cli` 1.0.70、`antigravity-cli` 1.1.0、`apm` 0.24.0、`rtk` 0.43.0。`codex` は flake pin では 0.143.0、local override では 0.144.0 だったが、0.144.1 は standalone install と code-mode host fallback の修正を含むため、`minCodex` を `0.144.1` へ引き上げ、local override を削除して flake pin のみに戻した。

2026-07-13 JST、両経路（nix devshell binary route と APM skill route）を確認した。APM route は `apm lock` を再実行しても `apm.lock.yaml` に差分なし（全 skill pin 据え置き）。nix devshell route は `nix flake update llm-agents` で `llm-agents.nix` が 2026-07-10 commit (`d17493b`) から 2026-07-13 commit (`3860609`) へ進み、`claude-code` 2.1.206 → 2.1.207、`codex` 0.144.1 → 0.144.3、`antigravity-cli` 1.1.0 → 1.1.1、`apm` 0.24.0 → 0.25.0 が追従（`copilot-cli` 1.0.70 / `rtk` 0.43.0 は変化なし）。

claude-code の release note（2.1.206–2.1.207）を確認した結果、この repo の床根拠（多 agent ワークフロー・worktree 隔離の信頼性）に関わる修正が複数見つかったため、`minClaudeCode` を `2.1.205` → `2.1.207` へ引き上げた:

- `EnterWorktree` が `.claude/worktrees/` 外への worktree 進入時に確認を挟むよう変更（2.1.206）
- background agent が Claude Code 更新直後にバックグラウンドで即時アップグレードされるよう変更、stale-session upgrade の遅延を解消（2.1.206）
- agent teams で不正な teammate mailbox メッセージが 1 秒おきの crash loop を起こすバグを修正（2.1.207）— この repo は `teammateMode: auto` を使うため直撃する
- background session が git worktree 内で resume した状態から cold reopen した際に空表示になるバグを修正（2.1.207）
- 最後の `worktree.sparsePaths` worktree 削除後も `extensions.worktreeConfig` が repo の `.git/config` に残留するバグを修正（2.1.207）— go-git 系ツールを壊す
- rules glob / skill path / `.ignore` / `.worktreeinclude` の不正な bracket pattern がファイル読み込み・worktree 作成を壊すバグを修正（2.1.207）

codex の release note（0.144.2–0.144.3）を確認した結果、0.144.0 で混入した auto-review（Guardian）prompting のリグレッションを 0.144.2 が revert して修正していることが分かった（0.144.1 はこのリグレッションを含んだまま）。0.144.3 は 0.144.2 からの変更なし（version-only リリース）。既知のリグレッションを含む版を床にしておく理由がないため、`minCodex` を `0.144.1` → `0.144.3` へ引き上げた。

`antigravity-cli` 1.1.0 → 1.1.1 と `apm` 0.24.0 → 0.25.0 は package metadata でのバージョン追従のみ確認し、追加の dotfiles 設定変更は不要と判断した（両者とも `ai.nix` の assert 対象外）。

2026-07-14 JST、Classmethod の Claude Code 2.1.208 紹介記事を更新トリガーとして、Anthropic 公式 release note と各 upstream の一次情報を確認してから `nix flake update llm-agents` を実施した。`llm-agents.nix` は 2026-07-13 commit (`3860609`) から 2026-07-14 commit (`5c73869`) へ進み、`claude-code` 2.1.207 → 2.1.208、`codex` 0.144.3 → 0.144.4、`antigravity-cli` 1.1.1 → 1.1.2 が追従した。`copilot-cli` 1.0.70 / `apm` 0.25.0 / `rtk` 0.43.0 は変化なし。

Claude Code 2.1.208 は、background agent への返信が配信失敗時に失われる問題、更新で binary が置換された後に background-session attach が恒久的に失敗する問題、旧 daemon が新しい worker を古い binary で再起動する問題を修正する。さらに agent view の worktree 削除が未 push commit を保護し、再利用した worktree 名の base を現在値へ戻すようになったほか、Remote Control の agent/workflow 可視化、長時間・多 MCP session のメモリ/CPU/転記量も改善された。この repo の多 agent・worktree 中心の運用に直接効くため、`minClaudeCode` を 2.1.207 → 2.1.208 へ引き上げた。

同 release で追加された `axScreenReader`、`vimInsertModeRemaps`、`CLAUDE_CODE_PROCESS_WRAPPER` はいずれも opt-in であり、現行要件では必要ないため `private_dot_claude/settings.json.tmpl` は変更しない。

Codex 0.144.4 は公式 release note が user-facing change なしと明記する patch release のため、flake pin には追従するが `minCodex` は 0.144.3 のまま据え置いた。`antigravity-cli` 1.1.2 は package metadata での追従のみ確認し、追加の dotfiles 設定変更は不要と判断した。

2026-07-17 JST、`nix flake update llm-agents` で `llm-agents.nix` を 2026-07-14 commit (`5c73869`) から 2026-07-16 commit (`b384352`) へ更新した。package metadata は `claude-code` 2.1.208 → 2.1.211、`codex` 0.144.4 → 0.144.5、`copilot-cli` 1.0.70 → 1.0.71、`antigravity-cli` 1.1.2 → 1.1.3 であり、`apm` 0.25.0 / `rtk` 0.43.0 は変化なし。

[Claude Code 2.1.210–2.1.211 の公式 changelog](https://raw.githubusercontent.com/anthropics/claude-code/v2.1.211/CHANGELOG.md)には、worktree 隔離された subagent が main checkout に git 操作できる不具合、auto mode が unsandboxed Bash の `PreToolUse` hook による `ask` 判断を上書きする不具合、background agent の結果報告・plugin MCP 再接続の不具合の修正が含まれる。多 agent・worktree 中心の運用に直接影響するため `minClaudeCode` を `2.1.208` → `2.1.211` へ引き上げた。

[Codex 0.144.5 の公式 release note](https://github.com/openai/codex/releases/tag/rust-v0.144.5)は、強制削除形式を含む危険コマンド検出と拒否理由を改善している。このリポジトリの安全なコマンド実行に直結するため `minCodex` を `0.144.3` → `0.144.5` へ引き上げた。Copilot CLI と Antigravity CLI は package metadata での追従のみ確認し、設定変更は不要と判断した。

なお、今回の更新は chezmoi source dir（`~/ghq/github.com/treflebonbon/dotfiles`）とは別の作業 worktree で行った。`ai.nix` の更新手順コメントが前提とする2経路（source dir で編集して `chezmoi apply` で `~/` へ反映する／デプロイ先 `~/.config/nix-devshell` を直接編集して `chezmoi re-add` で source へ戻す）のどちらでもなく、単に同じ repo の別 git worktree・branch で `nix flake update` を実行し `flake.lock` を編集してそのまま commit しただけである。source dir 側へは通常の merge/pull 経路で反映され、ライブ環境（`~/.config/nix-devshell`）へ反映したい場合はさらに `chezmoi apply` が必要になる。

2026-07-21 JST、共通 package set を Intel Darwin を最後に支える `nixpkgs-26.05-darwin` commit `fca2dbd4`、`llm-agents.nix` を4 platform の source map を保持する commit `533b02e5` へ更新した。package metadata と CLI 表示は `claude-code` 2.1.216、`codex` 0.144.6、`copilot-cli` 1.0.73、`antigravity-cli` 1.1.5、`apm` 0.26.0、`rtk` 0.43.0。Claude Code 2.1.212–2.1.216 は `.claude/worktrees` symlink、`git -C` / `GIT_DIR`、別 project の残存 worktree を介した隔離逸脱を修正したため `minClaudeCode` を 2.1.216 へ上げた。Codex 0.144.6 は GPT-5.6 Sol / Terra / Luna の bundled instructions と context window metadata を修正したため `minCodex` を 0.144.6 へ上げた。Copilot CLI 1.0.73 は追加 directory 設定時も Anthropic subagent が継続する修正を含む。Antigravity / APM / RTK は package metadata 追従のみで設定変更はない。

同じ更新で Playwright CLI 0.1.17、Waza 0.38.3、design.md 0.3.0、Defuddle 0.19.1 へ更新し、MarkItDown は最新の 0.1.6 を維持した。Waza 0.38.3 は release asset が生バイナリから tar/zip archive へ変わったため、4 platform の asset hash と unpack/install 手順を同期した。26.05 の Defuddle / MarkItDown は 0.18.1 / 0.1.4 のため、この2 package definition だけ commit `421eebfd` から26.05 package set上へ backport する。MarkItDown の依存する `arrow-cpp` は26.05で Intel Darwin broken のため、その sunset system に限り broken package の評価を許可する。4 system の flake 評価と現 host の devShell build、Nix store 上の各 CLI/version を隔離 workspace から確認し、ライブ環境への apply は行っていない。Intel Darwin の security support は 2026-12-31 までであり、この backport / overlay 経路も同日までに廃止判断する。

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
- **auto mode が session transcript file の改ざんをブロック**（2.1.205）— transcript 上の偽承認や履歴改ざんを前提にした権限逸脱を防ぐ方向の修正。
- **background agent の状態表示・attach・PR linking を修正**（2.1.205）— resumed agent が failed/completed のまま残る表示、mid-upgrade restart 中の `claude attach` error、30K inline limit を超える Bash output 内で作られた PR の session linking 漏れに対応。
- **Windows worktree removal / file watcher crash を修正**（2.1.205）— worktree 内の NTFS junction / directory symlink で worktree 外を削除する事故、directory scan 中に watcher が閉じた場合の crash を修正。
- **`EnterWorktree` が `.claude/worktrees/` 外への進入時に確認を挟むよう変更**（2.1.206）— `to-worktree` / Orca worktree 以外の場所へ誤って worktree を作る事故を防ぐ方向の変更。
- **background agent が Claude Code 更新直後にバックグラウンドで即時アップグレードされるよう変更**（2.1.206）— attach 時の stale-session upgrade 待ちを解消。
- **agent teams で不正な teammate mailbox メッセージによる crash loop を修正**（2.1.207）— 1 秒おきにエラーを繰り返しメールボックスファイルの手動削除が必要だった不具合。`teammateMode: auto` を使うこの repo に直撃する。
- **background session が git worktree 内で resume した状態から cold reopen した際に空表示になる不具合を修正**（2.1.207）。
- **最後の `worktree.sparsePaths` worktree 削除後も `extensions.worktreeConfig` が repo の `.git/config` に残留する不具合を修正**（2.1.207）— go-git 系ツール（`tea` 等）を壊す。
- **rules glob / skill path / `.ignore` / `.worktreeinclude` の不正な bracket pattern がファイル読み込み・ファイル候補提示・worktree 作成を壊す不具合を修正**（2.1.207）。
- **background agent への返信を配信失敗時に保存し、session restart 後に再送**（2.1.208）— agent への steer が無言で失われる問題を修正。
- **更新後の background-session attach と daemon の世代管理を修正**（2.1.208）— 実行中の `claude agents` が起動元 binary の置換後に attach 不能になる問題を直し、旧 daemon が新 worker を古い binary へ巻き戻さないようにした。
- **agent view の worktree 削除を安全化**（2.1.208）— rename 済み branch の worktree も削除でき、未 push commit は破壊せず、worktree を保持した session row も残す。再利用した worktree 名は現在の base へリセットされる。
- **Remote Control の background agent / workflow progress 可視化を修正**（2.1.208）— terminal-hosted session へ attach した client が task state の変化まで進捗を見られない問題を修正。
- **長時間・多 agent・多 MCP session の資源使用を抑制**（2.1.208）— MCP/LSP/hook/tool-result のメモリリーク、agent view の画像保持、tool-pool 再構築コスト、edit-heavy transcript/checkpoint 肥大を修正・削減。

### Advisor tool（experimental, 2.1.200 時点でも undocumented）

`settings.json.tmpl` の `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` + `advisorModel: "opus"` で、より高性能なモデル（advisor）が会話全体を読んで途中で助言する [Advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)（Anthropic API 側の beta 機能）を Claude Code 本体にも既定で有効化している。

- GitHub Release Notes（v2.1.200 時点）に記載が一切ない undocumented な機能。インストール済みバイナリの文字列解析で存在と挙動を確認: env var 未設定でも内部の段階的ロールアウトフラグ（`tengu_sage_compass2`）で一部セッションは既に有効化されうる。env var を明示すると (a) そのロールアウトフラグをバイパスして強制 ON、(b) `advisorModel` の互換性チェック（advisor はベースモデル以上の能力が必要、という catalog 上の rank 比較）も丸ごとスキップされる。
- 緊急停止用に `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` という kill switch も存在する。
- advisor 呼び出しは advisor モデルのレートで別課金され、コスト・レイテンシが増える（`effortLevel: xhigh` と方向性は同じだが二重に効く）。
- `tengu_sage_compass2` フラグや互換性チェックのバイパス挙動は、公式ドキュメントではなくインストール済みバイナリの文字列解析から得た非公式情報。claude-code の floor bump 時にはこの節も併せて再検証し、内部実装が変わっていないか確認すること。
- 2026-07-08、床上げ（2.1.200→2.1.204）に伴い 2.1.204 バイナリ（`.claude-wrapped`）を `strings` で再検証。kill switch（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL`）→ env var バイパス（`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL`）→ `tengu_sage_compass2` フラグ判定、advisorModel のランク互換性チェックという構造は変化なし。v2.1.204 の GitHub Release Notes にも記載なし（undocumented のまま）。
- 2026-07-13、床上げ（2.1.205→2.1.207）に伴い 2.1.207 バイナリを再検証しようとしたところ、Claude Code の auto mode 分類器が「バイナリの kill switch / bypass 挙動を探すリバースエンジニアリング」と判定し、周辺文脈を抽出する詳細解析コマンドをブロックした。ブロック前に取得できたのは4トークンの出現回数（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL` 3件、`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` 4件、`tengu_sage_compass2` 2件、`advisorModel` 18件、いずれも 0 ではない）のみで、これは各文字列が バイナリ内に存在することしか示さない。kill switch → env var バイパス → `tengu_sage_compass2` 判定 → advisorModel のランク互換性チェックという**構造・挙動そのものは 2.1.207 で未検証**（2.1.204 時点の構造と一致するとは断定できない）。次回の床上げ時に必要なら、ユーザー自身の手元での `strings` 実行に切り替えること。v2.1.205–2.1.207 の GitHub Release Notes にも advisor tool への言及はない（undocumented のまま）。
- 2026-07-14、床上げ（2.1.207→2.1.208）では公式 release note に advisor tool への言及がなく、前回と同じ理由で binary の詳細解析は行っていない。2.1.204 時点で確認した内部構造が 2.1.208 でも同じとは断定せず、設定変更もしない。
- 2026-07-10、床上げ（2.1.204→2.1.205）では release note 上 advisor tool への言及が無く、設定変更も行わない。
- 経緯・判断根拠は [ADR-0005](../docs/adr/0005-advisor-tool-default-enable.md) を参照。

関連: [architecture](../docs/architecture.md) / [skill-harness](skill-harness.md)
