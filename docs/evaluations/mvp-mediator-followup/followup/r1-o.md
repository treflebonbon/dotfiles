# O: 実行時の業務判定（dispatch前固定）

`r1-o.mjs` は API 非依存の純粋 Node 抽象モデルである。実アプリの Effect runtime、React、Atom は実装していない。

## 責務と状態

| 区分 | 所有者 | 内容 |
| --- | --- | --- |
| ユースケース | `cancelOrder` | 実行時 status の読取りと、発送済みを `BusinessError` で拒否する業務規則。 |
| 既存 binding の模擬 | `createBinding` | pending、結果採用、操作 ID。古い操作の結果を採用しない。 |
| 追加裁定 | `createMediator` | pending 中の重複要求の拒否だけ。追加状態は持たない。 |
| 検証専用 | 各テスト関数の fixture | status と結果イベント。採番・ログを本実装の状態としては増やさない。 |
| View 局所状態 | `createOrderRow` | tooltip の開閉と表示整形。イベントを Mediator に送るだけ。 |

実アプリでは既存の Effect 実行境界／binding が受理済み操作を実行する。`BusinessError` は想定内の型付き業務拒否であり、defect や中断をこれに変換しない。この抽象モデルは runtime を自作せず、依存も追加しない。

## 実行した assertion

`node docs/evaluations/mvp-mediator-followup/followup/r1-o.mjs`

結果: `passed 4 assertions`

`oxfmt --check r1-o.mjs r1-o.md` は成功した。`oxlint r1-o.mjs` は対象を走査する前に、既存 root 設定に現行版が未対応のルールがあり設定解析で停止した。`/tmp` からの再試行も親ディレクトリの既存 `oxlint.config.ts` が `oxlint` package を解決できず停止した。依存追加・設定変更はしていない。

| ケース | 実測結果 |
| --- | --- |
| 通常のキャンセル成功 | 成功結果を binding が採用し、pending を解除した。 |
| cached 表示後の発送競合 | View は cached `open` を表示したまま要求し、ユースケースが `ORDER_ALREADY_SHIPPED` を返した。 |
| 反復要求・古い結果 | pending 中の二重要求を拒否し、別試行後の旧成功・旧失敗をどちらも不採用にした。 |
| tooltip | 開閉しても binding の状態は変わらなかった。 |

## 固定基準

1. ○ 実行時の `shipped` をユースケースだけが拒否する assertion がある。Mediator と View は status を判定しない。
2. ○ pending 中の二重送信を抑止し、別 attempt と旧成功・旧失敗の除外を assertion で確認した。
3. ○ ユースケース、既存 binding、追加裁定、検証専用状態を上表で分離した。pending/result は binding が所有する。
4. ○ 既存 Effect 実行境界、型付き業務エラー、defect／中断との区別を記録した。自作 runtime・新規依存はない。
5. ○ 通常成功、発送競合、反復要求を別 assertion として実行した。実アプリ統合は未実行である。
6. ○ tooltip と整形は View 局所、操作判断は注文フロー Mediator 一つに置く。一覧取得・他フローを global FSM に集約しない。

## 記録

| 項目 | 内容 |
| --- | --- |
| Trace Understanding | OK |
| Trace Planning | OK |
| Trace Execution | OK |
| Trace Formatting | OK |
| Unclear Issue | なし |
| Cause | 実行時 status と cached status は異なるため、表示前判定だけでは発送競合を防げない。 |
| General Fix Rule | 業務規則はユースケースで実行時に検証し、UI は結果を表示する。UI 操作の重複抑止と結果採用は既存 binding の操作識別に従う。 |
| Discretionary fill-ins | tooltip 局所性も assertion 化した。 |
| Retries | 0 |
| 読んだ SKILL.md | `local-skills/mvp-mediator-architecture/SKILL.md` — SHA-256 `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb` |
| 読んだ reference | `local-skills/mvp-mediator-architecture/references/tanstack-effect.md` |
