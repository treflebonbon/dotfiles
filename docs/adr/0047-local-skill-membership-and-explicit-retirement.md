---
type: decision
title: ローカル skill の配備対象をソースから導出し、撤去対象は明示する
description: 配備・保持一覧の手同期をなくし、配備履歴を保存せずに旧名の撤去を扱う
tags: [adr, chezmoi, skills, deployment]
timestamp: 2026-09-07
status: accepted
---

# ローカル skill の配備対象をソースから導出し、撤去対象は明示する

ローカル skill の配備一覧と cleanup の保持一覧は同じ10件を別々に持ち、追加・改名時の手同期を要求している。候補01「Skill 配備の所有権」の設計対話で、次の方針を採用した。

## Decision

- 集約の対象はローカル skill とする。APM の配布所有権、Matt managed set の保持一覧、独立した採用ゲートは維持する。
- `local-skills/<name>/SKILL.md` の配置を配備対象の宣言とし、配備対象と保持対象を同じソースから導出する。配備前の作業途中 skill はこの配置の外に置く。
- 撤去・改名時は、旧名を「ローカル skill 撤去対象」としてソース側で明示する。共有ハブと Claude の両配備先から旧名を除き、配備履歴による自動判定は導入しない。
- skill 処理による変更の開始前に、全ソースの `SKILL.md` 欠損や APM との名前衝突を検査する。ローカル skill による APM payload の暗黙の上書きは拒否する。
- 配備先単位で旧内容を保護して置換する。途中失敗で成功済みの更新は戻さず、再実行で揃える。全 skill・全配備先をまとめて復旧する仕組みは導入しない。
- chezmoi の cleanup → APM install / prune → ローカル skill 配備の順序と、変更検知による再実行の連動を維持する。APM lock の生成・採用手順は変更しない。

## Trade-offs

配備対象の明示一覧はソースとの二重管理を残すため採用しない。一方、撤去は現在のソースだけから旧名を復元できないため、明示した旧名を残す。配備履歴の保存による撤去の自動化より、追加の状態管理・移行・破損時の扱いを持たないことを優先する。新しい名前の追加に登録は不要だが、撤去・改名には旧名の宣言が必要になる。

全体の復旧処理を省くため、途中失敗時には skill 間や配備先間で新旧が混在し得る。事前検査で判明する入力不備は変更前に拒否し、実行中の失敗は配備先単位の保護と再実行で扱う。

関連: [CONTEXT.md](../../CONTEXT.md) / [ADR-0040](0040-adopt-mattpocock-v1-2-3-full-set.md) / [ADR-0042](0042-mattpocock-managed-set-update-gate.md) / [skill-harness](../../runtime/skill-harness.md)
