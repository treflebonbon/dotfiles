---
type: decision
title: Orca native worktree を /to-worktree の外側に置く
description: Worktree Entry Point を共通の入口契約として保ち、Orca は agent 起動前の native worktree、非 Orca runtime は /to-worktree で満たす
tags: [adr, orca, git, worktree, skills]
timestamp: 2026-09-01
status: accepted
---

# Orca native worktree を /to-worktree の外側に置く

## Context

[ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md) は `/to-worktree` を全 runtime 共通の Worktree Entry Point とし、Orca の新規 worktree が必要な場合は agent session 内から `orca-cli` の native create / full handoff を呼ぶ契約にした。しかしこの経路は、Worktree Owner である Orca が agent 起動前に worktree を所有できるにもかかわらず、起動済み agent から Orca へ ownership を戻す。Codex sandbox 内から WSL→Windows interop を使う環境では、その折り返し自体が失敗し得る。

## Decision

**Worktree Entry Point** は「workflow を validated task worktree から始める」という全 runtime 共通の入口契約として維持するが、全 runtime が `/to-worktree` を実行するという意味にはしない。

- Orca では、Orca native 機能による worktree の作成・選択と、その checkout での agent session 起動が具体的な Worktree Entry Point となる。Orca session 内から `/to-worktree` 経由で Orca CLI の native create / full handoff を呼び直さない。
- 非 Orca runtime では `/to-worktree` が具体的な Worktree Entry Point となり、各 Worktree Owner への既存 routing を担う。
- Orca session の識別は実行中 agent の runtime 自己認識に従い、`ORCA_CLI_COMMAND` や内部 `ORCA_*` environment を汎用 discriminator とする判定ロジックは導入しない。runtime を識別できない場合は既存どおり fail closed にする。
- Orca で `/to-worktree` を誤って起動した場合、current checkout が linked worktree なら検証して no-op とする。primary checkout なら Orca CLI や raw Git を呼ばず停止し、Orca native worktree を作成・選択して新しい agent session を始めるよう案内する。
- Orca では、local file の変更につながる engineering flow の開始時に current checkout が linked worktree であることを read-only に検証する。primary checkout なら local edit や外部書込みを始めず、同じ recovery guidance で停止する。説明、状況確認、local/shared state を変更しない調査は primary checkout でも許可する。

この decision は ADR-0044 の universal `/to-worktree` routing を amend する。ADR-0044 が定める linked worktree validation、Worktree Activation、Runtime Adapter、Active Git Metadata Boundary、technical sandbox の decision は変更しない。Orca native worktree 上で起動する Codex も、`codex-worktree` / `codex-orca` による Worktree Activation を引き続き使う。
