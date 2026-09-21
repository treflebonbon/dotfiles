# Scenario S: request identity による検索結果採否

## 責務と状態対応

| 状態 | 分類 | 所有者 | 用途 |
| --- | --- | --- | --- |
| `requests[id]` の `text` / `status` / `value` / `error` | 既存 binding／実行層の模擬 | React/Query binding | request ごとの通常の pending・成功・失敗を保持する。 |
| `currentRequestId` | 本実装で追加する裁定状態 | Search Mediator | 表示してよい request identity を一つだけ決める。text は採否に使わない。 |
| `nextRequestNumber` | 検証専用の ID 発行補助 | 抽象モデル | 同じ text の再入力でも別 identity を確実に作る。実装では既存 binding の request ID を使う。 |
| `helpOpen` | Passive View の局所状態 | help tooltip | tooltip の表示だけを変え、検索の許可・取消・進行・結果採否を変えない。 |

Mediator は `currentRequestId` の binding snapshot だけを View に渡す。従って、古い request の binding が成功・失敗へ更新されても、最新 request の pending/result/error は変わらない。新規検索では前 request の中断を実行層へ best effort で依頼する。これは通信停止の試みであり、サーバー側の rollback を保証しない。

## 遷移と実行記録

| 検査名 | 前状態 / イベント | 後状態 | 資源所有者 | 実行効果 | 実測 |
| --- | --- | --- | --- | --- | --- |
| `normal-completes` | 初期 / `submit(alpha)` → `success(request-1)` | `request-1` の pending 後に `alpha result` を表示 | binding `request-1` | `execute`、`settle:success` | passed |
| `failure-is-visible` | 初期 / `submit(broken)` → `error(request-1)` | `network` を表示 | binding `request-1` | `execute`、`settle:error` | passed |
| `same-text-reentry-ignores-stale-success-and-failure` | 初期 / `submit(tea)` を3回、古い success・error、最新 success | request-1/2 の通知後も request-3 は pending。request-3 success だけが `fresh result` を表示 | 各 settlement は該当 binding、表示採否は Mediator | 古い実行の `abort` は best effort、各 request は `execute` と `settle` | passed |
| `tooltip-is-local` | 初期 / `submit(guide)` → help open → success | tooltip が開いたまま `guide result` を表示 | tooltip は View、検索は binding | tooltip に実行効果なし | passed |

`example-3-s.mjs` の `cases` が期待値と実行記録の共通定義である。最初の検査は割込みのない初期状態から完了までを assertion している。実行出力では全4件が `result: "passed"` だった。

## 凍結基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. text でなく request identity を照合し、同じ text の再入力を扱う | ○ | `currentRequestId` と `request-1..3` を使い、`tea` 3回を別 request として検査した。 |
| 2. stale 成功・失敗が新 pending/result を変えず、current 完了を適用する assertion | ○ | request-1 success と request-2 error は `adopted: false`、request-3 success は `adopted: true` を同一 assertion で確認した。 |
| 3. 既存 binding の実行と通常 pending/result を再利用し、追加状態は結果採否識別だけ | ○ | request 状態は `createQueryBinding` が所有し、Mediator は `currentRequestId` だけで表示を導出する。 |
| 4. Effect/Atom/独自 scheduler 追加なし、サーバー rollback 保証なし | ○ | 純粋 Node モデルだけを用い、abort は `best-effort:no-rollback` と明記した。 |
| 5. tooltip 局所状態と結果採否の単一所有者 | ○ | `helpOpen` は View、`currentRequestId` は Search Mediator と対応表・検査で明記した。 |
| 6. memo/model 一致、実行検査と制約を示し browser 統合成功を主張しない | ○ | 表の4ケースは `cases` と一致し、Node self-check・oxlint・oxfmt のみ実行した。browser 統合は未実行。 |

## 入力と作業記録

- INPUT target SHA256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 読んだ参照: `local-skills/mvp-mediator-architecture/SKILL.md`、`local-skills/mvp-mediator-architecture/references/model-verification.md`
- 実行した検査: `node docs/evaluations/mvp-mediator-executable/example-3-s.mjs`、`node_modules/.bin/oxlint --config oxlint.config.ts ...`、`node_modules/.bin/oxfmt --check ...`。
- 未実行: 実 React/Query binding、ネットワーク、browser 統合。抽象モデルなのでこれらの成功は主張しない。

### YOUR Trace

| Understanding | Planning | Execution | Formatting |
| ------------- | -------- | --------- | ---------- |
| OK            | OK       | OK        | OK         |

all OK。

### Unclear Issue / Cause / General Fix Rule

| 項目 | 記録 |
| --- | --- |
| Unclear Issue | 実プロジェクトの Query binding が callback に渡す request ID の形は対象外で未確定。 |
| Cause | 本成果物は API 自由の Node 抽象モデルであり、既存 UI 実装を変更しない。 |
| General Fix Rule | binding が発行した request identity を Mediator が保存し、その identity の snapshot だけを表示する。text と callback 到着順を採否条件にしない。 |

### YOUR Retries

判断やり直し: 1 回。初回 self-check で開始イベントに余計な `requestId` を返していたため除去した。lint のキー順修正は機械的整形であり、状態方針のやり直しには数えない。
