# Scenario B: existing React/TanStack Query compound Context

## INPUT

- target: `local-skills/mvp-mediator-architecture/SKILL.md`
- SHA256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 実読参照: `local-skills/mvp-mediator-architecture/SKILL.md`、`local-skills/mvp-mediator-architecture/references/tanstack-effect.md`

## 変更提案

既存の compound Context と TanStack Query の購読・取得をそのまま使う。合計表示の View で既存 formatter を呼び出し、同じ View 内に help tooltip の開閉状態を置く。tooltip の開閉は表示だけを変え、送信、取消、キャッシュ、他操作の可否には接続しない。

## 凍結基準

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 既存の React/TanStack Query を維持する。Effect、Atom、MVP への移行は提案しない。 |
| 2 | ○ | 表示整形と局所 tooltip だけで足りるため、Mediator、reducer、global state、Model を追加しない。 |
| 3 | ○ | compound Context の複数 consumer は維持する。単一 connector や中継専用層を強制しない。 |
| 4 | ○ | 合計は既存 formatter を再利用し、tooltip は当該 View の局所状態として扱う。 |
| 5 | ○ | 業務規則、送信、取消、キャッシュ更新の所有者は変更しない。 |
| 6 | ○ | 合計が既存 formatter の出力になること、tooltip の開閉が当該表示だけを変えることを確認対象にする。アプリ試験の成功は主張しない。 |

## YOUR Trace 4 phase

| phase | 判定 | 記録 |
| --- | --- | --- |
| 1. Input | OK | target の SHA256 と対象スキル、React/TanStack 向け参照を確認した。 |
| 2. Scope | OK | 変更は既存 View の合計表示と、他操作に影響しない tooltip に限定される。 |
| 3. Ownership | OK | 複数 Context consumer、TanStack Query、業務・送信の所有者を維持できる。新しい裁定はない。 |
| 4. Verification | OK | formatter 出力と tooltip の局所開閉を検査対象にし、未実行のアプリ試験を成功として扱わない。 |

`allOK`

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 formatter の import 元と tooltip 実装は未特定 | この課題はアプリ実装を含まず、対象ソースも未読 | 実装時に既存 formatter と既存 tooltip primitive を検索して再利用し、見つからない場合も View 局所の最小実装に留める。 |

## 任意補完

tooltip がキーボード操作と閉じる操作を持つ既存 primitive ならそれを使う。既存 primitive がなければ、実装前にアクセシブルな最小 UI の選択を確認する。

## YOUR Retries

- 判断やり直し数: 0
- 理由: 小修正として既存設計を維持する明示的な規約と、tooltip を局所状態として許可する規約が一致するため。
