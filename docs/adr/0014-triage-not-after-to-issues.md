---
type: decision
title: 設計→実装ワークフローを「メインフロー1本 + on-ramp 2つ」に統合する（ADR-0012 を amend）
description: ADR-0012 の「シナリオ別3チェーン」枠組みを、上流 mattpocock ask-matt の main-flow/on-ramp 構造に合わせて統合する。triage は to-issues 産出物には使わず raw issue 専用の on-ramp とする
tags: [adr, skills, mattpocock, workflow, triage]
timestamp: 2026-07-07
---

# 設計→実装ワークフローを「メインフロー1本 + on-ramp 2つ」に統合する（ADR-0012 を amend）

## Status

Accepted (2026-07-07)。本 ADR の「この repo では `implement` を導入しておらず `tdd` → `code-review` に相当」という記述は、[ADR-0015](0015-add-tdd-commit-confirmation.md)（2026-07-07）でより正確な根拠（upstream issue による実証的な信頼性バグ）と、`tdd`/`code-review` 間の commit 責務の明記に補強された。その後、[ADR-0022](0022-align-mattpocock-v1-1-workflow.md)（2026-07-10）で `implement` を導入し、`to-prd` / `to-issues` を上流現行名の `to-spec` / `to-tickets` に置き換えた。triage を raw issue 専用 on-ramp とする判断は維持する。

## Context

[ADR-0012](0012-branch-workflow-chain-by-scenario.md) はワークフローを「要件未確定」「要件確定済み実装」「バグ修正」の3つの独立したチェーンに分岐して記述していた。しかし upstream mattpocock/skills の router skill `ask-matt` を実際に読むと、設計はそもそも3本の独立チェーンではなく、**1本のメインフロー**（`grill-with-docs` → `to-prd` → `to-issues` → `implement`。この repo では `implement` を導入しておらず `tdd` → `code-review` に相当。要件確定済みなら `grill-with-docs`/`to-prd`/`to-issues` を省略して直接 implement 相当へ）と、そこに合流する**2つの on-ramp**（raw issue 用の `triage`、ハードバグ用の `diagnosing-bugs`）という構造だった。

具体的な食い違いは2点:

1. **`triage` の位置づけ**: `to-prd` / `to-issues` はどちらも自前で `ready-for-agent` を付与しており、`to-prd` は「Apply the ready-for-agent triage label - no need for additional triage」と明記している。`ask-matt` も次のように明言している:

   > Triage is only for issues you didn't create — bug reports, incoming feature requests, anything that arrives raw. Issues that `/to-issues` produced are already agent-ready, so don't triage them.

   ADR-0012 の「要件未確定」チェーンが `triage` を末尾に含めていたのは、この upstream の設計と矛盾する二度手間だった。

2. **チェーンの独立性**: ADR-0012 は3チェーンを並列独立に記述し、それぞれが `to-worktree` から始まるかのように書いていた。しかし実際の運用（本 ADR を書くに至ったセッション自体がその実例）では、`grill-with-docs → to-prd → to-issues` を終えたあと、同一 worktree/セッション内でそのまま `tdd → code-review → to-pr` に連続して入っており、`to-worktree` に戻ってはいない。3チェーンを対等な独立チェーンとして描くと、この連続性が見えにくくなっていた。

## Decision

ワークフローを次の形に統合する:

- **メインフロー**: `to-worktree`（一度だけ）→ `grill-with-docs` → `to-prd` → `to-issues` → `tdd` → `code-review` → `to-pr`。要件がすでに確定している小さな作業では `grill-with-docs` / `to-prd` / `to-issues` を省略し、`to-worktree` の直後に `tdd` から入ってよい。
- **on-ramp**（メインフロー外から issue/バグが持ち込まれる入口）:
  - raw な issue（bug report・降ってきた要望等、`to-issues` を経由していないもの）→ `triage` → ready-for-agent 化 → `tdd` へ合流。`triage` は `to-issues` の産出物には使わない。
  - ハードなバグ（再現・原因調査が必要）→ `diagnosing-bugs` → `code-review` → `to-pr`。raw な報告として届いた場合はまず `triage` を通してから `diagnosing-bugs` へ。
- `CLAUDE.md` / `runtime/skill-harness.md` / `apm.yml` のコメントをこの構造で書き直す。

ADR-0004 のその他の決定（`to-worktree` による worktree 隔離、`setup-matt-pocock-skills` による初期設定、`to-pr` の役割等）はそのまま維持する。

## Consequences

- `to-prd` → `to-issues` で完結する変更は、triage の category ラベル付与や Agent Brief コメント無しでそのまま `tdd` に入れる。category ラベル（`bug`/`enhancement`）は `to-prd`/`to-issues` の issue には付与されない運用になる（upstream 側もこの点を要求していない）。
- `triage` / `diagnosing-bugs` の実際の役割に変更はない。適用対象が「メインフローの外から来た issue/バグ」に絞られる。
- ワークフローが「独立した3チェーン」ではなく「1本のメインフロー + 2 on-ramp」として描かれることで、worktree を一度しか入らないという実態と、upstream `ask-matt` の設計により忠実になる。
- 既に `to-issues` 産出物に対して triage を実行済みのケース（例: issue #22）を遡って取り消す必要はない。

関連: [ADR-0012](0012-branch-workflow-chain-by-scenario.md)（本 ADR が amend）/ [ADR-0004](0004-fill-mattpocock-gaps.md)
