---
type: decision
title: Orca native worktree を built-in agent launch と組み合わせる
description: Orca は native worktree と built-in agent permission mode、非 Orca runtime は /to-worktree と必要な adapter で Worktree Entry Point を満たす
tags: [adr, orca, git, worktree, skills]
timestamp: 2026-09-01
status: accepted
---

# Orca native worktree を built-in agent launch と組み合わせる

## Context

[ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md) は `/to-worktree` を全 runtime 共通の Worktree Entry Point とし、Orca の新規 worktree が必要な場合は agent session 内から `orca-cli` の native create / full handoff を呼ぶ契約にした。また Orca native Codex にも repository-owned `codex-orca` / `codex-worktree` adapter を使わせた。しかし Orca は agent 起動前に worktree、working directory、agent command、permission mode を所有できる。agent session から ownership を戻したり、Orca の built-in integration を repository wrapper で置き換えたりすると、Orca の公式経路と責務が重複する。

## Decision

**Worktree Entry Point** は「workflow を validated task worktree から始める」という全 runtime 共通の入口契約として維持するが、全 runtime が `/to-worktree` を実行するという意味にはしない。

- Orca では、Orca native 機能による worktree の作成・選択と、Agent Picker からの built-in agent 起動が具体的な Worktree Entry Point となる。Orca session 内から `/to-worktree` 経由で Orca CLI の native create / full handoff を呼び直さない。
- Orca native Codex の command と permission mode は Orca に委ねる。自律 workflow は Orca shipped Yolo（Codex の full-autonomy flag）を標準経路とし、`codex-orca` / `codex-worktree` や repository-owned permission override を挟まない。
- Yolo では OS-level の Technical Sandbox Boundary が無いため、Orca worktree は変更の review・破棄・cherry-pick を行う operational isolation であり、filesystem / network の security boundary ではない。信頼できる repository / host だけで使う。
- 権限確認を残す場合は Orca の Agent Permissions を Manual に切り替える。この場合、agent sandbox から protected Git metadata を書けない操作は Orca Source Control で stage / commit / push し、自律 commit を得るために repository adapter へ戻さない。
- 非 Orca runtime では `/to-worktree` が具体的な Worktree Entry Point となり、各 Worktree Owner への既存 routing を担う。
- Orca session の識別は実行中 agent の runtime 自己認識に従い、`ORCA_CLI_COMMAND` や内部 `ORCA_*` environment を汎用 discriminator とする判定ロジックは導入しない。runtime を識別できない場合は既存どおり fail closed にする。
- Orca で `/to-worktree` を誤って起動した場合、current checkout が linked worktree なら検証して no-op とする。primary checkout なら Orca CLI や raw Git を呼ばず停止し、Orca native worktree を作成・選択して新しい agent session を始めるよう案内する。
- Orca では、local file の変更につながる engineering flow の開始時に current checkout が linked worktree であることを read-only に検証する。primary checkout なら local edit や外部書込みを始めず、同じ recovery guidance で停止する。説明、状況確認、local/shared state を変更しない調査は primary checkout でも許可する。

この decision は ADR-0044 の universal `/to-worktree` routing と Orca adapter routing を amend する。ADR-0044 が定める linked worktree validation、raw Codex CLI の `codex-worktree` Worktree Activation、Active Git Metadata Boundary、technical sandbox の decision は非 Orca 経路に限って維持する。`codex-orca` は既存 caller 向け compatibility entry として残しても Orca native session の entry / activation には使わない。

関連: [Orca Agents & sessions](https://www.onorca.dev/docs/model/agents-sessions) / [Orca Supported agents](https://www.onorca.dev/docs/agents/supported) / [Orca Codex integration](https://www.onorca.dev/docs/agents/codex) / [Orca Commit & push](https://www.onorca.dev/docs/review/commit-push) / [OpenAI Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)
