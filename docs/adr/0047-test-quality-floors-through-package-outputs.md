---
type: decision
title: 品質 floor 判定を配備する package の出力で検証する
description: 承認済み floor の独立した期待値を保ち、判定と短い診断を ai.nix、採用経緯を ADR に集約する
tags: [adr, nix, quality-floor, testing]
timestamp: 2026-09-07
status: accepted
---

# 品質 floor 判定を配備する package の出力で検証する

Claude Code／Codex の品質 floor は、承認済み最低 release より古い版を配備しないための採否条件である。文字列を確認するテストでは、条件が宣言されていても実際の配備時に判定を迂回する変更を検出できない。[設計合意](../research/quality-floor-validation-design-2026-09-07.md)に従い、既存の ai.nix の引数へ version metadata を与え、`packages` 出力から採否と診断を検証する。

floor と短い採用理由、判定、診断は ai.nix 内で扱い、公開 interface を増やさない。[判定テスト](../../tests/ai-quality-floor.bats)は実装の floor から期待値を導出せず、承認済み値を独立して持つ。この意図的な重複により、floor 自体の引き下げも検出する。正当な床上げでは実装と期待値の両方を更新する。

採用理由の履歴は ADR を参照し、実行時の診断にはツール名、実際の版、必要な floor、現在の理由の要約、根拠への参照、修復手順だけを残す。version 欠損は「不明」と表示する。snapshot と floor の値、package の取得経路はこの決定で変更しない。判定テストは根拠機能の動作確認を代替せず、ツール更新時の [ADR-0045 の検証境界](0045-separate-llm-agents-and-apm-update-units.md#verification-boundary)を維持する。

## 既存コードから移した判断経緯

以下は `17440121a85c86272b0f61bcc98c2ff494d1af28` の `modules/ai.nix` にあった記録を整理したもの。今回 release の採否を再評価した記録ではない。現行値の判断は [ADR-0045 の2026-09-05更新](0045-separate-llm-agents-and-apm-update-units.md#llm-agents-snapshot2026-09-05claude-read-fence-と-codex-model-再評価)を参照する。

### Claude Code

- **2.1.197–2.1.200**: Sonnet 5 の default 化、subagent／teammate／workflow の rate-limit・API error 伝搬、background daemon の約50秒ごとの自死・stop 後 respawn・partial 応答破棄、sleep/resume／stale session のクラッシュと古い daemon による乗っ取り防止を根拠とした。2.1.200 の permission mode 変更（default → Manual）も運用上の留保として記録した。
- **2.1.201–2.1.202**: 2.1.201 の harness reminder の system role 廃止を単独の床上げ根拠にはしなかった。2.1.202–2.1.204 の修正は次項に含めて扱った。
- **2.1.203–2.1.204**: worktree 隔離 subagent が親 checkout で実行する問題、daemon の auto-upgrade 失敗による全 background session の停止、`claude agents` 復帰時の実行中 subagent の停止・やり直しを修正。headless SessionStart hook のイベント未送信による remote worker の idle-reap も修正した。
- **2.1.205–2.1.207**: auto mode の transcript 改ざん防止、background agent 状態表示／attach／PR linking、Windows worktree removal、file watcher crash を修正。EnterWorktree の既定外 path への確認、background agent の即時アップグレード、teammate mailbox crash loop、worktree 内 session の cold reopen 後の空表示、worktreeConfig 残留を扱った。
- **2.1.208**: background agent の返信再送、更新後 attach 復旧、daemon の世代逆行防止、worktree 削除安全化、Remote Control の agent／workflow 可視化、長時間 session の資源リークを修正した。
- **2.1.210–2.1.211**: worktree 隔離 subagent による main checkout の Git 変更、unsandboxed Bash で auto mode が PreToolUse の ask を上書きする問題、background agent／plugin MCP 再接続を修正した。
- **2.1.212–2.1.216**: `.claude/worktrees` の symlink による隔離逸脱、`git -C`／`GIT_DIR` での共有 checkout 操作、別 project の残存 worktree への誤進入を修正した。
- **2.1.217–2.1.222**: symlink 済み working directory の正規化、Opus 5 の採用、zsh regex 内コマンドの permission bypass、background session の Git 指示遵守、隔離 session の destructive Git と PreToolUse restriction 迂回を扱った。[ADR-0028](0028-claude-code-darwin-x64-local-override.md)、[ADR-0033](0033-update-llm-agents-snapshot-and-claude-baseline.md)、[ADR-0034](0034-update-ai-toolset-safety-baselines.md)を参照。2.1.220 は具体的な床上げ根拠を確認できず pin の追従のみとした。
- **2.1.223–2.1.228**: 不可視文字、動的 import、org policy、deny path の末尾スラッシュによる permission／sandbox 迂回、sandbox 診断欠落、auto mode の refusal 誤加算を根拠に採用した。2.1.226 の一般的な修正説明、2.1.227 の menu 更新、2.1.228 の claude.ai 同期 skill hardening は、この repo の APM／chezmoi／Nix 配備で独立した床上げ根拠にしなかった。[ADR-0035](0035-update-llm-agents-snapshot-and-trust-boundary-baseline.md)を参照。
- **2.1.229–2.1.237**: 危険 flag の auto-approval、PowerShell／Git Bash symlink、nested repository trust、cross-session `/tmp`、Linux protected-path、GitLab token、sandbox.ripgrep override、skill argument 再展開、NT namespace validation、Linux idle CPU、remote file／session restore、background permission、MCP secret redaction、macOS deny precedence、session messaging を扱った。subagent の background／fork 既定化と、後続版での permission 変更の revert も含む。[ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md)、[ADR-0037](0037-update-llm-agents-and-compatible-skill-pins.md)、[ADR-0039](0039-update-llm-agents-and-selected-skill-payloads.md)を参照。
- **2.1.238–2.1.239**: headers helper の consent／trust、継承 credential 分離、MCP 初期化、memory／session／Remote Control、worktreeConfig がある repo の Linux sandbox 誤判定、working directory 削除後の hook ENOENT、ListAgents／SendMessage の自己名解決・live teammate 一覧を根拠とした。[ADR-0040](0040-update-llm-agents-and-remotion-update-unit.md)と [ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md)を参照。
- **2.1.243–2.1.247**: rootless／user namespace の cross-session messaging、background subagent wake、hook command 条件の誤発火、人手作成 worktree の retention、malformed shell command の approval、third-party gateway credential の telemetry 境界を修正。chezmoi／Nix settings symlink、subagent fallback、hook output overflow、`--agent` session の compact system prompt も含めて [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)の床へ進めた。
- **2.1.251–2.1.257**: file tool の symlink swap、plugin path traversal、Grep／Glob deny、background worktree lock、managed settings の sandbox 弱化、移動・link 済み task output、always-allow 保存を修正。2.1.257 は Containment Escape rule、working directory 外の read fence、compound command／subshell の ask、redirect／reader command の deny、plugin component symlink traversal、subdirectory 移動後の sandboxed Git、worktree 内 Bash の false-positive、teammate mailbox の二重応答、daemon の起動待機・stop／detach／旧世代 session の残存を扱った。記録当時 2.1.253–2.1.256 は公式 CHANGELOG に存在しなかった。[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)を参照。
- **2.1.260–2.1.261**: read fence が macOS user git config と worktree-isolated subagent 自身の checkout を隠す問題、background resume の tight loop、teammate の tool／skill announcement 再送、危険な削除コマンドの検出を根拠とした。詳細は [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)と、そこから参照する実動作調査に記録する。

### Codex

- **0.144.0–0.144.6**: GPT-5.6 対応、standalone installer／code-mode reliability、Guardian prompting regression の revert、危険な強制削除コマンドの検出・拒否理由、Sol／Terra／Luna の bundled instructions と context window metadata を根拠とした。0.144.4 は単独の床上げ根拠にしなかった。
- **0.146.0–0.147.0**: executor が提供する skill の discover／read、context pressure 下の skill catalog 保持、MCP refresh／reconnect、cyber-capable model の auto-review 既定値、local project trust、managed authentication、plugin isolation、secret／bearer redaction を扱った。[ADR-0033](0033-update-llm-agents-snapshot-and-claude-baseline.md)、[ADR-0034](0034-update-ai-toolset-safety-baselines.md)、[ADR-0035](0035-update-llm-agents-snapshot-and-trust-boundary-baseline.md)を参照。
- **0.148.0–0.149.0**: denied／unreadable path の fail-closed、OAuth 再認証後の MCP recovery、plugin／skill root、resume／fork の working directory と permission profile 復元、agents dashboard／cwd／queue、catalog、MCP hooks／async message、skill／OAuth／sandbox hardening を扱った。[ADR-0039](0039-update-llm-agents-and-selected-skill-payloads.md)、[ADR-0040](0040-update-llm-agents-and-remotion-update-unit.md)、[ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md)を参照。
- **0.150.0–0.152.0**: untrusted project の AGENTS.md、managed deny-read、credential redaction、remote MCP auth／startup、Unix shutdown、permission profile 復元、`/cd` 後の sandbox、remote executor の HOME／OS／path、stale Guardian approval、MCP cache／error、cloud task の信頼できない URL・redirect 拒否、refreshed auth header を扱った。`tools.update_plan.enabled` の既定変更は元から未設定のため追加設定なしとした。[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)を参照。
- **0.153.1–0.153.4**: Astra の明示設定、Fast tier 表示、bundled picker／default を根拠とした。account catalog と実リクエストでの確認、0.153.0 の experimental context management を opt-in しない判断は [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)に記録する。
