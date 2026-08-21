---
type: research
title: llm-agents.nix と APM 管理 skill の更新差分（2026-08-21）
description: 2026-08-20 メモ以降に確認できる LLM エージェント、llm-agents.nix、APM 管理 skill/tool の公式リリース・タグ・コミット・ドキュメント差分を一次情報だけで整理した調査ノート。
tags: [research, llm-agents, apm, skills, claude-code, codex, remotion]
timestamp: 2026-08-21
---

# llm-agents.nix と APM 管理 skill の更新差分（2026-08-21）

このノートの `timestamp` と日付だけの履歴表記は JST（Asia/Tokyo）を基準とする。

## 結論

調査基準時刻は **2026-08-21 08:50 JST / 2026-08-20 23:50 UTC**。比較基準は前回メモの **2026-08-20 17:00 JST / 08:00 UTC 前後**とし、固定済みの source / lock は変更していない。

前回以降、`numtide/llm-agents.nix` の公式 main は [`d205793b`](https://github.com/numtide/llm-agents.nix/commit/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da)（2026-08-20 22:10:24 UTC）まで進み、当 repo が直接消費する package のうち次が進んだ。

| package         | 現行 source / 前回確認値 | 今回確認した公式候補                                                                                                                                                                                                                                                                                                                                      | 判断                                                                                                                                                                                      |
| --------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| claude-code     | `2.1.237`                | **`2.1.238`**（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/claude-code/hashes.json)、[`llm-agents commit`](https://github.com/numtide/llm-agents.nix/commit/4cecdce80551970f6d2349f31264057fe1568ea6)）                                                                    | 更新候補。worktree isolation、MCP、cross-session messaging、長時間 session のメモリ、plugin marketplace の trust / credential 境界に差分がある。実装 round で floor と smoke を更新する。 |
| codex           | `0.148.0`                | **`0.149.0`**（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/codex/hashes.json)、[`release`](https://github.com/openai/codex/releases/tag/rust-v0.149.0)、[`llm-agents commit`](https://github.com/numtide/llm-agents.nix/commit/1fb8c8cdf4f0aad45cf9d03c4d8249c42b6a9a46)） | 更新候補。agents dashboard、作業ディレクトリ操作、queue、resume 時の permission profile 復元、TUI / sandbox / MCP の修正を含む。                                                          |
| antigravity-cli | `1.1.16`                 | **`1.1.17`**（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/antigravity-cli/hashes.json)、[`llm-agents commit`](https://github.com/numtide/llm-agents.nix/commit/c4a474abd89924ff4c5f3a51007b8a7838067f23)）                                                                 | package metadata の追従候補。version 固有の upstream changelog / release tag は **未確認**。                                                                                              |
| copilot-cli     | `1.0.80`                 | `1.0.80`（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/copilot-cli/hashes.json)）                                                                                                                                                                                           | 変更なし。                                                                                                                                                                                |
| rtk             | `0.45.0`                 | `0.45.0`（[`package.nix`](https://github.com/numtide/llm-agents.nix/blob/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/rtk/package.nix)）                                                                                                                                                                                                             | 変更なし。                                                                                                                                                                                |
| apm             | `0.28.0`                 | `0.28.0`（[`package.nix`](https://github.com/numtide/llm-agents.nix/blob/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da/packages/apm/package.nix)）                                                                                                                                                                                                             | 変更なし。APM の公式最新 release も [`v0.28.0`](https://github.com/microsoft/apm/releases/tag/v0.28.0) のまま。                                                                           |

APM 管理 skill は、今回の確認範囲では Remotion の selected payload だけに明確な更新候補がある。

- Remotion は現行 lock `21320596` から main [`7fc6dea3`](https://github.com/remotion-dev/skills/commit/7fc6dea333869e23f58bf9e9861010e9ba589e5e)（version `4.0.514`）へ進んだ。`<HtmlInCanvas>` の nested 利用方針が「Chrome 152 以降では可」から「nesting しない（Remotion が拒否）」へ変わったため、単なる version 表示の更新ではない。selected subtree の materialization と browser / skill test を通してから lock に採用する。
- Matt Pocock は main [`0ab1b63a4`](https://github.com/mattpocock/skills/commit/0ab1b63a410a03d3627979a109c8695de27af954) で、`grilling` の同一 round 内の質問を水平線で区切る変更を追加した。これは小さいが、`writing-great-skills` が消えて `writing-for-agents` へ移動したこと、phase boundary / `grilling` / `prototype` の workflow 変更と同じ migration 系列にあるため、現行 20 dependency の pin bump には混ぜない。
- Shadcn は main の registry 追加 commit があるが、lock の `skills/shadcn` selected subtree の差分は確認できなかった。Orca も main は進んでいるが、現行 lock の `orca-cli` `5ca747da`、`orchestration` / `computer-use` `cb42b608` に対応する selected path の差分は確認できなかった。
- `pbakaus/impeccable`、`anthropics/skills`、`GoogleChrome/modern-web-guidance`、`vercel-labs/agent-skills`、`vercel-labs/skills`、`supabase/agent-skills`、`Effect-TS/skills`、`mizchi/skills` は、比較範囲に新しい commit は確認できなかった。確認できない version / payload 差分を推測していない。

**採用候補:** 次の実装 round では `llm-agents.nix@d205793b`、Claude floor `2.1.238`、Codex floor `0.149.0`、Antigravity package metadata `1.1.17` を一組として評価し、Remotion `7fc6dea3` は selected payload 単独で検証する。Matt Pocock は別 workflow migration として保留する。

## 調査範囲と方法

repo の次の source / lock を対象にした。

- CLI: `private_dot_config/nix-devshell/flake.nix`、`private_dot_config/nix-devshell/flake.lock`、`private_dot_config/nix-devshell/modules/ai.nix`
- APM manifest / lock: `apm.yml`、`apm.lock.yaml`
- 背景と前回との差分: `runtime/ai-runtimes.md`、`docs/research/llm-agents-and-apm-update-2026-08-20.md`

外部情報は、各 upstream の GitHub REST API、immutable commit、公式 release page、公式 changelog、raw source のみを確認した。検索結果の二次記事、SNS、転載 changelog は根拠にしていない。

research skill が要求する補助 background agent については、`codex exec --sandbox read-only --ephemeral` の起動を試みたが、managed session の read-only filesystem により app-server 初期化で失敗した。補助役の結果は本ノートの根拠に使わず、上記の一次情報をこの調査側で直接照合した。

## llm-agents.nix と CLI の一次情報

### Snapshot と package metadata

前回 source の snapshot は `20766586959e0dcc2f9e7cff6d49b0c710de30d6`。[`公式 compare`](https://github.com/numtide/llm-agents.nix/compare/20766586959e0dcc2f9e7cff6d49b0c710de30d6...d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da) で今回の package 差分は Claude Code、Codex、Antigravity CLI の3つだけだった。

- [`claude-code: 2.1.237 -> 2.1.238`](https://github.com/numtide/llm-agents.nix/commit/4cecdce80551970f6d2349f31264057fe1568ea6) は version と各 platform hash を更新。
- [`antigravity-cli: 1.1.16 -> 1.1.17`](https://github.com/numtide/llm-agents.nix/commit/c4a474abd89924ff4c5f3a51007b8a7838067f23) は version、Google Cloud Storage artifact URL、sha512 を更新。
- [`codex: 0.148.0 -> 0.149.0`](https://github.com/numtide/llm-agents.nix/commit/1fb8c8cdf4f0aad45cf9d03c4d8249c42b6a9a46) は version、source hash、cargo hash を更新し、`librusty_v8` は `150.4.0` のまま。

この snapshot には `orca` や `workmux` など当 repo が直接配備しない package の更新もあるが、`modules/ai.nix` の直接消費 package ではないため今回の採用候補に含めない。

### Claude Code 2.1.238

公式 [`v2.1.238 release`](https://github.com/anthropics/claude-code/releases/tag/v2.1.238) は 2026-08-20 UTC に公開された。repo の運用に関係する変更は次のとおり。

- worktree-isolation Bash refusal の誤案内、stdio MCP の `initialize` 前 `server/discover`、MCP elicitation / permission prompt、長時間 session の subagent tool-result メモリ保持を修正。
- cross-session messaging が拒否・queue full を成功と誤報せず、sender に `refused` / drop を伝えるよう修正。`ListAgents` / `SendMessage` の Remote Control 到達性も修正。
- plugin marketplace / `.mcp.json` の `headersHelper` に対し、install / update 前の表示と確認、project trust、credential environment の継承範囲を明確化。
- self-hosted runner の graceful shutdown / proxy authorization options、`keybindingFlavor`、起動時 update check の遅延を追加。

いずれもこの repo の多 agent、worktree 隔離、MCP / skill 配備、Bash login-shell 運用に関係する。ただし provider を伴う background session、Remote Control、plugin marketplace の live 経路は未検証であり、floor の採用は実装時の smoke 後とする。

### Codex 0.149.0

公式 [`rust-v0.149.0 release`](https://github.com/openai/codex/releases/tag/rust-v0.149.0) は 2026-08-20 UTC に公開された。今回の floor 候補に直結する変更は次のとおり。

- TUI に interactive `codex agents` dashboard、`/cd` / `/pwd` / `/cwd`、既存 session へ送る `codex queue` を追加。
- queued message の idle wake、sub-agent activity / approval routing、resume / fork 時の active permission profile 復元を修正。
- `codex doctor` の endpoint protection / network / proxy / desktop / update 診断を拡張し、secure devcontainer の DNS exfiltration risk を公式 documentation に追加。
- MCP policy、OAuth resource header、Windows sandbox、Guardian risk scoring、plugin / skill selection、TUI replay buffer などを harden。

現行 `0.148.0` の floor 根拠（sandbox fail-closed、MCP OAuth recovery、skill/plugin root loading、resume policy）を包含する候補だが、0.149.0 の TUI / multi-agent / sandbox 境界は x86_64-linux smoke と3 system Nix evaluationで再確認する。

### Antigravity CLI 1.1.17

`llm-agents.nix` の公式 package metadata と更新 commit から version `1.1.17`、build ID `5084709148033024`、Linux / Darwin artifact URL と hash は確認できた。更新 commit が指す公式入口は [`antigravity.google/cli`](https://antigravity.google/cli)。一方、1.1.17 固有の公式 release note / tag / changelog はこの調査範囲では **未確認**。package metadata 追従以上の意味を推測しない。

## APM skill / tool の一次情報

### Remotion 4.0.514

公式 [`remotion-dev/skills@7fc6dea3`](https://github.com/remotion-dev/skills/commit/7fc6dea333869e23f58bf9e9861010e9ba589e5e) は package と selected skill の version を `4.0.513` から `4.0.514` へ更新した。selected `remotion-markup` の `html-in-canvas` guidance も変わった。

- 現行: Chrome 152.0.7944.0 以降は nested `<HtmlInCanvas>` を許容し、古い Chrome では単一要素だけを推奨。
- 候補: nested `<HtmlInCanvas>` を使わない。Remotion が nesting を reject し、Chrome が nested subtree を安定描画しないため。

この repo の `apm.yml` は Remotion を `#21320596...` に固定している。candidate は明確な behavior guidance 変更を含むため、lock の `resolved_commit` と deployed content hash を更新する場合は、APM materialization、selected file list、Remotion skill の discovery、既存の frontend verification を一つの gate とする。

### Matt Pocock skills

公式 main の現時点の immutable commit は [`0ab1b63a4`](https://github.com/mattpocock/skills/commit/0ab1b63a410a03d3627979a109c8695de27af954)。前回メモで保留した workflow migration に加え、2026-08-20 10:32:07 UTC の [`85f83d3f`](https://github.com/mattpocock/skills/commit/85f83d3fde1d3a90d5c9a657f6998c79a6c37308) と merge commit `0ab1b63a4` が `grilling` の round template を更新した。

- 同一 round 内の Q1 / Q2 を水平線 `---` で区切る形式になった。
- 前提の frontier interview、複数質問を一 round で聞く契約自体は維持されている。
- `writing-great-skills` は upstream の現行 tree では削除され、[`writing-for-agents`](https://github.com/mattpocock/skills/tree/0ab1b63a410a03d3627979a109c8695de27af954/skills/productivity/writing-for-agents) に移動済み。既存 `apm.yml` の path と lock を単独 pin bump では維持できない。

したがって現行 `ed37663c` の20 dependencyは据え置く。採用するには manifest path、lock、deploy 後の discovery、local `ui-grill-with-docs` の one-question-at-a-time override、phase boundary、prototype HTML、未導入 skill の router を別 migration として設計する。

### その他の selected skill

今回の upstream main / selected subtree 比較結果は次のとおり。

| upstream                           | 現行 lock / 対象                                                      | 2026-08-20 メモ以降の公式確認                                                                                                                                                                                                                                                                                                                                                                                                                                                 | 判断       |
| ---------------------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `pbakaus/impeccable`               | `5a149f3f` / `.agents/skills/impeccable`                              | [公式 commit history](https://github.com/pbakaus/impeccable/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                              | 据え置き。 |
| `anthropics/skills`                | `f6656c12` / `pdf`, `skill-creator`                                   | [公式 commit history](https://github.com/anthropics/skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                               | 据え置き。 |
| `GoogleChrome/modern-web-guidance` | `460e5536`                                                            | [公式 commit history](https://github.com/GoogleChrome/modern-web-guidance/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                | 据え置き。 |
| `shadcn-ui/ui`                     | `d4fc45b1` / `skills/shadcn`                                          | main は registry commit を含むが、[`公式 compare`](https://github.com/shadcn-ui/ui/compare/d4fc45b1fbabfccb7a6a4333d8004cf19481caa9...4e88ab81ae1d1550165db949a903c691a04f699c) で selected skill path の差分なし                                                                                                                                                                                                                                                             | 据え置き。 |
| `stablyai/orca`                    | `5ca747da` / `orca-cli`; `cb42b608` / `orchestration`, `computer-use` | main は [`012e9f41`](https://github.com/stablyai/orca/commit/012e9f410c7610c8d2b136a5c60e809f5e8214bf) まで進んだが、[`orca-cli compare`](https://github.com/stablyai/orca/compare/5ca747dad0d0583f4a1ac91c2655b345ba6c07eb...012e9f410c7610c8d2b136a5c60e809f5e8214bf) と [`orchestration / computer-use compare`](https://github.com/stablyai/orca/compare/cb42b60849d81ff58976200baa6b89dc5df99fb7...012e9f410c7610c8d2b136a5c60e809f5e8214bf) で selected path の差分なし | 据え置き。 |
| `vercel-labs/skills`               | `c6f69c63` / `find-skills`                                            | [公式 commit history](https://github.com/vercel-labs/skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                              | 据え置き。 |
| `supabase/agent-skills`            | `8331f910` / Postgres skill                                           | [公式 commit history](https://github.com/supabase/agent-skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                           | 据え置き。 |
| `Effect-TS/skills`                 | `28822c9e` / `effect-ts`                                              | [公式 commit history](https://github.com/Effect-TS/skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                                | 据え置き。 |
| `vercel-labs/agent-skills`         | `b8caa260` / React / Vercel 4 skill                                   | [公式 commit history](https://github.com/vercel-labs/agent-skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                        | 据え置き。 |
| `mizchi/skills`                    | `7a0d7286` / `empirical-prompt-tuning`                                | [公式 commit history](https://github.com/mizchi/skills/commits/main) で期間内の commit なし                                                                                                                                                                                                                                                                                                                                                                                   | 据え置き。 |

### APM CLI 0.28.0

公式 [`v0.28.0 release`](https://github.com/microsoft/apm/releases/tag/v0.28.0) が引き続き最新の release tag。公式 main の最新確認値は [`8993dcc6`](https://github.com/microsoft/apm/commit/8993dcc6fd7171ef3881a9021a7f25b9439e1a29)（2026-08-16 08:44:43 UTC）で、前回メモ以降の新規 commit / release tag は **未確認**。`apm` binary を main commit へ置き換える根拠はない。

## 採用 round の verification record（2026-08-21）

候補を source に採用する前に、既存 `.env*` の権限制限を避けた clean temporary source で Nix の深い評価を実行した。`nix flake check --no-build --all-systems` は `x86_64-linux`、`aarch64-linux`、`aarch64-darwin` の devShell / formatter 全出力で成功した。候補 package metadata も Nix evaluation で Claude `2.1.238`、Codex `0.149.0`、Antigravity `1.1.17` と一致した。構築済み Claude は `--version`、Antigravity は `--version` / `--help` の smoke を通過した。

APM は `/tmp` の isolated runtime layout で `apm install --frozen --https --no-audit` を実行し、lock SHA-256 は実行前後で `0515ee2e20b9ab0242789f8e1b4e2f446105cc7ca4781ff0b3be3f006d9ef834` と一致した。同じ cwd の `apm audit --ci` は10 checksを通過し、Remotion の `.agents/skills/remotion-best-practices` は137 filesとして materialize / discoveryできた。repo の targeted APM runtime tests（10 tests）と accepted update contract test も成功した。

Codex `0.149.0` の Linux binary build は、Nix daemon の cache SQLite write restriction により無出力のまま継続したため中断した。Nix source evaluation と package metadata は確認済みだが、Codex binary の実行 smoke と aarch64-darwin 実機実行は未確認として残す。source boundary を指定した `chezmoi apply --dry-run` は exit 0 で完了したが、管理対象 home を変更する実 apply と live home discovery はこの managed session では実行していない。

## 未確認事項と検証境界

- Antigravity CLI 1.1.17 の version 固有 changelog / upstream release tag は **未確認**。`llm-agents.nix` の metadata 以上の変更内容は記録していない。
- Codex 0.149.0 の candidate binary smoke と aarch64-darwin 実機実行は未実施。3 system の Nix deep evaluation、Claude / Antigravity の version/help smoke は上記 verification record で確認済み。
- Remotion 4.0.514 の isolated selected subtree materialization / discovery は確認済み。既存 project での `<HtmlInCanvas>` nested usage の有無、browser regression は未確認。
- Matt Pocock candidate の `apm install --frozen`、`writing-for-agents` 移行、local UI grill override と phase-boundary の end-to-end は未実施。
- APM 0.28.0 の isolated frozen install / audit は上記 verification record で確認済み。APM main を採用する場合の lock schema / trust-bin / marketplace validation の実運用差分は未確認。
- upstream の「公式 docs に変更がない」ことを網羅的に証明するものではない。GitHub の対象 repository、release、tag、commit と selected path の範囲で確認できなかったものは **未確認** と扱った。

## 次回の採用時ゲート

1. `llm-agents.nix@d205793b` を隔離した評価対象にし、Claude `2.1.238` / Codex `0.149.0` floor assert、3 system deep eval、x86_64-linux の CLI / MCP / worktree smoke を通す。
2. Antigravity `1.1.17` は metadata / hash / platform evaluation と version smoke のみを確認し、未確認の upstream changelog を採用理由にしない。
3. Remotion `7fc6dea3` は selected subtree を materialize し、`4.0.514` の content hash、skill discovery、nested `<HtmlInCanvas>` guidance の影響を検証する。
4. Matt Pocock と APM CLI の更新は今回の snapshot 更新へ混ぜず、前者は workflow migration、後者は新 release が出た時の frozen install / audit round として扱う。

関連: [2026-08-20 調査ノート](llm-agents-and-apm-update-2026-08-20.md) / [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md)
