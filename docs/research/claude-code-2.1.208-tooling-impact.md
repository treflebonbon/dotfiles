---
type: research
title: Claude Code 2.1.208 — llm-agents.nix 更新と多 agent / tool 運用への影響
description: Claude Code 2.1.208 の変更を Anthropic 公式 changelog・ドキュメントと numtide/llm-agents.nix の一次情報で検証し、この dotfiles に必要な更新を整理した調査ノート。
tags: [research, claude-code, llm-agents, agents, mcp, worktree]
timestamp: 2026-07-14
---

# Claude Code 2.1.208 — llm-agents.nix 更新と多 agent / tool 運用への影響

## 結論

Claude Code 2.1.208 は新しい設定を必須にするリリースではないが、この repo が重視する **background agent、agent view、worktree 隔離、長時間セッション、MCP 多用時の信頼性**に直接関係する修正をまとめて含む。そのため `minClaudeCode` を `2.1.207` から `2.1.208` へ引き上げる根拠は十分にある。

Anthropic は v2.1.208 を 2026-07-14 01:10 UTC に公開した。以下はユーザー提示の [DevelopersIO 記事](https://dev.classmethod.jp/en/articles/20260714-cc-updates-v2-1-208/)を論点抽出にだけ用い、各事実を Anthropic または `numtide/llm-agents.nix` の一次情報に遡って検証した結果である。公式 changelog は [v2.1.208 tag の固定版](https://github.com/anthropics/claude-code/blob/v2.1.208/CHANGELOG.md#21208)、公開日時と配布物は [公式 GitHub Release](https://github.com/anthropics/claude-code/releases/tag/v2.1.208) を参照した。

## 多 agent / worktree 運用への重要変更

### 信頼性と観測性

公式 changelog で確認できる重要修正は次のとおりである。

- background agent への返信が delivery failure 時に失われず、保存されてセッション再起動後に配送される。
- CLI 更新で実行中バイナリが置き換わった後、`claude agents` から起動された background daemon へ attach できなくなる永続的失敗を修正。
- supervised/background session の HTTP/2 `GOAWAY` による crash を修正。
- Remote Control client が background agents と workflow progress を task の開始・停止まで見られなかった問題を修正。
- SDK initialize request で定義した agents が、client attach 前の plugin refresh により失われる問題を修正。
- subagent の `tools` 指定が未認識名だけで空になった場合、tool なしで起動せず、問題の entry を明示する error を返す。
- 完了した background agent が即座に消えず、cleanup まで `/tasks` に残る。停止済み agent への attach では warm-up 中も transcript を直ちに表示する。
- agent view の Ctrl+X は renamed-branch worktree を削除できる一方、unpushed commit を破棄せず、worktree を保持した場合は session row も保持する。再利用した worktree 名は現在の base へ reset される。
- 古い background daemon が新しい version で spawn された worker を古い binary へ巻き戻す挙動を防止。

これらはすべて [公式 v2.1.208 changelog](https://github.com/anthropics/claude-code/blob/v2.1.208/CHANGELOG.md#21208) に記載されている。公式の agent 機能整理でも、`claude agents` は background sessions の agent view、`/tasks` は current session の background work を一覧・attach・stop する入口、worktree は並列 session のファイル隔離手段と位置づけられているため、上記修正はこの repo の運用経路にそのまま当たる（[Run agents in parallel](https://code.claude.com/docs/en/agents)）。

### 長時間セッションと tool 実行性能

同じ公式 changelog は次を報告している。

- edit-heavy session の transcript を最大 79 倍縮小し、上書き済み file-history backup を prune して checkpoint の disk 使用量を bounded にした。
- background agents または大きな会話から fork した session の resume memory を削減。
- headless/SDK session で大きな tool-result payload が引き起こす unbounded memory growth を修正。
- MCP stdio server の stderr は server ごとに最大 64 MB、LSP open document は LRU 50 件へ bounded 化し、background 化後に async hook output を保持する leak も修正。
- print/SDK session で MCP tool が多い場合、tool-pool assembly を cache し、tool 数が多い条件では tool round を最大 7 倍高速化。
- file edit read cache を最大 1,000 full files の pin から 16 MB 上限へ変更。
- permission deny/ask rule が多い session の matcher を一度だけ compile/cache し、turn ごとの数秒規模の遅延を修正。

この repo は MCP、hooks、複数 agent、長時間の Builder-Evaluator loop を併用するため、単なる UI 改善ではなく resource exhaustion と反復 tool-call latency の低減として効く。Claude Code 公式も MCP を外部 tool の接続手段、subagent を独立 context の worker と説明している（[Tools reference](https://code.claude.com/docs/en/tools-reference)、[Create custom subagents](https://code.claude.com/docs/en/sub-agents)）。

### permission の circuit breaker 強化

command substitution（`$(...)`、backtick、`<(...)`）を含む command 内の `rm -rf ~` 等も、plain form と同様に `--dangerously-skip-permissions` と auto mode で確認対象になった（[公式 v2.1.208 changelog](https://github.com/anthropics/claude-code/blob/v2.1.208/CHANGELOG.md#21208)）。公式 permission docs は以前から root/home removal を bypass mode でも残る circuit breaker と定義しており、v2.1.208 はその検出を command substitution 内まで揃えた修正と解釈できる（[Choose a permission mode](https://code.claude.com/docs/en/permission-modes)）。

これは安全性の改善だが、`bypassPermissions` 自体を安全にするものではない。公式は引き続き、internet access のない container / VM / dev container 等の隔離環境だけで使うよう警告している。

## 新機能と設定影響

公式 changelog 上の追加機能は次の4点である。

1. screen reader 向け plain-text rendering（`claude --ax-screen-reader`、`CLAUDE_AX_SCREEN_READER=1`、または `"axScreenReader": true`）。
2. vim insert mode の2キー remap 用 `vimInsertModeRemaps` setting。
3. Claude Code 自身が spawn する agent view/background service process を企業 launcher 経由にする `CLAUDE_CODE_PROCESS_WRAPPER`。
4. fullscreen mode の multi-select menu と `Other` input row の mouse click 対応。

いずれも opt-in または UI 操作改善であり、現行 `private_dot_claude/settings.json.tmpl` に必須追加はない。`CLAUDE_CODE_PROCESS_WRAPPER` は corporate launcher が要求される環境向けであり、`llm-agents.nix` が package 自体に施す Nix wrapper の代替として設定する根拠はない。screen reader または vim `jj`/`jk` remap を利用したいという個別要件が生じた場合だけ設定すればよい。

## llm-agents.nix の追従状況

この repo の `private_dot_config/nix-devshell/flake.lock` は調査開始時点で `numtide/llm-agents.nix` commit [`38606092`](https://github.com/numtide/llm-agents.nix/commit/3860609253abda8ef63068b45064be31b50d1ab1) を pin し、その Claude Code package は 2.1.207 である。

upstream は commit [`d052868b`](https://github.com/numtide/llm-agents.nix/commit/d052868bf087fa11ff76f498406859a4da3ec776) で `claude-code` を 2.1.207 から 2.1.208 へ更新済みであり、package の version/hash は [`packages/claude-code/hashes.json`](https://github.com/numtide/llm-agents.nix/blob/d052868bf087fa11ff76f498406859a4da3ec776/packages/claude-code/hashes.json) に固定されている。したがって local override は不要で、通常の `nix flake update llm-agents` で追従できる。

実装では `nix flake update llm-agents` により pin を `3860609` から [`5c73869`](https://github.com/numtide/llm-agents.nix/commit/5c73869318afcf796a7a465b4b5e31b27f0819d4) へ更新した。更新前後の flake package metadata を `nix eval` で比較した確定値は次のとおり。

| package         | 更新前 pin | 更新後 pin | 判断                                                                               |
| --------------- | ---------: | ---------: | ---------------------------------------------------------------------------------- |
| claude-code     |    2.1.207 |    2.1.208 | 今回の主対象。`minClaudeCode` も 2.1.208 へ引き上げ                                |
| codex           |    0.144.3 |    0.144.4 | 公式 release が user-facing change なしと明記するため `minCodex` は 0.144.3 のまま |
| antigravity-cli |      1.1.1 |      1.1.2 | package metadata の追従を確認。追加設定なし                                        |
| copilot-cli     |     1.0.70 |     1.0.70 | 変更なし                                                                           |
| apm             |     0.25.0 |     0.25.0 | 変更なし                                                                           |
| rtk             |     0.43.0 |     0.43.0 | 変更なし                                                                           |

Codex 0.144.4 の判断根拠は OpenAI 公式 [0.144.4 release](https://github.com/openai/codex/releases/tag/rust-v0.144.4) の「No user-facing changes in this patch release」である。全 package の version assert を含む devShell は `nix flake check --no-build`、リポジトリ全体は 173 件の Bats tests で検証済み。

## この dotfiles で更新が必要な箇所

最小変更は次の3箇所である。

1. `private_dot_config/nix-devshell/flake.lock`: `llm-agents` input を v2.1.208 を含む upstream commit へ更新する。
2. `private_dot_config/nix-devshell/modules/ai.nix`: `minClaudeCode = "2.1.208"` へ引き上げ、assert message と根拠コメントに background agent / worktree / memory fixes を追記する。
3. `runtime/ai-runtimes.md`: pin の commit、実際に追従した全 tool version、v2.1.208 を床にする理由、settings 変更不要の判断を記録する。

`private_dot_claude/settings.json.tmpl` は変更不要。既存文書の方針どおり、Claude Code floor bump 時には undocumented な advisor tool の存在・挙動を 2.1.208 binary で再検証できるなら行い、検証不能ならその旨を明記する。

## 検証上の注意

- DevelopersIO 記事は「45 changes」「4 new features」「30件超の bug fixes」と集計しているが、公式 changelog 自体は category/count を明示していない。本ノートでは件数を設計判断の根拠にせず、公式 changelog の個別項目だけを採用した。
- 記事は release を July 13 と表現する一方、GitHub Release API の公開時刻は 2026-07-14 01:10:42 UTC（JST 10:10）である。時差による日付表現とみられるため、本ノートは公式 timestamp を採用した。
- 「最大79倍」「最大7倍」は Anthropic が changelog で示した上限値であり、この repo での実測値ではない。
