---
type: decision
title: Builder-Evaluator ループの commit 確認を廃止し、worktree 隔離＋自動テスト＋PR レビューを安全モデルとする（ADR-0015 を amend）
description: grill-with-docs セッションで「human out of the loop」なループエンジニアリングを検討した。Planner（grill-with-docs〜to-issues）と Builder-Evaluator（tdd〜code-review）を語彙として分離し、Builder-Evaluator の commit 確認（ADR-0015 が導入した2箇所）を両方とも廃止する。一次情報調査（docs/research/human-out-of-the-loop-coding-agents.md）により、doc 層の commit 確認は permission mode に依存し、AFK 運用で最も必要な場面で機能しないと判明したため、安全性は worktree 隔離＋自動テスト＋PR レビュー（batch された to-pr）で担保する設計に変更した
tags: [adr, skills, mattpocock, workflow, tdd, code-review, autonomy]
timestamp: 2026-07-08
---

# Builder-Evaluator ループの commit 確認を廃止し、worktree 隔離＋自動テスト＋PR レビューを安全モデルとする（ADR-0015 を amend）

## Status

Accepted (2026-07-08)

## Context

`/grill-with-docs` セッションで、以前議論した「`implement` ではなく `tdd`/`diagnosing-bugs` を使う」判断（ADR-0004/0015）を再確認しつつ、「human out of the loop」——人間の介在を最小化するループエンジニアリング——をどう進めるか検討した。

セッション冒頭で二点が判明した:

- ユーザーが確認した `ask-matt`（`~/.claude/skills/ask-matt/SKILL.md`）は upstream からの vendored コピーで、今も `/implement` をメインフローの中核として扱っている。この repo の `implement` 非導入判断（ADR-0004/0015）を知らないドキュメントであり、「ask-matt 的に問題ない」は forward compatibility の確認にはならない。
- この repo は既に「ある種の自律性は受け入れ、ある種は意図的に拒否する」という線引きを持っている。受け入れ側の例: Claude Code 2.1.198 以降の worktree 完了時の自動 commit/push/draft PR、`tdd`/`code-review` の model-invoked 自動発火。拒否側の例: ADR-0004 の4値 verdict gate・evidence JSON schema 非導入、ADR-0015 の commit 強制ゲート非導入、issue #27/[ADR-0016](0016-to-pr-shared-contract-vocabulary.md) の「評価結果を次サイクルへ自動で戻す経路」非自動化。

ユーザーは「既存の no-gates 方針の範囲内で確認の手間を減らす」方向（ADR-0004/0015 が却下した機械的ゲートの再導入ではない）を選んだ。

ワークフロー全体を洗い出すと、人間の確認ポイントは3種に分かれる: (1) 設計協働そのもの（削ると skill の価値が失われるため対象外）、(2) 異常系・曖昧時のみの fallback（もともと低頻度で対象外）、(3) happy path で毎回発生する administrative な確認（`tdd` の各 green slice の commit 確認、`code-review` 後の修正差分 commit 確認。いずれも [ADR-0015](0015-add-tdd-commit-confirmation.md) 由来）。3 が実質的な摩擦であり、本 ADR のスコープはここに絞られる。

**ローカル commit はそもそも「確認が必要な行動」か**: `CLAUDE.md` 自身のリスク分類（破壊的・取り消し困難・他者に見える行動のみ確認が必要）に照らすと、ローカルの `git commit`（`git reset` で即座に取り消せ、push しない限り他者に一切見えない）はどれにも該当しない。ADR-0015 が commit 確認を求めた根拠は「commit の危険性」ではなく、Claude Code 自体が持つ「明示依頼なしに commit しない」というデフォルト方針の踏襲だった。

### 一次情報調査（docs/research/human-out-of-the-loop-coding-agents.md）

セッション中に model-invoked `research` skill が調査した一次情報ドキュメントが `docs/research/human-out-of-the-loop-coding-agents.md` として既に存在していた（本セッションへのインプットとして作成されたもの。context compaction を挟んだため一時的に見落とし、後半で発見して読み込んだ）。Anthropic 公式ドキュメント・Ralph Wiggum（loop engineering の実運用パターン）・upstream `mattpocock/skills` の3方向を一次情報で調査したもので、以下が本 ADR の設計に直接影響した。

