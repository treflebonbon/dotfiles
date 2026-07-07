---
type: decision
title: tdd の各 slice ごとの commit 確認ステップを明記し、implement 非導入の根拠を upstream issue で補強する（ADR-0004 を補強）
description: issue #25 の調査で、upstream implement は README/plugin.json 非掲載に加え、確認済みの信頼性バグ（存在しない /review 参照、commit/review 省略の頻発、install 分類の混乱）を抱えることが判明。ADR-0004 の非導入判断を維持しつつ、code-review が commit 済みの diff（...HEAD 三点差分）しか見ないという制約に合わせ、to-pr が前提とする「tdd cycle で commit 済み」を実際に担保する明示的な commit 確認ステップを tdd の各 slice ごとに追加する
tags: [adr, skills, mattpocock, workflow, implement, to-pr]
timestamp: 2026-07-07
---

# tdd の各 slice ごとの commit 確認ステップを明記し、implement 非導入の根拠を upstream issue で補強する（ADR-0004 を補強）

## Status

Accepted (2026-07-07)

## Context

[issue #25](https://github.com/treflebonbon/dotfiles/issues/25) は「upstream mattpocock/skills の `implement` が、この repo の `tdd` → `code-review` の起点になるか」を確認するために起票された。[ADR-0004](0004-fill-mattpocock-gaps.md) は既に `implement` を「README 非掲載の unlisted skill」として非導入と決定していたが、その根拠を upstream で再検証したところ、以下が判明した。

**upstream `implement/SKILL.md`（`skills/engineering/implement/`）の内容**: `/tdd` を内部で駆動 → typecheck を定期実行、単体テスト/全テストスイートを実行 → `/review` を実行 → 現在のブランチに commit、という5行のオーケストレーター。router skill `ask-matt` はこれを main flow の中核として扱っている。

**upstream issue tracker（すべて OPEN）で確認した事実**:

- **[#371](https://github.com/mattpocock/skills/issues/371)** — `implement` は `main` に存在するが `README.md` にも `.claude-plugin/plugin.json` にも掲載されていない。issue 作成者の調査によれば、これは意図的な非推奨ではなく、`implement` 追加コミットが manifest 更新を伴わなかった**計上漏れ**。`npx skills add` 経由の一般ユーザーには `/implement` 自体が存在しない。
- **[#399](https://github.com/mattpocock/skills/issues/399)** — `/implement` を使っても、エージェントが最終2ステップ（`/review` 実行と commit）を**頻繁に省略する**という実運用バグ報告。この repo が抱えていた「commit 責務の空白」と同型の症状が、`implement` を導入した場合でも解消されていない。
- **[#350](https://github.com/mattpocock/skills/issues/350)** — `implement/SKILL.md` が指す `/review` は `skills/in-progress/` にあり出荷されていない、ダングリング参照。提案されている修正は「代わりに `/code-review` を使う」——この repo が独自に `code-review` へ向けている選択と一致する。
- **[#386](https://github.com/mattpocock/skills/issues/386)** — インストール時のカテゴリ分類で `/implement` が "other" に紛れ込み、メインフローの一部か判然としないとの指摘。

一方、この repo独自の調査で、`to-pr`（`local-skills/to-pr/SKILL.md`）が「a `/tdd` cycle stops at commit-to-branch」「running tests... is assumed done by the implementation work (e.g. the `/tdd` cycle) that precedes this skill」と、commit と test 実行が**既に完了している前提**で書かれている一方、この repo の `tdd` skill（apm 経由で upstream から vendor されたそのままのファイル）には commit の手順が一切無いことが分かった。

ただし `implement` が担っていた3つの責務のうち、**typecheck/test の定期実行は既にこの repo で構造的にカバーされている**: `lefthook.yml` の pre-commit hook が `typecheck`（`bunx tsc --noEmit`）・`oxlint`・`shellcheck` 等を commit のたびに強制実行し、test 実行自体は `tdd` の red-green loop に内在する（テストを書いて red→green を確認しなければ loop が成立しない）。commit が per-slice で起きる前提（本 ADR の Decision 2）にすれば、`implement` が言う「typecheck を定期実行」は lefthook が commit ごとに担うことで自動的に満たされ、追加の doc 指示は不要。**この repo のどの skill にも明示的に残っていないのは「commit する」責務だけ**であり、これが本 ADR が実際に埋める空白である。

さらに、`code-review`（この repo の vendor 済みコピー、および upstream 本体の両方で確認——repo 固有の分岐ではない）は `git diff <fixed-point>...HEAD` という三点差分で **commit 済みの履歴のみ** を review 対象にし、empty diff は明示的に fail する（`code-review/SKILL.md` 手順1）。つまり `code-review` が動くためには、それより前に何らかの commit が既に存在していなければならない。当初の草案は「`code-review` の後に commit する」という順序で書いていたが、これは `code-review` 自身の前提と矛盾する——正しくは、**`tdd` の各 green slice ごとに commit し**、その積み上がった commit 履歴を `code-review` が review する、という順序である。`implement` が末尾に置く「commit」は、この per-slice commit とは別に、レビュー起因の修正など残った変更を最後に取りこぼさないための締めくくりだと解釈するのが upstream の記述と整合する。

## Decision

1. **`implement` 非導入は維持する**（ADR-0004 の決定を変更しない）。根拠を「README 非掲載」だけでなく、上記 upstream issue（#371 / #399 / #350 / #386）で確認された **実際の信頼性バグ** に基づくものへ補強する。`implement` を仮に導入しても、commit/review 省略という同種の問題が upstream 実運用でも解消されていない（#399）ため、この repo が抱える空白の解決策にはならない。
2. **doc 層のみで commit 確認ステップを明記する**。`tdd` の各 green slice ごとに、ユーザーに commit してよいか確認してから commit する（`code-review` が review する commit 履歴を積み上げる）。`code-review` が完了しブロッキングな指摘が無いことを確認した後は、修正差分についても同様に確認のうえ commit してから `to-pr` へ進む。この手順を `CLAUDE.md` の設計→実装ワークフロー節と `runtime/skill-harness.md` に追記する。これにより `to-pr` の「tdd cycle で commit 済み」という前提と、`code-review` が commit 済みの diff しか見ないという制約の両方が、暗黙の期待ではなく明示された手順に基づくようになる。
3. **新規 skill は作らず、vendor 済み `tdd`/`code-review` の `SKILL.md` も編集しない**。前者はほぼ一行の指示に対して skill 一つを新設するには過剰（over-engineering）であり、後者は次回 `apm install` で上書きされ non-durable。
4. commit を機械的に強制するゲート（#399 のコメントが提案する pytest hook 的な仕組み）は導入しない。Claude Code 自体が「明示依頼なしに commit しない」という基本方針を持つため、doc に確認ステップを明記するだけで十分機能する。他ランタイム（Codex / Antigravity）はこの基本方針を共有しない可能性があるため、doc への明記自体が実質的なガードになる。

## Consequences

- `to-pr` の「commit 済み」という前提が、doc 上どこにも書かれていない暗黙の期待から、明示された手順の帰結に変わる。
- Claude Code 以外のランタイムで実行した場合でも、commit 前にユーザー確認を求める手順が doc 上明確になる。
- upstream が `implement` の manifest 計上漏れ（#371）とダングリング参照（#350）を修正し、commit/review 省略バグ（#399）を解消した場合、この ADR の evidence は古くなる。その場合は非導入判断自体を再検討してよい。
- issue #25 は本 ADR で解消: `implement` は起点にならない（意図的な非推奨ではなく計上漏れだが、独立した信頼性バグにより採用の根拠はない）。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md)（`implement` 非導入の原決定）/ [ADR-0014](0014-triage-not-after-to-issues.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #25](https://github.com/treflebonbon/dotfiles/issues/25) / upstream [mattpocock/skills#371](https://github.com/mattpocock/skills/issues/371), [#399](https://github.com/mattpocock/skills/issues/399), [#350](https://github.com/mattpocock/skills/issues/350), [#386](https://github.com/mattpocock/skills/issues/386)
