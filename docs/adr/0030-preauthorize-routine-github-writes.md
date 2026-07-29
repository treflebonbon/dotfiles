---
type: decision
title: 内容確定後の非破壊 GitHub 書込みを事前承認する
description: ユーザーが結果を依頼し内容が確定した GitHub 定型書込みは外部操作を理由に二重確認せず、破壊的・履歴改変・運用実行系だけを承認境界に残す
tags: [adr, github, approvals, codex, skills]
timestamp: 2026-07-29
status: accepted
---

# 内容確定後の非破壊 GitHub 書込みを事前承認する

## Context

`to-pr` で PR を公開するとき、Claude Code では停止しない運用になっている一方、Codex では二つの独立した確認要因があった。共有 `to-pr` skill が push・PR 作成・画像 upload を外部操作として明示確認する契約を持ち、Codex も `approval_policy = "on-request"` の下で通常の `git push` / `gh pr create` に allow rule を持っていなかった。GitHub app も user default の重要操作レビューを継承していた。

確認をすべて無効化すると GitHub 以外の sandbox 越境や破壊的操作まで広がる。一方、ユーザーが既に結果を依頼し、Planner・finding review・会話などで内容も確定した後に「外部操作だから」と同じ承認を聞き直すことは、判断を増やさない administrative な停止である。

## Decision

1. ユーザーが結果を依頼し内容が確定した後の **非破壊な GitHub 定型書込み**は二重確認しない。対象は current topic branch の非 force push、PR/issue の create/edit/comment、PR の review/ready、label の create/edit とする。topic branch push は引数を受け取らず、remoteの実際のdefault branchを拒否して内部で`git push -u origin HEAD`だけを実行する`git-push-topic`を使う。default branchを判定できない場合はfail closedとする。これは依頼済み scope を広げる権限ではない。
2. `/to-pr` の明示呼出し、または AFK/自律完了の明示許可は、topic branch push・PR create/edit・証跡画像 upload・整合済み `Fixes` への事前承認とする。close 対象は PR body と完了報告に記録するが、公開直前の確認には戻さない。
3. 内容を決める対話は維持する。dogfood finding の Keep/Skip/Edit、曖昧な issue 内容、実課金などは「外部操作の確認」ではなく product decision または不可逆操作なので、本決定の対象外とする。
4. default branch への直接 push、force-push、merge、close/reopen/delete、release、workflow dispatch、repository settings/secrets、共有 infrastructure は事前承認しない。force-push は従来どおり禁止し、GitHub app の destructive tool は無効化する。
5. Codex は `approval_policy = "on-request"` を維持する。execpolicy は`git-push-topic`と列挙した`gh` commandだけをallowし、生の`git push`に加えてabsolute path・Git global option・`env`/`command` wrapperによる代表的な迂回形もforbiddenとする。default branchへの直接pushは明示承認後に`git-push-reviewed`を使い、state transitionはprompt、force-pushはforbiddenとする。GitHub app は非破壊toolを`approve`、destructive toolをdisabledとする。
6. この契約をCodex・Claude Code・Gemini/Antigravityのglobal guidanceとproject workflowで統一する。

本決定は **ADR-0019 Decision 7**（push / PR作成確認の維持）を置き換え、ADR-0023の`triage` apply確認についても内容確定後の非破壊GitHub書込みに限って置き換える。

## Consequences

- `to-pr` と定型issue操作は内容確定後に停止せず、CodexでもClaude Codeと同じ流れで公開まで進む。
- Codexの一般的なsandbox・network承認は残り、GitHub以外へ権限は波及しない。
- topic branch pushは`git-push-topic`へ統一される。生の`git push`は遮断され、明示承認済みのdefault branch pushだけが`git-push-reviewed`を通る。
- GitHub appのdestructive toolは確認付き実行ではなく遮断される。明示依頼された破壊的操作は、対象を確認した上でCLI等の別経路を使う。

関連: [ADR-0019](0019-builder-evaluator-cross-issue-autonomy.md) / [ADR-0023](0023-resolve-external-skill-contracts-locally.md) / [skill-harness](../../runtime/skill-harness.md)
