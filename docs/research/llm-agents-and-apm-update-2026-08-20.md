---
type: research
title: llm-agents.nix と APM 管理 skill の更新候補（2026-08-20）
description: 2026-08-18 の候補から進んだ llm-agents.nix、AI CLI、APM 管理 skill の一次情報を確認し、採用単位と検証ゲートを整理した調査ノート。
tags: [research, llm-agents, apm, skills, claude-code, codex, matt-pocock]
timestamp: 2026-08-20
---

# llm-agents.nix と APM 管理 skill の更新候補（2026-08-20）

このノートの `timestamp` と日付だけの履歴表記は JST（Asia/Tokyo）を基準とする。

## 結論

調査基準時刻は **2026-08-20 17:00 JST / 2026-08-20 08:00 UTC 前後**。moving HEAD は必ず次の exact commit として扱う。

更新後の配備 source は、`llm-agents.nix` `20766586959e0dcc2f9e7cff6d49b0c710de30d6`、Claude Code floor `2.1.237`、Codex floor `0.148.0`、Impeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`、Matt Pocock 20 skill `ed37663cc5fbef691ddfecd080dff42f7e7e350d` である。

一次情報で確認できた最新候補は [`numtide/llm-agents.nix@20766586`](https://github.com/numtide/llm-agents.nix/commit/20766586959e0dcc2f9e7cff6d49b0c710de30d6)（2026-08-20 06:06:36 UTC、Orca 1.4.184 の追加 commit）で、当 repo が直接消費する package は次のように進む。

| package           |  更新前 |      採用後 | 判断                                                                                                                                                                                                                            |
| ----------------- | ------: | ----------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| claude-code       | 2.1.232 | **2.1.237** | floor を引き上げた。skill argument 再展開、NT namespace path、Linux/macOS sandbox、background/session permission の修正を採用理由にする。ただし 2.1.232 の Windows symlink / input-redirection hardening の revert は明記する。 |
| codex             | 0.147.0 | **0.148.0** | floor を引き上げた。拒否 path の sandbox fail-closed、MCP OAuth 再接続、skill/plugin root loading、非同期 hook を採用理由にする。librusty-v8 は 150.4.0 へ進むため全 system の deep eval と候補 binary smoke を実施した。       |
| copilot-cli       |  1.0.80 |      1.0.80 | snapshot と共に再評価するが package 差分なし。                                                                                                                                                                                  |
| antigravity-cli   |  1.1.13 |  **1.1.16** | package metadata と artifact hash を更新した。version 固有の upstream changelog は未確認。                                                                                                                                      |
| rtk               |  0.45.0 |      0.45.0 | 変更なし。                                                                                                                                                                                                                      |
| apm               |  0.28.0 |      0.28.0 | release binary は変更なし。                                                                                                                                                                                                     |
| code-review-graph |   2.3.7 |       2.3.7 | local package tree は変更なしとみなすが、snapshot の overlay/evaluation 変更を跨ぐため gate は再実行する。                                                                                                                      |

**判断:** `llm-agents.nix` snapshot、Claude floor、Codex floor、Antigravity を一つの変更単位として採用した。3-system Nix deep eval、Linux host smoke、Claude/Codex smoke が完了し、source へ反映した。

APM では `apm outdated` が **29 dependency outdated** と報告した。APM CLI 自体は v0.28.0 が最新の release tag で、main の [`8993dcc6`](https://github.com/microsoft/apm/commit/8993dcc6fd7171ef3881a9021a7f25b9439e1a29) は未 release のため binary は据え置く。

APM skill は次の3群に分ける。

1. **採用:** Modern Web Guidance、Remotion、Orca `orca-cli`。selected payload の変化を確認し、それぞれ `460e5536`、`21320596`、`5ca747da` を lock へ反映した。
2. **revision-only のため据え置き:** Anthropic `pdf`、Shadcn、Vercel `find-skills`、Orca `computer-use` / `orchestration`。upstream revision は進んだが selected payload hash が変わらないため lock の依存ブロックを変更しなかった。
3. **変更なし:** Effect-TS、Supabase、Vercel `agent-skills`、mizchi。APM の解決結果では現行 selected revision と同一だった。
4. **別 migration:** Matt Pocock `v1.2.3`。`writing-great-skills` がなくなり `writing-for-agents` へ移動したほか、grilling、prototype、phase boundary、ask-matt の router 契約が変わる。単なる pin bump として今回の llm-agents 更新へ混ぜない。

## llm-agents.nix の一次情報

候補 snapshot の package metadata は upstream の exact blob で確認した。

- [Claude Code `hashes.json` at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/claude-code/hashes.json): `2.1.237`
- [Codex `hashes.json` at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/codex/hashes.json): `0.148.0`、librusty-v8 `150.4.0`
- [Copilot CLI `hashes.json` at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/copilot-cli/hashes.json): `1.0.80`
- [Antigravity CLI `hashes.json` at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/antigravity-cli/hashes.json): `1.1.16`、build ID `6607970839166976`
- [RTK package at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/rtk/package.nix): `0.45.0`
- [APM package at `20766586`](https://raw.githubusercontent.com/numtide/llm-agents.nix/20766586959e0dcc2f9e7cff6d49b0c710de30d6/packages/apm/package.nix): `0.28.0`

候補 snapshot には [Orca 1.4.184 の package 初期化](https://github.com/numtide/llm-agents.nix/commit/20766586959e0dcc2f9e7cff6d49b0c710de30d6)も含まれるが、当 repo は Orca CLI binary を `modules/ai.nix` から直接配備せず、APM の skill と Orca app の注入経路を使うため、今回の直接消費 package には含めない。

### Claude Code

[Claude Code 2.1.237 の公式 changelog](https://raw.githubusercontent.com/anthropics/claude-code/v2.1.237/CHANGELOG.md)で、この repo の運用に関係する変更を確認した。

- 2.1.233: skill/command argument を template marker として再展開しない、NT `\\??\\` device path の UNC validation bypass を塞ぐ、Linux sandbox idle CPU、MCP v2 stream、bundled skill alias を修正。
- 2.1.234: remote file read、session restore、`CLAUDE.md` include、workflow script、file upload でも NT namespace path を拒否し、残存する NTLM credential leak 経路を harden。background subagent の permission answer と MCP diagnostics の secret redaction も修正。
- 2.1.237: macOS sandbox の wildcard read-deny を allow region 内でも優先し、削除された working directory 後の background/local MCP/session state、background subagent permission、session messaging の不具合を修正。
- 留保: 2.1.233 は 2.1.232 の Windows Cygwin-style symlink / input redirection permission 変更を revert している。また新しい model では TaskCreate/Get/Update/List と TodoWrite が既定で使えず、`CLAUDE_CODE_ENABLE_TODO_TOOLS=1` が必要になる。この repo の `implement` / `tdd` は tool 名に直接依存していないが、interactive smoke で AFK workflow を確認する。

### Codex

[Codex 0.148.0 の公式 release](https://github.com/openai/codex/releases/tag/rust-v0.148.0)では、次の変更が当 repo の floor 候補に直結する。

- denied / unreadable path の sandbox restriction を Linux/Windows で fail-closed にする。
- MCP server を OAuth 再認証後に再起動なしで復旧する。
- plugin/skill root loading と shared skill loader を整理し、MCP/tool hook と非同期 command hook を追加する。
- resume 時に working directory と approval policy を復元する。

既存の Codex `0.147.0` floor（trust boundary、managed authentication、plugin isolation、secret redaction）を維持した上で、`minCodex = 0.148.0` を候補とする。

## APM skill の一次情報

### APM binary

- [APM v0.28.0 release](https://github.com/microsoft/apm/releases/tag/v0.28.0)が現在の release tag。
- [APM main `8993dcc6`](https://github.com/microsoft/apm/commit/8993dcc6fd7171ef3881a9021a7f25b9439e1a29)には未 release の変更があるため、main commit を binary pin に採用しない。
- 現行 `apm.lock.yaml` は APM 0.28.0 の37 direct dependencyを materializeしている。lock の生成物は source へ採用候補を確定した後、隔離 `apm install --frozen` で再現性を確認する。

### 更新候補の exact revision

APM の upstream ref resolution と `git ls-remote` で確認した candidate は次のとおり。表の revision は調査時点の exact commit で、後から動く branch を意味しない。

| dependency                       | 現行 lock  | 候補 revision                                                                                                     | 備考                                                                                      |
| -------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| anthropics/skills                | `f6656c12` | [`0a64e398`](https://github.com/anthropics/skills/commit/0a64e398ec6bb34a494f0c347e8ccae53a862f8e)                | selected `pdf` は update plan で前進。`skill-creator` は selected payload が不変。        |
| GoogleChrome/modern-web-guidance | `9e70fa4c` | [`460e5536`](https://github.com/GoogleChrome/modern-web-guidance/commit/460e5536b8e61034d83ff4af24bb0bf1112d2cb0) | upstream branch は前進。selected subtree の最終 hash は materialization gate で確定する。 |
| remotion-dev/skills              | `2a204c9b` | [`21320596`](https://github.com/remotion-dev/skills/commit/21320596cf9008cf6ccaa6bf1a2b9f71c8f191c3)              | selected payload の差分確認が必要。                                                       |
| shadcn-ui/ui                     | `d4fc45b1` | [`25be24cc`](https://github.com/shadcn-ui/ui/commit/25be24cca34d06eed29a4779c3f48c4816aa812c)                     | selected payload の差分確認が必要。                                                       |
| stablyai/orca                    | `cb42b608` | [`5ca747da`](https://github.com/stablyai/orca/commit/5ca747dad0d0583f4a1ac91c2655b345ba6c07eb)                    | `orca-cli` / `orchestration` / `computer-use` を同一 revision で再評価。                  |
| vercel-labs/skills               | `c6f69c63` | [`435076e7`](https://github.com/vercel-labs/skills/commit/435076e78988e1e6ec40d00b0b1d76bdbbc5419a)               | selected `find-skills` の差分確認が必要。                                                 |
| mattpocock/skills                | `ed37663c` | [`v1.2.3 / 6acc160e`](https://github.com/mattpocock/skills/releases/tag/v1.2.3)                                   | pin 更新ではなく workflow migration。                                                     |

その他の selected dependency は調査時点の ref resolution で現行と同一だった: Effect-TS `28822c9e`、mizchi `7a0d7286`、Supabase `8331f910`、Vercel `agent-skills` `b8caa260`。

### Matt Pocock v1.2.3

現行の20 dependencyは `ed37663c` で `writing-great-skills` を含む。APM の最新 tag は `v1.2.3`（dereferenced commit `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`）であり、選択した source path を一次情報で確認すると:

- `skills/productivity/writing-great-skills` は消え、`skills/productivity/writing-for-agents` が追加されている。したがって `apm.yml` の path、lock、deploy 後の discovery test、docs の skill 名を同時に変更する必要がある。
- `grilling` は一問一答から design-tree の frontier を一 round ずつ質問する契約へ変更されている。
- `ask-matt` は `handoff` / `compact` / `clear` を含む phase boundary の router へ広がり、smart-zone と context hygiene の前提も変わっている。
- `prototype` は logic branch の TUI から single shareable HTML へ変わっている。
- `grill-with-docs`、`implement`、`research` 等の selected path 自体は残るが、関連する phase boundary と helper document の契約を一括で読む必要がある。

これは現行 repo の `AGENTS.md`、`runtime/skill-harness.md`、local `ui-grill-with-docs`、`handoff` 方針と衝突し得る。Matt skill は **別の workflow migration** として `grill-with-docs` で設計を確定してから採用し、今回の llm-agents snapshot 更新に混ぜない。

## 実施した確認と未確認事項

実施した確認:

- `git ls-remote` で各 upstream の exact branch/tag revision を確認。
- `llm-agents.nix@20766586` の package metadata / hash files を raw source から取得。
- Claude Code 2.1.233–2.1.237 の公式 changelog と Codex 0.148.0 の公式 release body を確認。
- `apm outdated` を source repo で実行し、29 outdated dependency と現行 APM release 状態を確認。
- source-level Bats を候補値で red-green にし、APM は selected payload だけを隔離 materializeして現行 lock の deployment ledger を保持した lock を生成した。
- `nix flake check --no-build --all-systems`、3 system deep evaluation、候補 package version、Claude/Codex/Antigravity/RTK/APM/Copilot の候補バイナリ smoke、Design Hook 9/9、managed fail-open 1/1、`apm install --frozen --https`、`apm audit --ci` を完了した。`chezmoi apply` は managed session の read-only home filesystem と orphan cleanup の失敗で完遂できず、live `apm install --frozen` と live host smoke は後段へ残した。

境界として未確認の事項:

- aarch64-darwin の実機実行。従来の repo 境界どおり、Linux host からの derivation 評価までを採用根拠とする。
- Claude/Codex provider 側の長時間応答品質。今回の smoke では repo の source/package/skill の起動境界と CLI version を確認した。

## 採用時の検証ゲート

1. `llm-agents.nix@20766586` と `minClaudeCode = "2.1.237"` / `minCodex = "0.148.0"` を隔離 worktree で評価した。
2. `nix flake check --no-build --all-systems` と3 systemの `devShells.<system>.default.drvPath` / package version deep evalを通した。現行の3-system境界と shared nixpkgs pinは変更していない。
3. x86_64-linuxでClaude、Codex、Copilot、Antigravity、RTK、APM、code-review-graphの CLI/MCP smokeを行った。aarch64-darwinは実機実行ではなく評価境界とした。
4. APM manifestの selected revisionを隔離 runtimeへ materializeし、`apm install --frozen --https`、`apm audit --ci`、lock再現性、selected file listを確認した。Impeccableは `tests/design-hook.bats` 9/9 と managed fail-open 1/1を通過した。
5. Claude 2.1.237 の print smoke と Codex 0.148.0 の candidate binary version smoke、各 CLI の help/version 境界を確認した。provider 応答を伴う background/message、MCP OAuth、worktree、skill argument の長時間実運用は別途実環境で確認する。`CLAUDE_CODE_ENABLE_TODO_TOOLS=1` は恒久設定していない。
6. 全 source gate 後に配備 source、ADR、runtime baseline、testsを同じ変更として更新した。managed session の home filesystem が read-only のため `chezmoi apply` / live `apm install --frozen` / live smoke は実行完了できず、topic commit 後の環境で再実行する。

関連: [ADR-0036](../adr/0036-update-llm-agents-and-validated-skill-pins.md) / [ADR-0037](../adr/0037-update-llm-agents-and-compatible-skill-pins.md) / [skill-harness](../../runtime/skill-harness.md)
