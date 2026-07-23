---
type: decision
title: to-pr が最終 PR で直接の親 issue を reconciliation する
description: 全 child ticket が完了済みまたは最終 PR に covered な場合、to-pr が child と直接の親へ close keyword を付け、GitHub merge によって同時に完了させる
tags: [adr, skills, to-pr, github, issues, workflow]
timestamp: 2026-07-23
status: accepted
---

# to-pr が最終 PR で直接の親 issue を reconciliation する

## Context

`to-tickets` は親 issue を変更せず、`to-pr` は実装元の ticket だけを `Fixes #N` で PR 本文へ参照していた。issue #103 から child ticket #104 を実装した PR #105 では、merge によって #104 は自動 close された一方、全作業が完了した親 #103 は open のまま残った。

従来の `to-pr` は issue close と epic-branch reconciliation を対象外としていた。しかし、手動 close は今回のような漏れを再発させ、merge 後の GitHub Action は新しい常設 automation を必要とする。最終 PR の作成時点では Contract、Verification Matrix、native subissues を既に参照できるため、直接の親1階層に限れば、安全条件を PR 本文へ表現できる。

## Decision

1. `to-pr` は最終 PR の作成時に **Parent Reconciliation** を行う。判定を担うのは `to-pr` だが、実際に issue を close するのは `Fixes #N` を解釈する GitHub merge とする。PR が merge されなければ issue は閉じない。
2. **Ticket Hierarchy** の正本は GitHub native subissues とし、child ticket 本文の `Parent` は人間向けの写しとして照合する。native hierarchy を取得できない場合、または両者が不一致の場合は親を close 対象にしない。
3. child ticket の全 AC が PR の Contract に含まれ、Verification Matrix の行へ対応している状態を **Ticket Coverage** とする。`確認済み`、`未確認`、`要人間確認` など行の検証結果は coverage を左右せず、issue 番号や commit message の参照だけでも coverage とみなさない。
4. 直接の全 child ticket が既に close 済み、または同一の最終 PR で covered な場合に **親完了条件** が成立する。最終 PR の作成後から merge までは Ticket Hierarchy を凍結し、後から見つかった追加 scope は同じ親へ child ticket を加えず、別の親 issue として扱う。
5. 親完了条件を満たす場合、PR 本文は未完了かつ covered な全 child ticket と直接の親 issue の双方へ `Fixes #N` を付ける。既に closed の child ticket は close 対象から省く。grandparent 以上へは再帰しない。
6. PR 本文へ `## Parent Reconciliation` を常設し、`確認済み`、`未実施`、`対象なし` のいずれか、判定理由、close 対象を記録する。hierarchy または coverage を証明できない場合は親の `Fixes` を省き、理由を PR 本文と完了報告へ残すが、PR 作成自体は止めない。
7. push / PR 作成前の既存確認には、merge 時に close 対象となる child ticket と親 issue の番号を列挙し、他の外部公開操作と一度に確認する。親 close だけの追加確認は設けない。
8. merge で close された issue の state label はそのまま残す。Parent Reconciliation は close 漏れだけを扱い、label cleanup や post-merge automation は導入しない。

## Consequences

- 単一 ticket と複数 ticket のどちらでも、最終 PR が全 child ticket を covered していれば、merge 時に直接の親も同時に完了する。
- `to-pr` の責務は従来より広がるが、直接の親1階層と PR 本文の close keyword 生成に限定される。汎用 epic reconciler、再帰 close、merge 後の issue mutation は引き続き対象外とする。
- Ticket Coverage は Verification Matrix の完全性を使うが、検証結果を verdict gate にしない既存方針は維持される。
- PR 作成後の hierarchy 凍結が安全性の前提になる。scope が増えた場合は既存の親を変異させず、新しい親 issue へ分離する。
- hierarchy や coverage の判定失敗は親の誤 close を防ぐ方向へ倒れるが、PR 作成を妨げない。親が残る可能性は、PR 本文と完了報告の `未実施` 記録によって可視化される。

関連: [ADR-0014](0014-triage-not-after-to-issues.md) / [ADR-0016](0016-to-pr-shared-contract-vocabulary.md) / [ADR-0019](0019-builder-evaluator-cross-issue-autonomy.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #103](https://github.com/treflebonbon/dotfiles/issues/103) / [PR #105](https://github.com/treflebonbon/dotfiles/pull/105)
