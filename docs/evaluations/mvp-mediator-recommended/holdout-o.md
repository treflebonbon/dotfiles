# Holdout O: 実行時の業務判定

対象スキル: `local-skills/mvp-mediator-architecture/SKILL.md`

SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`

読んだ reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`

## 責務

- Model／ユースケース: `cancelOrder` が実行時の最新 status を読み、`shipped` を `business-error`（`ORDER_ALREADY_SHIPPED`）として返す。cached status は使わない。
- 既存 binding の模擬: `pendingByOrder`、`resultByOrder`、operation ID を所有する。通常の pending/result と旧応答の除外はここで共用する。
- Mediator: `binding.start` へ要求を渡すだけで、pending 中の重複は binding の同じ判断で拒否する。発送可否を再実装しない。追加の裁定状態はない。
- 実行境界: 実アプリでは既存 Effect/Atom binding がユースケースを実行し、成功と typed business error を binding へ戻す。defect と中断は `business-error` に変換せず、Effect の既存 Fiber/Scope と境界で別扱いにする。この純粋 Node モデルは runtime を自作しない。
- View: cached status の表示、tooltip の開閉、表示整形は局所責務。tooltip はモデル化していない。注文一覧の取得や他フローは独立で、global FSM はない。
- 検証専用状態: 永続的なものはない。テスト中の `cachedStatus` と assertion の局所変数だけであり、本実装の状態へ持ち込まない。

## 実行した検査

実行コマンドと結果:

```text
$ node docs/evaluations/mvp-mediator-recommended/holdout-o.mjs
holdout-o: 4 assertion groups passed

$ node_modules/.bin/oxfmt --check docs/evaluations/mvp-mediator-recommended/holdout-o.mjs docs/evaluations/mvp-mediator-recommended/holdout-o.md
（成功、終了コード 0）

$ node_modules/.bin/oxlint docs/evaluations/mvp-mediator-recommended/holdout-o.mjs
（成功、終了コード 0）
```

| ケース | 期待値 | 実測 |
| --- | --- | --- |
| 通常キャンセル | pending を開始し、最新 status が open なら成功を採用する | `testNormalCancellation` が通過 |
| 発送との競合 | cached が open でも実行時 shipped は typed business error | `testRuntimeBusinessRejection` が通過 |
| 反復要求と遅延応答 | pending の重複を拒否し、旧成功・旧 business error は新試行を完了しない | `testDuplicateAndStaleResults` が通過 |
| View 局所状態 | tooltip の開閉と cached status の整形は局所状態だけを変える | `testLocalViewState` が通過 |

実アプリの React/Effect 統合、Fiber の実際の中断、Scope の解放は未実行である。これは API 自由な抽象 Node モデルの検証結果であり、統合成功を意味しない。

## 固定6基準

| # | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | cached `open` と実行時 `shipped` を分け、ユースケースだけが `ORDER_ALREADY_SHIPPED` を返す assertion がある。 |
| 2 | ○ | 同一 pending の重複を拒否し、operation ID 1 の旧成功、ID 2 の旧 business error が ID 2/3 を完了しないことを assertion で検査した。 |
| 3 | ○ | Model、既存 binding、Mediator の追加裁定なし、検証専用状態なしを上記の責務に分類した。 |
| 4 | ○ | memo に Effect の既存実行境界と typed business error、defect/中断との区別を記録し、モデルは runtime・依存を追加していない。 |
| 5 | ○ | 通常成功、発送競合、反復要求を別関数で実行し、ケース表と実測を一致させた。実アプリ統合の未実行も明記した。 |
| 6 | ○ | tooltip/整形を View 局所責務とし、操作判断を binding/Mediator に一意に置いた。global FSM は作らず一覧取得・他フローを対象外にした。 |

## Trace U/P/E/F

| 要素 | Trace |
| --- | --- |
| U | `cancelOrder` が最新 status を読む。発送済みは typed business error を返す。 |
| P | `createMediator().requestCancel` は `binding.start` へ一度だけ委譲する。 |
| E | `createBinding` が pending/result と operation ID を保持し、完了結果を ID 一致時だけ採用する。 |
| F | Node assertion で通常成功、競合拒否、重複・旧成功・旧失敗を検査した。 |

allOK: はい。

## Unclear Issue / Cause / General Fix Rule

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 実 Effect/Atom binding の実際の result-exclusion API は未確認 | 本課題は API 自由な純粋 Node 抽象モデルで、実 runtime 実装は不要 | 統合時は導入済み binding の operation ID・中断・結果採用保証を確認し、不足する裁定だけを既存の Mediator/binding に追加する。 |

## 任意の補記

なし。

## YOUR Retries

1 回。初回 `oxlint` は関数形式・key 順・インラインコメントの規約違反を報告したため、意味を変えずに整形して再実行した。Node assertion は初回から通過した。
