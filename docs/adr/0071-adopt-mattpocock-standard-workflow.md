---
type: decision
title: Matt Pocock 標準へ移行して類似ローカル skill を撤去する
description: implement-spec・pr・retro を公式セットから導入し、独自の一括実装・PR公開・逸脱分析の保守を終了する
tags: [adr, skills, mattpocock, workflow, apm]
timestamp: 2026-09-30
status: accepted
---

# Matt Pocock 標準へ移行して類似ローカル skill を撤去する

独自機能の維持より上流への準拠と保守削減を優先し、`batch-implement`・`to-pr`・`harness-feedback` を撤去する。ユーザーは各選択肢の推奨案をすべて選び、Matt Pocock 準拠を明示した。上流本文は fork せず、既存の安全規則に必要な差分と短い PR 公開手順だけを指示層へ残す。

## 決定

- `implement-spec` を使い、ticket graph の実行可能な frontier を並列に実装して、一つの仕様を一つの Integration Branch／PR へ集約する。GitHub 運用では最初の集約後に draft PR を作り、全 ticket の実装・レビュー・修正後に ready 化する。chain ごとの順次実装と複数 PR は廃止する。
- `pr` の標準本文（変更概要・変更前後の証拠・merge の危険性）を採用する。PR 公開を依頼された場合は `git-push-topic` と `gh pr create/edit` を使い、実際の default branch を base にする。独自の Contract／AC 別 Verification Matrix、Hierarchy Repair／Parent Reconciliation、自動画像添付は廃止する。実装の検証と根拠の提示は維持する。
- `retro` の標準の振り返りを採用する。指定されたセッション、指定がなければ現在のセッションから環境改善を提案する。独自の前回ログ選択・逸脱分類・重大度判定は引き継がない。
- 公式 managed full set を APM の単一 exact pin で更新する。候補は [上流 commit `d81f3a1`](https://github.com/mattpocock/skills/commit/d81f3a183412e71a5b1e84ca21bc1a35eea03a60)。公式セットは [plugin manifest](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/.claude-plugin/plugin.json) の27 skillに揃え、上流で削除された `resolving-merge-conflicts` は独自に保持しない。用語集は `CONTEXT.md` から `GLOSSARY.md` へ移行する。
- force push 禁止、default branch への直接 push・PR merge・issue の直接 close・破壊的 reset・ファイル／worktree 削除の確認境界は既存規則に従う。上流の reset／cleanup 指示を承認の代用にしない。未コミット変更と失敗した作業の保護は維持する。

## 実装時の受入条件

APM manifest／native lock、managed set の保持・撤去、AGENTS.md／CLAUDE.md、runtime 文書、domain 設定、関連テストを同じ更新単位で整合させる。撤去する3スキルは同梱 script／reference を含めて source から取り除き、`localSkills.retired` へ登録する。廃止した機能の helper・テスト・現行文書の参照も整理し、過去の ADR／調査記録は履歴として保持する。旧名の互換 alias や代替ローカル skill は作らない。

[既存の更新ゲート](0042-mattpocock-managed-set-update-gate.md)を27 skillと新しい標準契約に合わせて更新し、隔離環境の APM install／frozen no-rewrite／audit、両配布先の discovery、関連テスト・全 Bats、chezmoi dry-run を通す。導入先の live source／HOME への反映は受入・merge 後の配備境界で行う。

本決定は ADR-0040／0041 の25-skill membership と旧実装フロー、ADR-0016／0027／0052 の独自 PR 出口契約、ADR-0023 の `harness-feedback` 評価手順を置き換える。各記録は当時の判断として保持する。

上流の根拠: [implement-spec](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/implement-spec/SKILL.md)、[pr](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/pr/SKILL.md)、[retro](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/retro/SKILL.md)、[domain-modeling](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/domain-modeling/SKILL.md)。

## 検証記録

APM 0.32.0 の空の隔離 cwd／HOME で実 manifest から native lock を生成し、frozen install 前後の SHA-256 不変と audit 10/10 を確認した。Matt の selected content hash は `sha256:3228058108c4d2b45044dc0cc2ac0823890dee5bf885e3114297685bb04592c2`。他19依存の selected content hash はすべて不変で、shadcn `db2db460` → `08ab84f7`、Orca `computer-use`／`orchestration` `31012aeb` → `59b746ff` だけが revision-only で進んだ。APM の organization policy は隔離 cwd に Git remote がないため warning 付きで skip し、baseline の10項目は成功した。

配布・撤去テストでは、旧3ローカルスキルと `resolving-merge-conflicts` が共有ハブ・Claude・旧 Codex native／app から撤去され、再実行でも戻らず、未知の共有ハブ entry と残すローカル skill が保持されることを確認した。新しい3スキルの契約を欠く候補は更新ゲートで reject する。

live 配備は受入・merge 後に残す。
