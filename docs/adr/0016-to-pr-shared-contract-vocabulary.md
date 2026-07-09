---
type: decision
title: to-pr を軽量 evaluator 化し、ready-for-agent と PR body を共有 contract 語彙で繋ぐ
description: issue #27 を受け、verification matrix・contract 埋め込み・code-review 実施記録・harness-feedback 運用を doc-level の共有語彙として統合する。4値 verdict gate・evidence JSON schema・eval.yaml 復活は見送り、ADR-0004 の軽量方針を維持する
tags:
  [adr, skills, to-pr, triage, harness-feedback, contract, verification-matrix]
timestamp: 2026-07-07
---

# to-pr を軽量 evaluator 化し、ready-for-agent と PR body を共有 contract 語彙で繋ぐ

## Status

Accepted (2026-07-07)

## Context

[issue #27](https://github.com/treflebonbon/dotfiles/issues/27) は「軽量化としては筋が通っているが、評価結果を次サイクルへ戻す経路が弱い」と指摘し、5つの改善案（`to-pr` の verification matrix / code-review 実施確認 / `ready-for-agent` 品質 gate / 軽量 loop contract / `harness-feedback` の定期運用）と、非導入判断8項目の再評価を提起した。

grilling セッションで、この5提案は独立パッチではなく、**単一の contract 語彙**（[CONTEXT.md](../../CONTEXT.md) 参照）が入口（`ready-for-agent`）と出口（PR body の verification matrix）の両方に現れる1つの設計として閉じられることが分かった。一方で、issue が主題とする「評価結果を**次サイクルへ**戻す経路」そのものは、この設計では自動化されない。`harness-feedback` の auto モードは「現在アクティブなセッション自体をスキップする」仕様であり、`to-pr` の最後から同一セッション内でチェーン呼び出すことは技術的に噛み合わない。

## Decision

1. 共有 contract 語彙は目的 / AC / 非目標 / 検証方法 / 関連ファイル・入口 / 判断済み tradeoff の6項目（[CONTEXT.md](../../CONTEXT.md) の Contract 参照）。issue/ticket 本文が正本とし、`ready-for-agent` 化（`triage` 経由・`to-tickets` 経由の両方）の入口契約とする。issue/ticket が無い小規模作業（`grill-with-docs`/`to-spec`/`to-tickets` を省略するケース）では会話から抽出して埋め、議論されていない項目は「未記載」と明記する（省略しない）。
2. `to-pr` は PR body に contract をコピー埋め込みする。issueは `Fixes #N` で自動closeされた後も、レビュアーが PR 単体で contract を確認できるようにする。
3. `to-pr` の verification matrix（AC / 種別 / 実行コマンドまたは理由 / 結果 / 未確認理由、[CONTEXT.md](../../CONTEXT.md) 参照）に、既存のブラウザ検証4ラベル（確認済み/未確認/要人間確認/対象外(非UI)）を完全統合する（種別列で区別、1つの表）。非UI（CLI/API/infra）の AC について `to-pr` は新規に検証コマンドを実行せず、既に存在する証拠（tdd フェーズのテスト・lefthook実行・commit）を引用するだけに留める。これは旧 `active-evaluator` が持っていた AC verification の考え方の軽量復活であり、JSON schema や verdict gate は伴わない。
4. code-review 実施状況は PR body に記録するのみで、証拠が見当たらない場合も PR 作成をブロックしない（未実施ならその旨を正直に記す）。ADR-0004 の「4値 verdict gate 非導入」方針を維持する。
5. `ready-for-agent` の6項目最低条件は `runtime/skill-harness.md` に主記し、`docs/agents/triage-labels.md` からは参照リンクのみとする。`triage` / `to-tickets` は apm 経由の vendored skill で編集できないため、この最低条件は **skill 自体がゲートするのではなく、skill 実行後に運用者（エージェント自身）が確認する operator-enforced な doc-level discipline** とする（[ADR-0015](0015-add-tdd-commit-confirmation.md) の commit 確認ステップと同型）。
6. `harness-feedback` は `to-pr` から自動チェーン呼び出ししない。`to-pr` 自身が末尾に軽量インラインチェック（code-review をスキップしていないか・検証記録の無い AC を見落としていないか）を持つ。`to-pr` が PR body に書く Markdown は人間と `to-pr` 自身のインラインチェックのためのものであり、`harness-feedback` の artifact-driven enrichment（`contract.json` / `review.json` / `active-eval.json` のパース）はこの設計では発火しない——`harness-feedback` は引き続き別セッションでの transcript 分析としてのみ運用する。
7. 次の2件は今回のスコープ外として見送り、ADR-0004 を維持する（別issue化の余地はある）: `eval.yaml`/`tasks`（`to-pr`/`to-worktree`/`dogfood-to-issues` の最小eval復活）、実装チェックリストの新規追加（[ADR-0015](0015-add-tdd-commit-confirmation.md) で既に解消済みと判断）。`resolving-merge-conflicts` は後続の [ADR-0022](0022-align-mattpocock-v1-1-workflow.md) で導入に変更した。issueが挙げたその他6項目（4値verdict gate・evidence JSON・trace/video必須化・SessionStart自動GC hook・`grill-me`・`teach`）も引き続き非導入。

## Consequences

- この設計が閉じるのは「各サイクルを可読・監査可能にする」経路であり、issue本来の主題である「評価結果を次サイクルへ戻す経路」そのものの自動化ではない。次サイクルへの反映は、人間が PR body の記録を読むか、後日 `harness-feedback` を別セッションで実行するか、いずれも**運用者トリガーの手動プロセス**のまま残る。
- `to-pr` の `SKILL.md`（chezmoi local skill、編集可能）を書き換える。`triage` / `to-tickets` の `SKILL.md`（vendored、apm 管理）は変更しない。
- ADR-0004 の「4値 verdict gate / evidence JSON schema / eval harness は持ち込まない」という決定は維持される。今回追加する Markdown ベースの contract / verification matrix はいずれも JSON schema でも verdict gate でもないため、この決定と抵触しない。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md) / [ADR-0013](0013-to-pr-ready-for-review.md) / [ADR-0014](0014-triage-not-after-to-issues.md) / [ADR-0015](0015-add-tdd-commit-confirmation.md) / [skill-harness](../../runtime/skill-harness.md) / [triage-labels](../agents/triage-labels.md) / [CONTEXT.md](../../CONTEXT.md) / [issue #27](https://github.com/treflebonbon/dotfiles/issues/27)
