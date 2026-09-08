---
type: decision
title: to-pr の一時成果物を session scratchpad 解決 + 明示 fallback にする
description: ADR-0048 が繰延べた root cause（to-pr 等の一時成果物が working directory 外の /tmp に散らばる問題）に対し、env var 自動検出ではなく agent 自身のセッション context を都度参照する解決方式と、scratchpad が特定できない runtime 向けの明示 fallback を決定する。
tags: [adr, claude-code, codex, skills, scratchpad, tmp]
timestamp: 2026-09-08
status: accepted
---

# to-pr の一時成果物を session scratchpad 解決 + 明示 fallback にする

[ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) は `/tmp` を `additionalDirectories` へ恒久追加するのを見送り、root cause（`to-pr` 等が `/tmp` ではなく session scratchpad を使うようにする）を別 issue（[#241](https://github.com/treflebonbon/dotfiles/issues/241)）へ繰延べた。本 ADR はその決着。

`local-skills/to-pr/SKILL.md:97`（`TO_PR_EVIDENCE_DIR`）、同 `:246`（PR body 用 temp file）、`local-skills/to-pr/references/hierarchy-repair.md:7`（`HIERARCHY_REPAIR_RESULT`）の3箇所は `${TMPDIR:-/tmp}` 配下へ `mktemp` しており、nix-shell 環境ではこれが working directory 外の、session をまたいで残る path になる。session 終了で消える path を、`managed-chrome-owner` の所有権レコードのようなより寿命の長い state から参照し続けて壊れた実例を観測している。

## Decision

1. **対象は `to-pr` の上記3箇所に限定する。** `local-skills/dogfood-to-issues/` の裸 `mktemp -d`（`references/verification.md:22`、`references/mv3-extension.md:102`）はローカル runner の自己完結した検証出力であり、寿命の長い state から参照される経路ではないため対象外とする。
2. **scratchpad path の解決は env var の自動検出に頼らない。** 実測の結果、session scratchpad path は Claude Code の system prompt にテキストとしてのみ注入され、env var には出ない。Claude Code 公式ドキュメントにもこの injection が session 種別（interactive / `-p` / subagent / background job）を問わず一貫して行われるという記載はなく、未文書化・未確認である。既存の `${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}`（`local-skills/dogfood-to-issues/SKILL.md:25` 等）も実際には runtime が自動設定するのではなく、テストハーネス（`tests/dogfood-results.bats:170`）が明示 export しているだけと判明した。したがって `to-pr` は、agent が自分のセッション context を都度確認し、scratchpad path を認識できたらローカル変数へ明示代入してから使う、という手順を踏む。この方式は [ADR-0017](0017-element-pointing-feedback-in-tdd.md) が既に採用した原則（「ランタイム検出ロジックは導入しない — 実行中のエージェントは自身のランタイムの機能を把握している」）と同じ考え方であり、session 種別ごとの injection 有無を前提にしないため上記の未文書化な不確実性の影響を受けない。
3. **scratchpad path を特定できない場合は `${TMPDIR:-/tmp}` を明示的な fallback として維持する。** ADR-0048 の実測結論（Bash 経由の `/tmp` 読み書きは Working-Directory Read Fence の対象外で、動作自体は問題ない）と整合させる。fallback が発動したことは PR body 等の出力に明記し、無言で `/tmp` へ落とさない。
4. **実務手順（agent への具体的な指示文）は `runtime/skill-harness.md` に集約する。** 本 ADR は decision の記録に留め、手順そのものは `to-pr` 以外の local skill も将来使う横断規約として skill harness 側で保守する。

## Considered Options

- **env var の自動検出ロジックを書く**: `CLAUDE_SKILL_DIR`/`CODEX_SKILL_DIR` 相当の新しい env var を runtime が提供している前提で判定スクリプトを書く案。実測で両変数とも runtime 自動設定ではなくテストハーネスの明示 export に過ぎないと分かり、同種の前提を持ち込む価値がないため却下した。
- **session 種別ごとに分岐する**（interactive では scratchpad 前提、background job では `/tmp` 前提、など）: Claude Code 公式ドキュメントに injection の一貫性についての記載がなく、session 種別ごとの挙動を前提にする分岐は根拠を欠くため却下した。
- **scratchpad が特定できない場合は fail closed にする**: ADR-0048 の実測結論と矛盾する（`/tmp` 経由の動作自体は問題ないと確認済み）ため、`to-pr` 全体を止めるコストに見合わないと判断した。
- **`dogfood-to-issues` の裸 `mktemp -d` も同じ issue で直す**: 性質の異なる2種類の temp 生成（session をまたいで参照される成果物 vs 自己完結した検証実行の出力）を1つの変更に混ぜることになるため、スコープを `to-pr` に絞った。

## Consequences

`to-pr` は scratchpad path を得るための agent 向け手順を持つが、これは shell script による自動判定ではなく、agent 自身が自分の context を読んで判断する規約である。将来 Claude Code や Codex が scratchpad 相当の情報を公式に env var で公開するようになった場合、この判断は前提を変える必要がある。

`runtime/skill-harness.md` に手順を集約したことで `to-pr` 以外の local skill も同じ scratchpad 解決規約を再利用できるが、実際に他の skill へ適用するかどうかは本 ADR のスコープ外であり、必要になった時点で個別に対応する。

関連: [ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) / [ADR-0017](0017-element-pointing-feedback-in-tdd.md)
