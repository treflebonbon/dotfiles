---
type: decision
title: to-pr が最終 PR で直接の親 issue を reconciliation する
description: body-only hierarchy を安全に native subissues へ修復し、全 child ticket が完了済みまたは最終 PR に covered な場合に child と直接の親を GitHub merge で同時に完了させる
tags: [adr, skills, to-pr, github, issues, workflow]
timestamp: 2026-07-23
status: accepted
---

# to-pr が最終 PR で直接の親 issue を reconciliation する

## Context

`to-tickets` は親 issue を変更せず、`to-pr` は実装元の ticket だけを `Fixes #N` で PR 本文へ参照していた。issue #103 から child ticket #104 を実装した PR #105 では、merge によって #104 は自動 close された一方、全作業が完了した親 #103 は open のまま残った。

従来の `to-pr` は issue close と epic-branch reconciliation を対象外としていた。しかし、手動 close は今回のような漏れを再発させ、merge 後の GitHub Action は新しい常設 automation を必要とする。最終 PR の作成時点では Contract、Verification Matrix、native subissues を既に参照できるため、直接の親1階層に限れば、安全条件を PR 本文へ表現できる。

その後、`aiakos-inc/helpmei#1` と child #2〜#15 では、各 child 本文が `## Parent` で #1 を宣言した一方、native subissue relationship が作られなかった。native hierarchy だけを見る `to-pr` は各 child を単独 ticket と判断し、全 child が PR で close された後も親 #1 が残った。本文を reconciliation の第二の正本に戻すと誤 close の危険があるため、本文の宣言を検証済み native edge へ変換してから既存判定へ合流させる必要がある。

## Decision

1. `to-pr` は最終 PR の作成時に **Parent Reconciliation** を行う。判定を担うのは `to-pr` だが、実際に issue を close するのは `Fixes #N` を解釈する GitHub merge とする。PR が merge されなければ issue は閉じない。
2. **Ticket Hierarchy** の正本は GitHub native subissues とする。child ticket 本文の `Parent` は人間向けの写しであり、native hierarchy との照合と **Hierarchy Repair** の入力にだけ使う。本文から直接 parent completion を判定しない。
3. linked issue に native parent がなく、bounded `## Parent` section が現在の repository 内の単一 parent issue を明示する場合、Parent Reconciliation より前に Hierarchy Repair を行う。repository の全 Issue を GraphQL cursor pagination で取得し（PR を除外）、同じ parent を単一参照する open / closed の全 direct-child candidates を列挙する。parent と全 candidates を再読出しし、parent の存在、current linked issue の包含、各 body 宣言の一意性、各 native parent が未設定または対象 parent であることを mutation 前に確認する。
4. preflight 成功後、全 direct-child candidates の missing edge を `replaceParent: false` で追加する。追加の成功・失敗後に各 child の `parent` と parent の `subIssues` を両側から再検証し、全 candidate が一致したときだけ修復済み native hierarchy として既存の Parent Reconciliation へ渡す。current child だけの追加、既存 parent の削除・reparent、grandparent への再帰は行わない。
5. body Parent の複数・不正・取得不能、別 native parent との競合、pagination・追加・再検証の失敗では Parent Reconciliation を `未実施` とする。部分成功も失敗として親の `Fixes` を省き、失敗した Issue 番号と理由を PR 本文・完了報告へ残すが、PR 作成自体は続ける。本文にも native hierarchy にも Parent 宣言がない単独 ticket は従来どおり `対象なし` とする。
6. child ticket の全 AC が PR の Contract に含まれ、Verification Matrix の行へ対応している状態を **Ticket Coverage** とする。`確認済み`、`未確認`、`要人間確認` など行の検証結果は coverage を左右せず、issue 番号や commit message の参照だけでも coverage とみなさない。
7. 直接の全 child ticket が既に close 済み、または同一の最終 PR で covered な場合に **親完了条件** が成立する。最終 PR の作成後から merge までは Ticket Hierarchy を凍結し、後から見つかった追加 scope は同じ親へ child ticket を加えず、別の親 issue として扱う。
8. 親完了条件を満たす場合、PR 本文は未完了かつ covered な全 child ticket と直接の親 issue の双方へ `Fixes #N` を付ける。既に closed の child ticket は close 対象から省く。grandparent 以上へは再帰しない。
9. PR 本文へ `## Parent Reconciliation` を常設し、`確認済み`、`未実施`、`対象なし` のいずれか、判定理由、close 対象を記録する。hierarchy または coverage を証明できない場合は親の `Fixes` を省き、理由を PR 本文と完了報告へ残すが、PR 作成自体は止めない。
10. `to-pr` の明示呼出しまたは AFK 完了許可は、本文で宣言済みの missing edge の追加だけを routine publication repair として承認する。Issue の body、state、label、assignee、既存 parent は変更しない。merge 時に close 対象となる child ticket と親 issue の番号は PR 本文と完了報告に列挙し、親 close や repair だけの追加確認は設けない。
11. merge で close された issue の state label はそのまま残す。Parent Reconciliation は close 漏れだけを扱い、label cleanup や post-merge automation は導入しない。

## Consequences

- body-only hierarchy でも最初の child PR が全 sibling を一括修復するため、未処理 sibling を native hierarchy の外へ残したまま親完了条件を成立させない。
- 単一 ticket と複数 ticket のどちらでも、最終 PR が全 child ticket を covered していれば、merge 時に直接の親も同時に完了する。
- `to-pr` の責務は missing native edge の追加まで広がるが、本文で宣言済みの直接の親1階層に限定される。汎用 migration、関係削除、reparent、再帰 close、merge 後の issue mutation は引き続き対象外とする。
- Ticket Coverage は Verification Matrix の完全性を使うが、検証結果を verdict gate にしない既存方針は維持される。
- PR 作成後の hierarchy 凍結が安全性の前提になる。scope が増えた場合は既存の親を変異させず、新しい親 issue へ分離する。
- repair、hierarchy、coverage の判定失敗は親の誤 close を防ぐ方向へ倒れるが、PR 作成を妨げない。GitHub mutation は複数 edge を atomic に追加しないため部分成功は残り得るが、両側の再検証が揃うまでは親を close 対象にしない。

関連: [ADR-0014](0014-triage-not-after-to-issues.md) / [ADR-0016](0016-to-pr-shared-contract-vocabulary.md) / [ADR-0019](0019-builder-evaluator-cross-issue-autonomy.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #103](https://github.com/treflebonbon/dotfiles/issues/103) / [PR #105](https://github.com/treflebonbon/dotfiles/pull/105) / [issue #181](https://github.com/treflebonbon/dotfiles/issues/181)
