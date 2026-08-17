---
type: decision
title: llm-agents と互換性を検証した APM skill pin を更新する
description: Claude Code 2.1.233 と互換な APM 更新を採用候補として評価し、interactive gate 通過まで配備 source から分離する
tags: [adr, nix, llm-agents, apm, skills, claude-code, impeccable]
timestamp: 2026-08-18
status: proposed
---

# llm-agents と互換性を検証した APM skill pin を更新する

## Context

2026-08-18 00:05 JST に固定した一次情報調査では、`numtide/llm-agents.nix` の候補 snapshot `5b3a7eff4326cb9001a79938a53e2fc8662d38c2` が Claude Code 2.1.233 を提供する。直接消費する他の6 package treeは現pinと同一で、Codex 0.147.0、Copilot CLI 1.0.80、Antigravity CLI 1.1.13、RTK 0.45.0、APM 0.28.0、local `code-review-graph` 2.3.7を維持する。

Claude Code 2.1.233はNT `\\??\\` device pathによるUNC validation bypass / NTLM credential leak、skill / command argumentのtemplate marker再展開、Linux sandbox idle CPU、MCP v2 reconnectを修正する。一方、2.1.232のCygwin-style symlinkとinput redirectionのpermission変更はrevertされ、新しいmodelではTaskCreate/Get/Update/ListとTodoWriteが既定で無効になる。したがってsecurityの単調増加とは扱わず、revertとinteractive workflowの留保を品質フロアの根拠へ残す。

APM経路ではImpeccable、Remotion、Orca `orca-cli`のselected payloadが変わる。Impeccableのhook / footer / admin coreは前pinと同一blobだが、static HTML detector等を含むruntime全体は変わるためDesign Hook gateを必要とする。Matt Pocockの候補HEADは`writing-great-skills`のrename、frontier interview、HTML prototype、handoff / compact / clearのphase boundaryを変更し、現行のquality floorとworkflow契約へはpinだけで取り込めない。一次情報と全37 dependencyの判定は [調査ノート](../research/llm-agents-and-apm-update-2026-08-18.md) に記録する。

## Proposed Decision

- interactive gate通過後に、`llm-agents.nix`をimmutable snapshot `5b3a7eff4326cb9001a79938a53e2fc8662d38c2`へ固定する。ユーザーdevShellが共有するnixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`と対応system（x86_64-linux / aarch64-linux / aarch64-darwin）は変更しない。
- 同じ条件で`minClaudeCode`を2.1.232から2.1.233へ上げ、`minCodex`は0.147.0を維持する。Task\*/TodoWriteのためのcompatibility flagは、interactive smokeで必要性を確認するまで追加しない。
- Impeccableの採用候補を検証済みcommit `5c5553b1d7f9e89bb833f9179cea681742a17720`とする。Claude / CodexのPostToolUse + Stop配線、fail-open、full / short footer、理由付き`ignore-value`と明示承認を要する`ignore-file` / `ignore-rule`の境界は変更しない。
- APM 0.28.0の隔離runtimeで全37 dependencyを再materializeしたlockを採用候補とする。Remotionは`9f0faa5056c3167d0fc0b7e9575d35284dce98c8`、Orcaは生成時の`a1cd7eaa7ed558f43312b8608a34181727b2a77c`へ進め、Anthropic / Shadcnのrevision-only更新も含める。
- Matt Pocockの20 dependencyは`ed37663cc5fbef691ddfecd080dff42f7e7e350d`に据え置く。上記workflow差分を調停する別migrationなしには更新しない。APM binaryも0.28.0のまま維持する。
- 本ADRがproposedの間、配備可能なchezmoi sourceは[ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md)のsnapshot `9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a`、`minClaudeCode = 2.1.232`、Impeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`と対応lockを維持する。上記候補revisionは本ADR、調査ノート、隔離runtimeだけに置く。

## Verification

- 隔離した実装worktreeでsnapshot / Claude floorとAPM pin / hashのテストを旧値でred、候補値でgreenとして確認した。その後、interactive gate未完了のため配備sourceはADR-0036の値へ戻し、proposed revisionが配備sourceへ混入しない回帰テストを追加した。
- `nix flake check --all-systems`を通し、3 systemすべてでdevShellを`.drv`まで強制した。同じshared overlay経路の7 package versionはClaude Code 2.1.233、Codex 0.147.0、Copilot CLI 1.0.80、Antigravity CLI 1.1.13、RTK 0.45.0、APM 0.28.0、code-review-graph 2.3.7で一致し、CRGのFastMCP 3.3.1 / tree-sitter-language-pack 0.13.0 floorも満たした。
- x86_64-linuxで7 CLIを実行し、CRGは一時repoのgraph buildとstdio MCP `initialize`応答まで確認した。aarch64-darwinの実機実行は未確認である。
- 候補Impeccable runtimeで`tests/design-hook.bats` 9/9、managed hook fail-open 1/1が通過した。既知のboth-tiers Stop交互報告characterizationも維持されている。
- 隔離runtimeの`apm install --frozen --https`は全37 dependencyを再確認して`No changes`となり、lock SHA-256は書き戻し前後で一致した。
- hostの実Nix profile scriptを拾わない隔離条件で、全Bats suite 309/309が通過した。
- Claude Code 2.1.233のinteractive TUI、project trust、custom skill argumentの投入までは確認したが、応答前にClaude TeamのOAuth access tokenが401 expiredとなった。background / fork、wait / message delivery、worktree context、skill argumentの応答値、Task\*/TodoWriteなしでのimplement進行は未確認である。再認証後にこのgateを通すまで本ADRをacceptedへ変更せず、候補revisionを配備sourceへ入れない。

## Consequences

interactive gate通過後に本ADRをacceptedへ変更し、同じ変更で候補revisionを配備sourceへ反映した時点で、[ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md) のsnapshot固定値、`minClaudeCode`、検証済みImpeccable pinをsupersedeする。それまでは候補を本ADRと調査ノートでレビュー可能にし、配備sourceとライブ環境の採用判断はADR-0036を維持する。ADR-0034の3-system decision、ADR-0029の二層hook / fail-open / suppression境界 / 既知不具合、`minCodex = 0.147.0`、Matt Pocock workflow据え置きの判断は変更しない。

Claude Code 2.1.233のrevert対象をhardening根拠として数えない。Task\*/TodoWriteが見えないことだけを理由にcompatibility flagを先回りで有効化せず、現行`implement` / `tdd`契約が具体的に阻害された場合に別途判断する。

Matt Pocockの更新は、rename、routerの未導入先、質問UX、prototype artifact、phase boundary、smart-zone表記を一つのworkflow migrationとして扱う。今回の非Matt更新へ混ぜない。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md) / [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md)