- **doc 層の commit 確認は permission mode に依存する**: 非対話（headless / `auto` / `bypassPermissions`）モードでは、確認プロンプトは応答者不在のため自動承認されるか、ブロックが続いてセッションが abort する（同ドキュメント §1a, 出典 [8]）。対話モード（`default`/`acceptEdits`）では人間は既にそこにいる。**つまり commit 確認の有用性は、それが必要な場面（AFK 運用）で機能せず、機能する場面（対話運用）では不要という、安全機構として構造的に噛み合わない位置にある。**
- **Anthropic 公式・Ralph Wiggum の双方が一致して採る安全モデルは「サンドボックス/worktree 隔離＋自動検証ゲート」であり、「人間の目視チェック」ではない**（同ドキュメント §1e, §2b, 出典 [6][7][10]）。人間のレビューは、エージェント不在でも成立する形——事後の PR レビュー等——に位置づけられている。
- **upstream #399 自体の desired behavior**（AI triage brief, 出典 [13]）は「the workflow should continue through review and commit **unless the user explicitly interrupts it**」——不要な人間への割り込み自体をバグとして扱う立場であり、「commit 前に人間に聞く」を解決策として推していない。
- **Claude Code には Stop hook / PreToolUse hook という公式の軽量な機構があり**、review の省略を機械的に強制することも技術的には可能（同ドキュメント §1c, 出典 [4]）。ADR-0004/0015 が却下したのは pytest hook 的な重量級 evidence gate であり、この native hook 機構はそれとは別物——選択肢として検討したが、本 ADR では採用しない（Decision 参照）。

これを踏まえ、セッション前半で一度合意した非対称設計（`tdd` slice のみ自動化、`code-review` 後の修正 commit は確認を残す——upstream #399 の review-skip リスクをここで人間の目が拾う、という想定。`codex-rescue` subagent への相談でも同じ結論を得ていた）を再検討した。この非対称設計は「commit 確認が review-skip の安全網として機能する」という前提に立っていたが、上記の一次情報はその前提自体が permission mode 依存で崩れることを示した。ユーザーは「permission mode で分岐させる設計は採らない」と明言し、Builder-Evaluator の commit 確認を（tdd slice・code-review 後の修正の両方について）一律に廃止し、安全性は worktree 隔離＋自動テスト＋PR レビューで担保する、という単一設計に確定した。

## Decision

`to-issues` までの設計協働フェーズを **Planner**、`tdd`↔`code-review` の実装検証フェーズを **Builder-Evaluator** と呼ぶ（[CONTEXT.md](../../CONTEXT.md)）。

1. **`tdd` の各 green slice の commit は確認なしで自動的に行う**（ADR-0015 の該当規定を置き換え）。commit 後は通常運用どおり何を commit したか報告する。
2. **`code-review` 完了後、ブロッキング指摘への修正の commit も確認なしで自動的に行う**（ADR-0015 の該当規定を置き換え。当初検討した非対称設計——ここだけ確認を残す——は撤回した。理由は Context 参照: commit 確認は permission mode 依存で安全機構として機能しない）。
3. **review integrity（review が実際に行われたか）は、人間の目視確認ではなく次の3層で担保する**:
   - **worktree 隔離**（`to-worktree`）——変更は隔離されたブランチに閉じる
   - **自動テスト**（`tdd` の red-green 必須化、`lefthook` の pre-commit hook）——commit のたびに機械的に実行される
   - **PR レビュー**（`to-pr` が worktree/branch 単位で一度だけ開く PR を、人間が戻ってきた時にレビューする）——エージェント不在でも成立する事後チェックポイント
