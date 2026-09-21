# Scenario S: request identity による検索結果採否

## 入力

- Target: `local-skills/mvp-mediator-architecture/SKILL.md`
- INPUT target SHA256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 読んだ参照: `local-skills/mvp-mediator-architecture/references/model-verification.md`

## 責務と状態

| 状態または責務 | 所有者 | 分類 | 説明 |
| --- | --- | --- | --- |
| request ごとの `text` / `status` / `result` / `error` | 既存 Query binding（実行層） | 既存 binding／実行層の模擬 | 通常の pending と結果を request record に保持する。 |
| `currentRequestId` | Search Mediator | 本実装で追加する裁定状態 | 最新 request だけを選び、View が読む binding record を決める唯一の採否状態。 |
| 取消要求 | 既存 Query binding（実行層） | 既存 binding／実行層の模擬 | `cancel` は best effort の中断要求であり、サーバー処理の rollback を保証しない。 |
| tooltip の開閉 | Help Tooltip の Passive View | 局所状態 | 検索の開始、取消、進行、結果採否を変えない。 |
| case の expected / actual | self-check | 検証専用 | 実装状態には含めない。 |

結果採否の単一所有者は Search Mediator の `currentRequestId` である。View は同 ID の binding record から通常の pending/result/error を導出する。text は採否キーではないため、`cats` を再入力しても別 request になる。

## 遷移と検証記録

| 検査名 | 前状態 / イベント / 後状態 | 資源所有者 | 実行効果 | 実測 |
| --- | --- | --- | --- | --- |
| `normal-current-success` | idle → search(cats) → current pending → current success | binding request record | execute, success | passed |
| `normal-current-failure` | idle → search(cats) → current pending → current error | binding request record | execute, error | passed |
| `stale-success-keeps-new-request-pending` | cats pending → search(dogs) → dogs pending → cats success → dogs success | binding request record | execute, cancel best-effort, execute, success, success | passed |
| `stale-failure-keeps-new-request-pending` | cats pending → search(dogs) → dogs pending → cats error → dogs error | binding request record | execute, cancel best-effort, execute, error, error | passed |
| `same-text-reentry-has-a-new-identity` | cats pending → search(cats) → second cats pending → first success → second success | binding request record | execute, cancel best-effort, execute, success, success | passed |
| `cancellation-is-best-effort-not-rollback` | cats pending → search(dogs) → dogs pending | binding request record | execute, cancel best-effort, execute | passed (`serverRollback: false`) |
| `tooltip-is-local` | tooltip closed/open → toggle → open/closed | Passive View | なし | passed |

通常経路は `normal-current-success` で新しい初期状態から `search → success` を assertion 済みである。古い成功と古い失敗はいずれも current の pending を変えず、current の完了だけが表示されることを別々の assertion で確認した。

## 凍結基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. text でなく request identity を成功・失敗へ照合し、同文再入力を扱う | ○ | `currentRequestId` と request record を参照し、同じ `cats` の2 request に `notEqual` assertion を置いた。 |
| 2. stale 成功・失敗が新 pending/result を変えず、current 完了は適用される | ○ | stale 成功と stale 失敗を別ケースで pending 維持と current 完了を assertion した。 |
| 3. 既存 binding の実行と通常 pending/result を再利用し、追加状態を採否識別だけにする | ○ | binding が request record を所有し、Mediator の追加状態は `currentRequestId` のみ。 |
| 4. Effect/Atom/独自 scheduler の追加やサーバー rollback 保証をしない | ○ | 純粋 Node モデルであり、取消は binding への best-effort 要求だけで `serverRollback: false` を確認した。 |
| 5. tooltip 局所状態と結果採否の単一所有者を明記する | ○ | tooltip は Passive View、採否は Search Mediator と責務表に明記した。 |
| 6. memo/model が一致し、実行検査と制約を示し browser 統合成功を主張しない | ○ | 下記コマンドを実行し、表の検査名とモデル出力を対応させた。browser 統合は未実行。 |

## 実行した検査

```sh
node docs/evaluations/mvp-mediator-executable/example-2-s.mjs
node_modules/.bin/oxlint --config oxlint.config.ts docs/evaluations/mvp-mediator-executable/example-2-s.mjs
node_modules/.bin/oxfmt --check docs/evaluations/mvp-mediator-executable/example-2-s.mjs
```

Node self-check は 7 ケースすべて `passed`。oxlint と oxfmt は成功する設定で実行した。browser 統合は抽象 Node モデルの範囲外のため未実行であり、成功は主張しない。

## YOUR Trace

1. Target と必須参照を読了: OK
2. binding 再利用と Mediator の採否状態をモデル化: OK
3. Node self-check と lint/format 検査を実行: OK
4. メモとモデルのケース名・制約を照合: OK

allOK

## Unclear Issue / Cause / General Fix Rule

**Unclear Issue:** 実際の React/Query binding が持つ取消 API とキャッシュ再検証通知の形は未提示。

**Cause:** この Scenario は API 自由の抽象 Node モデルである。

**General Fix Rule:** 実装では binding が発行する一意な request identity を Mediator が保持し、その ID の pending/result だけを表示する。取消は binding の API へ委譲し、サーバー rollback の保証として扱わない。

## YOUR Retries

判断やり直し数: 2。初回は snapshot の未定義フィールドと lint 規則、2回目は expected の表示 text 不足を検出し、出力ファイルだけを補正した。
