# Holdout U 実行メモ

対象スキル SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6` (`local-skills/mvp-mediator-architecture/SKILL.md`)

`confirm-u.mjs` は純粋 Node の抽象モデルである。React integration、Effect runtime、通信処理は作成していない。

## 責務と状態対応表

| 項目 | 分類 | 所有者 | 内容 |
| --- | --- | --- | --- |
| `FeedBinding.entries` | 既存 binding の模擬 | binding | session ごとの最新値・失敗を保持する。 |
| `EffectScopeExecutor.subscriptions` | 実行層の模擬 | Effect Scope 実行層 | subscribe、session 単位の解除指示、旧資源の解除完了を扱う。 |
| `activeSessionId` | 本実装で追加する裁定状態 | Mediator | 現在表示へ結果を採用できる session を一つだけ示す。 |
| `nextSessionId` / `unsubscribed` | 本実装で追加する裁定状態 | Mediator | mount ごとの識別子発行と、同じ session の解除指示を一度にする。 |
| `helpOpen` | 検証専用の局所 View 状態 | Passive View | ヘルプの開閉だけを表し、購読・表示採用・解除を変えない。 |
| `checks` | 検証専用 | Node 自己検査 | assertion を順に実行する。 |

Mediator は `activeSessionId` と一致する binding だけを `view()` で採用する。Effect Scope 実行層は session ごとの資源終了を処理し、`unsubscribeCompleted(oldSession)` は新 session を変更しない。解除は通信の停止要求であり、サーバー側の処理を巻き戻す意味にはしない。

## 遷移と実測

| 検査 | 前状態 / イベント / 後状態 | 資源所有者 / 実行効果 | 期待結果 | 実測 |
| --- | --- | --- | --- | --- |
| normal mount -> value -> unmount -> completion | 初期 / mount→値→unmount→解除完了 / 非表示・旧資源なし | Scope が session を所有し、解除完了で破棄 | 表示は値、解除指示は一度、完了後に資源なし | `ok` |
| remount ignores old results and delayed completion | 旧 session 解除中 / 同銘柄へ remount、旧値・旧失敗・旧解除完了 / 新 session 表示継続 | 旧 Scope の終了と新 Scope の購読を分離 | 新 ID、表示は新値、旧解除は新資源を失わせない | `ok` |
| help is local | 新 session 表示中 / ヘルプ開閉 / 同じ表示 | Passive View のみ | ヘルプ状態が feed を変えない | `ok` |

実行コマンド: `node docs/evaluations/mvp-mediator-executable/confirm-u.mjs`。最初に独立した通常経路の assertion を実行し、その後に反復 unmount、遅延した旧失敗、遅延した旧解除完了を別検査で実行した。

## 凍結基準の自己報告

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 同銘柄の remount が別 session ID を発行し、旧値・旧失敗後も新値だけを assertion で確認した。 |
| 2 | ○ | 重複 unmount が no-op で解除指示は一度、旧解除完了後も新 Scope と表示が残ることを assertion で確認した。 |
| 3 | ○ | binding、実行層、Mediator 裁定、検証専用、局所状態を表で分類した。 |
| 4 | ○ | `view()` の採用は Mediator、資源終了は `EffectScopeExecutor` と明記し、自作 runtime を作らず通信停止を巻戻しと扱わない。 |
| 5 | ○ | 通常経路を最初の独立 assertion とし、反復・遅延失敗・遅延解除を別検査にし、表の実測と一致させた。 |
| 6 | ○ | `helpOpen` を局所状態として assertion し、Node 抽象モデルの実行済み範囲と未実行の React/Effect integration を区別した。 |

## Trace

| 区分 | 状態 | 記録 |
| --- | --- | --- |
| Understanding | OK | frozen criteria と session ごとの表示採用・資源寿命を読み取った。 |
| Planning | OK | binding、Mediator、Scope 実行層の最小3責務に分けた。 |
| Execution | OK | Node の `assert/strict` により3検査を実行した。 |
| Formatting | OK | 日本語メモ、状態対応表、遷移表、自己報告を成果物へ記録した。 |

未解決 Issue: なし。Cause: なし。General Fix Rule: session をまたぐ通知は表示採用 ID と資源所有 ID を混同せず、完了通知を旧資源の終了として処理する。

裁量判断: `view()` は current session の binding を都度読むため、表示値の二重保持を追加しなかった。解除中に同一銘柄を remount するケースだけをモデル化し、複数銘柄の同時表示や React/Effect integration は要件外として未実行である。

Retries: 0回。自分の反復判断はなし。
