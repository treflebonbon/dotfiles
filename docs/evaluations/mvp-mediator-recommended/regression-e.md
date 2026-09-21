# E: exclusive device

## 責務

親 Mediator は録音と較正の排他、最新要求、停止・解放・再試行を裁定する。子フローは開始要求だけを送り、`profile` は局所 UI としてデバイス状態を変えない。既存の Effect 実行境界は `acquire`／`stop`／`release` command を実行し、型付きエラー、defect、中断、寿命を扱う。この純粋モデルは I/O、scheduler、runtime を持たない。

## 実行した確認

`node_modules/.bin/oxfmt --write docs/evaluations/mvp-mediator-recommended/regression-e.mjs docs/evaluations/mvp-mediator-recommended/regression-e.md`

実測結果: 2 files の整形完了（exit 0）。

`node docs/evaluations/mvp-mediator-recommended/regression-e.mjs`

実測結果: `regression-e: 6 assertions passed`（exit 0）。

`node_modules/.bin/oxlint docs/evaluations/mvp-mediator-recommended/regression-e.mjs`

実測結果: 診断なし（exit 0）。

`git diff --check`

実測結果: 出力なし（exit 0）。実アプリ統合は未実行であり、この確認は抽象 decision model のみを対象にする。

| 基準 | 結果 | 根拠 |
| --- | --- | --- |
| 1. 待機中の最新意図 | ○ | acquiring 中に `calibration`、続けて in-flight と同じ `recording` を要求しても I/O を増やさず、成功時に recording を active にする assertion が通過した。stopping／releasing／blocked の `start` も desired だけを更新する。 |
| 2. 停止・解放待ちと明示 retry | ○ | 切替は stop 成功後に release、release 成功後に acquire を発行する。stop／release の失敗は blocked にし、`retry` は失敗した stage だけを新 ID で再発行する。blocked 中の start は retry しないことを確認した。 |
| 3. 操作 ID と stale completion | ○ | stage ごとと retry ごとに `device-N` を採番する。古い release の成功が acquiring state を変えず、6 ID が重複しない assertion が通過した。 |
| 4. 親／Effect／純粋モデルの分担 | ○ | model の effect は `{ type, target, id }` command だけで、I/O・Effect runtime・scheduler を含まないことを assertion で確認した。 |
| 5. 子フローと profile の独立 | ○ | `profile` は同じ state object と空 effects を返す assertion が通過した。 |
| 6. 成果物・memo・check の一致 | ○ | 本ファイルの記載どおり `regression-e.mjs` の 6 assertion を実行し、成功を確認した。提案のみの確認はない。 |

## Trace

| Trace | 内容 |
| --- | --- |
| U | E の指示を、純粋 Node モデル、指定 API、6 基準、I/O を実行しないこととして理解した。 |
| P | `initial`／`transition`／`observe` と assertion を一つの `.mjs` に置き、最新意図、停止・解放、retry、stale、profile、acquire 失敗を順に確認する計画にした。 |
| E | 指定 API を実装し、Node assertion、oxfmt、oxlint、diff check を実行した。対象 skill と reference は読んだが変更していない。 |
| F | `oxfmt` で両成果物を整形し、`oxlint` が成功する構造へ最小限に分割した。lint disable は最終成果物に含めていない。 |
| allOK | 可能。正常成功、切替、stop/release failure、retry、stale completion、profile、acquire failure を assertion で通過した。 |

## Unclear Issue / Cause / General Fix Rule

該当なし。仕様は、acquire 中の owner を null、stop/release/blocked 中の owner を旧 owner とすることまで明示しており、必要な裁定状態を決められる。

## Optional fill-ins

なし。

## YOUR Retries

1 回。初回の `oxlint` は repository の厳格スタイル規則（関数式、key 順、分岐 complexity など）で失敗した。lint disable は使わず、機械修正と `transition` の小さな event handler 分割で解消して再実行する。

## INPUT

- 対象 skill: `local-skills/mvp-mediator-architecture/SKILL.md`
- SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 読んだ reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
