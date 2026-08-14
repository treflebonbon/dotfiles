---
type: decision
title: llm-agents と検証済み APM skill pin を更新する
description: Claude Code 2.1.232 の trust boundary 修正を品質フロアへ採用し、Design Hook 契約を検証した Impeccable 4.1.1 と互換な floating skill 更新を固定する
tags: [adr, nix, llm-agents, apm, skills, claude-code, impeccable]
timestamp: 2026-08-15
status: accepted
---

# llm-agents と検証済み APM skill pin を更新する

## Context

2026-08-15 00:48 JST に固定した一次情報調査では、`numtide/llm-agents.nix` の候補 snapshot `9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a` が Claude Code 2.1.232、Copilot CLI 1.0.80、Antigravity CLI 1.1.13 を提供する。Codex 0.147.0、RTK 0.45.0、APM 0.28.0、local `code-review-graph` 2.3.7 は変わらない。

Claude Code 2.1.232 は PowerShell permission bypass、Git Bash symlink bypass、nested repository の trust 継承、cross-session `/tmp` symlink、Linux protected-path sandbox bypass を修正し、GitLab token redaction と project 設定による `sandbox.ripgrep` override 禁止も追加する。一方で interactive session の non-teammate subagent は background / fork が既定になるため、更新は security floor の引き上げだけでなく多 agent 運用の挙動変更を含む。Copilot CLI は model configuration 更新のみを公表し、Antigravity CLI 1.1.13 の version 固有 changelog は確認できなかった。

APM 経路では Impeccable 4.0.4 から 4.1.1 への更新が自動実行する Design Hook runtime を変える。候補 runtime は finding の full policy を session 内の初回だけ表示し、以後は短い footer にする。また agent が確信のある false positive または明示的に許容された例外へ `ignore-value` を自己適用できるようにする一方、`ignore-file` / `ignore-rule` は引き続きユーザーの明示承認を要求する。既存の both-tiers Stop 交互報告 defect は残る。

Remotion と Vercel React View Transitions も selected payload が変わる。Matt Pocock の候補 HEAD は `writing-great-skills` を alias なしで `writing-for-agents` へ rename し、grilling / prototype / phase boundary も同時に変えるため、現行 workflow 契約のまま一括採用できない。一次情報と全 dependency の判定は [調査ノート](../research/llm-agents-and-apm-update-2026-08-15.md) に記録する。

## Decision

- `llm-agents.nix` を immutable snapshot `9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a` に固定する。共有 nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` と対応 system（x86_64-linux / aarch64-linux / aarch64-darwin）は変更しない。
- 導入 version を claude-code 2.1.232、codex 0.147.0、copilot-cli 1.0.80、antigravity-cli 1.1.13、rtk 0.45.0、apm 0.28.0、code-review-graph 2.3.7 とする。`minClaudeCode` は 2.1.228 から 2.1.232 へ上げ、`minCodex` は 0.147.0 を維持する。
- Impeccable を検証済み commit `5a149f3fdb1b5793f10567233b1dcab98fc305fd`（4.1.1）へ固定する。`ignore-value` の自己適用は狭く可逆な advisory suppression として許容するが、full footer が要求するとおり根拠を開示する。`ignore-file` / `ignore-rule` はユーザーの明示承認なしに実行しない。
- APM 0.28.0 の隔離 runtime layout で全37 dependencyを再 materialize し、生成 lock を採用する。selected payload が変わるのは Impeccable、Remotion `2a204c9b71f7a98997128759cbd2ab557b197fd3`、Vercel React View Transitions `b8caa260a420a73042e35521de4b5c8baf6446cc`。repository revision だけが進み content hash が不変の依存も lock には取り込む。
- Matt Pocock の20 dependencyは `ed37663cc5fbef691ddfecd080dff42f7e7e350d` に据え置く。rename と workflow 差分を repo 固有契約へ調停する別作業なしには更新しない。

## Verification

- `nix flake check --all-systems` が3 systemで通過し、同じ overlay 経路から `devShells.<system>.default.drvPath` と7 packageの versionを深く評価した。全 systemで versionが一致した。aarch64-darwinの実機実行は未確認。
- snapshot / Claude floor の red test を先に確認し、更新後に同じ `tests/nix-devshell.bats` slice が green になった。
- Impeccable の旧 runtime に対して新しい footer policy test が red、候補 runtime に対して `tests/design-hook.bats` 9/9 が green になった。full / short footer、`ignore-file` / `ignore-rule` の承認境界、理由の返信開示、`hook-admin.mjs ignore-value` が理由付き finding value だけを `detector.ignoreValues` へ保存することを固定し、既知の both-tiers Stop 交互報告 characterization も維持した。
- `tests/codex-config.bats` の managed hook fail-open 契約、code-review-graph の FastMCP gate、host CLI smoke と、その時点の全 Bats suite 307/307 が通過した。review で追加した self-serve persistence test は上記 Design Hook 9/9 で再検証した。
- 隔離 runtime layout の `apm install --frozen --https` は `No changes` となり、生成 lock の再現性を確認した。
- Claude Code の host smoke は `claude --version` までで、interactive session における subagent の background / fork 既定化、wait / message delivery、context 継承は未確認。security floor の採用は進めるが、ライブ反映後の運用確認事項として残す。

## Consequences

本 ADR は [ADR-0035](0035-update-llm-agents-snapshot-and-trust-boundary-baseline.md) の snapshot 固定値と `minClaudeCode` を supersede し、[ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) の検証済み Impeccable pin と footer policy を補足する。ADR-0034 の3-system decision、ADR-0029 の二層 hook / fail-open / 既知不具合の判断は維持する。

Impeccable の hook entrypoint と Claude / Codex の配線は変えない。初回 full footer と以後の short footer が session state を増やすため、将来の pin 更新でも同一 session の2回出力を compatibility gate に含める。

Claude Code の background / fork 既定化について、管理設定は foreground 前提を明示しておらず security 修正の採用を遅らせる理由にはしない。ただし interactive session smoke が終わるまでは orchestration の実互換性を確認済みとは扱わない。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0035](0035-update-llm-agents-snapshot-and-trust-boundary-baseline.md) / [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md)
