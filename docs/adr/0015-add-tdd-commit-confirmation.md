---
type: decision
title: tdd の各 slice ごとの commit 確認ステップを明記し、implement 非導入の根拠を upstream issue で補強する（ADR-0004 を補強）
description: issue #25 の調査で、upstream implement は README 非掲載（2026-07-06 時点でも継続）に加え、commit/review 省略の頻発・install 分類の混乱という信頼性バグを抱えることが判明。plugin.json 欠落とダングリング /review 参照は 2026-07-01 の upstream commit で既に修正済みと判明したため根拠から除外し、pin した revision に基づき訂正した。ADR-0004 の非導入判断を維持しつつ、code-review が commit 済みの diff（...HEAD 三点差分）しか見ないという制約に合わせ、to-pr が前提とする「tdd cycle で commit 済み」を実際に担保する明示的な commit 確認ステップを tdd の各 slice ごとに追加する
tags: [adr, skills, mattpocock, workflow, implement, to-pr]
timestamp: 2026-07-07
---

# tdd の各 slice ごとの commit 確認ステップを明記し、implement 非導入の根拠を upstream issue で補強する（ADR-0004 を補強）

## Status

Accepted (2026-07-07)

## Context

[issue #25](https://github.com/treflebonbon/dotfiles/issues/25) は「upstream mattpocock/skills の `implement` が、この repo の `tdd` → `code-review` の起点になるか」を確認するために起票された。[ADR-0004](0004-fill-mattpocock-gaps.md) は既に `implement` を「README 非掲載の unlisted skill」として非導入と決定していたが、その根拠を upstream で再検証したところ、以下が判明した。

**upstream `implement/SKILL.md`（`skills/engineering/implement/`）の内容**: `/tdd` を内部で駆動 → typecheck を定期実行、単体テスト/全テストスイートを実行 → `/review` を実行 → 現在のブランチに commit、という5行のオーケストレーター。router skill `ask-matt` はこれを main flow の中核として扱っている。

**upstream issue tracker（GitHub 上はすべて OPEN——ただし下記の通り一部は既に code fix 済みで stale）で確認した事実**。upstream `main`（[`16a2a5cd`](https://github.com/mattpocock/skills/commit/16a2a5cd00b4)、2026-07-06 時点で pin）を実際に読んで検証した:

- **[#371](https://github.com/mattpocock/skills/issues/371)** — `implement` が `.claude-plugin/plugin.json` に掲載されていない、という報告。**2026-07-06 時点で修正済み**: commit [`b3b1d8d1`](https://github.com/mattpocock/skills/commit/b3b1d8d1)（2026-07-01、"chore: add implement skill to public plugin set"）で `plugin.json` に追加され、`npx skills add` 経由でも `/implement` はインストール可能になっている。issue 自体は GitHub 上まだ OPEN だが（`README.md` 未掲載は残っているため——下記参照）、「manifest から欠落してインストール不可能」という核心の指摘はもはや事実ではない。
- **`README.md`（`skills/engineering/README.md` および root `README.md` の両方、pin した revision で確認）に `implement` は現在も掲載されていない**。#371 が修正された後もこの状態は変わっておらず、「upstream の promoted skill 一覧に `implement` は入っていない」という ADR-0004 のもともとの根拠は今も成立している。
- **[#399](https://github.com/mattpocock/skills/issues/399)** — `/implement` を使っても、エージェントが最終2ステップ（`/review` 実行と commit）を**頻繁に省略する**という実運用バグ報告。pin した revision の `implement/SKILL.md` を見ても、この省略を防ぐための文言追加（issue のコメントが提案する "MUST proceed without silent truncation" 等）は入っておらず、**未修正のまま**。この repo が抱えていた「commit 責務の空白」と同型の症状が、`implement` を導入した場合でも解消されていない。
- **[#350](https://github.com/mattpocock/skills/issues/350)** — `implement/SKILL.md` が出荷されていない `/review` を指すダングリング参照だった、という報告。**2026-07-06 時点で修正済み**: commit [`14c13c5b`](https://github.com/mattpocock/skills/commit/14c13c5b)（2026-07-01、"Rename review skill to code-review and promote to engineering... Point /implement and its docs at /code-review"）で `/code-review` を指すよう修正されている。pin した revision で直接確認済み——現在の `implement/SKILL.md` は "Once done, use /code-review to review the work." と書かれている。この論点は根拠から除外する。
- **[#386](https://github.com/mattpocock/skills/issues/386)** — インストール時のカテゴリ分類で `/implement` が "other" に紛れ込み、メインフローの一部か判然としないとの指摘。ファイル差分で検証できる性質の報告ではないが、対抗する証拠も無く、still OPEN。

**教訓**: upstream issue の本文だけを根拠にし、実際のファイル内容を revision 指定で確認しなかったため、当初のドラフトは #371 と #350 を「現在も有効な根拠」として引用してしまった（実際には両方とも本 issue 起票の6日前、2026-07-01 に修正済みだった）。以降、upstream の動的な状態を根拠にする場合は commit SHA を pin し、issue の open/closed だけでなく実ファイルを直接確認する。

一方、この repo独自の調査で、`to-pr`（`local-skills/to-pr/SKILL.md`）が「a `/tdd` cycle stops at commit-to-branch」「running tests... is assumed done by the implementation work (e.g. the `/tdd` cycle) that precedes this skill」と、commit と test 実行が**既に完了している前提**で書かれている一方、この repo の `tdd` skill（apm 経由で upstream から vendor されたそのままのファイル）には commit の手順が一切無いことが分かった。

ただし `implement` が担っていた3つの責務のうち、**typecheck/test の定期実行は既にこの repo で構造的にカバーされている**: `lefthook.yml` の pre-commit hook が `typecheck`（`bunx tsc --noEmit`）・`oxlint`・`shellcheck` 等を commit のたびに強制実行し、test 実行自体は `tdd` の red-green loop に内在する（テストを書いて red→green を確認しなければ loop が成立しない）。commit が per-slice で起きる前提（本 ADR の Decision 2）にすれば、`implement` が言う「typecheck を定期実行」は lefthook が commit ごとに担うことで自動的に満たされ、追加の doc 指示は不要。**この repo のどの skill にも明示的に残っていないのは「commit する」責務だけ**であり、これが本 ADR が実際に埋める空白である。

さらに、`code-review`（この repo の vendor 済みコピー、および upstream 本体の両方で確認——repo 固有の分岐ではない）は `git diff <fixed-point>...HEAD` という三点差分で **commit 済みの履歴のみ** を review 対象にし、empty diff は明示的に fail する（`code-review/SKILL.md` 手順1）。つまり `code-review` が動くためには、それより前に何らかの commit が既に存在していなければならない。当初の草案は「`code-review` の後に commit する」という順序で書いていたが、これは `code-review` 自身の前提と矛盾する——正しくは、**`tdd` の各 green slice ごとに commit し**、その積み上がった commit 履歴を `code-review` が review する、という順序である。`implement` が末尾に置く「commit」は、この per-slice commit とは別に、レビュー起因の修正など残った変更を最後に取りこぼさないための締めくくりだと解釈するのが upstream の記述と整合する。

## Decision

1. **`implement` 非導入は維持する**（ADR-0004 の決定を変更しない）。主たる根拠は **#399 の commit/review 省略バグ**（pin した revision で今も未修正——`implement` を仮に導入しても、この repo が抱える「commit 責務の空白」と同種の問題が upstream 実運用でも解消されない）と、#386 の install 分類の混乱（still OPEN）。「README 非掲載」は補助的な根拠にとどめる: これは #371 の未修正の残り半分（`plugin.json` は 2026-07-01 に修正されたが `README.md` は据え置き）であり、upstream が `implement` を非推奨とする恒久的な意思表示ではなく、修正待ちの過渡的な状態にすぎない——upstream が README を追いつかせた瞬間に消える根拠なので、これ単体には重みを置かない。#399 は upstream の実運用挙動そのものについての報告であり、README 掲載状況に左右されないため、この決定の主軸として扱う。
2. **doc 層のみで commit 確認ステップを明記する**。`tdd` の各 green slice ごとに、ユーザーに commit してよいか確認してから commit する（`code-review` が review する commit 履歴を積み上げる）。`code-review` が完了しブロッキングな指摘が無いことを確認した後は、修正差分についても同様に確認のうえ commit してから `to-pr` へ進む。この手順を `CLAUDE.md` の設計→実装ワークフロー節と `runtime/skill-harness.md` に追記する。これにより `to-pr` の「tdd cycle で commit 済み」という前提と、`code-review` が commit 済みの diff しか見ないという制約の両方が、暗黙の期待ではなく明示された手順に基づくようになる。
3. **新規 skill は作らず、vendor 済み `tdd`/`code-review` の `SKILL.md` も編集しない**。前者はほぼ一行の指示に対して skill 一つを新設するには過剰（over-engineering）であり、後者は次回 `apm install` で上書きされ non-durable。
4. commit を機械的に強制するゲート（#399 のコメントが提案する pytest hook 的な仕組み）は導入しない。Claude Code 自体が「明示依頼なしに commit しない」という基本方針を持つため、doc に確認ステップを明記するだけで十分機能する。他ランタイム（Codex / Antigravity）はこの基本方針を共有しない可能性があるため、doc への明記自体が実質的なガードになる。

## Consequences

- `to-pr` の「commit 済み」という前提が、doc 上どこにも書かれていない暗黙の期待から、明示された手順の帰結に変わる。
- Claude Code 以外のランタイムで実行した場合でも、commit 前にユーザー確認を求める手順が doc 上明確になる。
- upstream は既に `implement` の manifest 欠落（#371）とダングリング参照（#350）を修正済み（2026-07-01）——upstream が `implement` を積極的にメンテしている証拠でもある。README への掲載と #399 の commit/review 省略バグが解消された場合、非導入判断自体を再検討してよい。
- upstream の動的な状態（issue の open/closed、ファイル内容）は変わり続けるため、この ADR の evidence は pin した revision（`16a2a5cd`, 2026-07-06）時点のスナップショットである。将来これを参照する際は、再度現在の upstream 状態を確認すること——古い issue 本文だけを信用しない。
- issue #25 は本 ADR で解消: `implement` は起点にならない（README 非掲載が今も継続し、commit/review 省略という実運用バグも upstream 側で未解決のため）。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md)（`implement` 非導入の原決定）/ [ADR-0014](0014-triage-not-after-to-issues.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #25](https://github.com/treflebonbon/dotfiles/issues/25) / upstream [mattpocock/skills#371](https://github.com/mattpocock/skills/issues/371), [#399](https://github.com/mattpocock/skills/issues/399), [#350](https://github.com/mattpocock/skills/issues/350), [#386](https://github.com/mattpocock/skills/issues/386)