4. **`tdd` のシーム確認は、対象 issue の Acceptance Criteria（Planner フェーズ＝`to-issues` の「Quiz the user」で既に人間が確定済み）からシームが一意に導出できる場合は省略する。** AC 単体で判断がつかない曖昧なケースのみ、従来どおり人間に確認する。`tdd` が ready-for-agent issue を経由せず単体で呼ばれる場合はこの省略は適用されず、常にシーム確認を行う。
5. **Builder-Evaluator ループは、`to-issues` が生成した issue をまたいで、issue 間で停止せず連続して処理してよい。** 適用範囲は「同一 worktree/branch」であり「単一の連続セッション」ではない——smart zone（~120k トークン）に達した場合は引き続き `/handoff` で別セッションへ移ってよく、複数セッションが同一 worktree/branch を扱うことも許容される。これは issue #28・#29 が単一 worktree・単一 PR（#30）として実践されていた前例（本 ADR 以前は未文書化だった）を明文化するもの。
6. **`to-pr` は、対象 worktree/branch 上の全 issue が完了してから一度だけ実行する**（issue ごとの都度 PR 作成はしない）。明示的に AFK/自律運用を指示されたタスクではエージェントが自律的に `to-pr` まで呼び出してよい。指示が無い通常運用では、全 issue 完了をエージェントが報告し、ユーザーの明示的な `/to-pr` 呼び出しを待つ。
7. **push / PR 作成自体の確認は変更しない**（`to-pr` 手順5「ask before pushing」のまま）。`CLAUDE.md` の一般リスク分類上「他者に見える」行動に該当するため。
8. **Stop hook / PreToolUse hook による機械的な review 強制は、技術的に可能であることを記録した上で、今回は採用しない。** ADR-0004/0015 が却下した重量級ゲート（pytest hook・evidence JSON schema）とは別物の、Claude Code 公式の軽量な機構だが、本 ADR の安全モデル（worktree 隔離＋自動テスト＋PR レビュー）で当面は十分と判断した。将来 review-skip が実運用上の問題として顕在化した場合の対応候補として残す。
9. **permission mode（`default`/`acceptEdits`/`auto`/`bypassPermissions`）による分岐は設けない。** Builder-Evaluator の挙動は運用モードに関わらず単一の設計として文書化する。

## Consequences

- Builder-Evaluator ループの中断頻度が大きく下がる（`tdd` slice・`code-review` 後の修正のいずれも確認なしで commit される）。review-skip に対するリアルタイムの人間検知は失われ、実質的な検知点は事後の PR レビュー（人間が戻ってきた時）のみになる。
- `tdd`/`lefthook` の自動テストが実質的な安全網になるため、テストカバレッジが不十分な変更では review-skip が検知されにくい、という残存リスクがある（本 ADR のスコープ外——テスト品質は `tdd` skill 自体の責務）。
- `tdd` slice・`code-review` 後の修正いずれの自動 commit も、project `CLAUDE.md` の指示が Claude Code 組み込みの「明示依頼なしに commit しない」デフォルトを実際に上書きできる、という前提に立っている。この前提は本 ADR 時点で未検証（ADR-0015 自身も他ランタイム——Codex 等——がこのデフォルトを共有しない可能性を指摘しており、ランタイム間で挙動が揃わない可能性がある）。運用開始後、確認なしで commit が実際に行われるか経験的に確認すること。
- worktree/branch 単位で `to-pr` を一度だけ呼ぶ運用が明文化されたことで、issue ごとに個別 PR を作るかどうかの曖昧さが解消される。
- 本 ADR は ADR-0015 の2つの commit 確認規定を両方とも置き換える。ADR-0015 の no-gates 方針、#399 に基づく `implement` 非導入根拠はそのまま維持する。
- Stop hook / PreToolUse hook による機械的強制は検討済みだが未採用のまま記録される。review-skip が実運用で問題化した場合、まずこの選択肢を再検討する。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [ADR-0014](0014-triage-not-after-to-issues.md) / [ADR-0015](0015-add-tdd-commit-confirmation.md)（本 ADR が置き換え）/ [ADR-0016](0016-to-pr-shared-contract-vocabulary.md) / issue #27 / [docs/research/human-out-of-the-loop-coding-agents.md](../research/human-out-of-the-loop-coding-agents.md) / upstream [mattpocock/skills#399](https://github.com/mattpocock/skills/issues/399), [#329](https://github.com/mattpocock/skills/issues/329), [#451](https://github.com/mattpocock/skills/issues/451), [#124](https://github.com/mattpocock/skills/issues/124)
