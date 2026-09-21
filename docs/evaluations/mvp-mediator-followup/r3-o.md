# O — 実行時の業務判定（dispatch前固定）

`r3-o.mjs` は API 非依存の純粋 Node 抽象モデルである。実行コマンドは `node docs/evaluations/mvp-mediator-followup/r3-o.mjs`。5 ケースすべてが `OK` になった。

## 責務と状態

| 区分 | 所有者 | 内容 |
| --- | --- | --- |
| ユースケース | `CancelOrderUseCase` | 実行時の最新 status を読み、発送済みを `BusinessError` で拒否する。cached status は参照しない。 |
| 既存 binding の模擬 | `ExistingCancelBinding` | attempt ごとの pending と result を保持する。 |
| 追加裁定状態 | `CancelMediator.currentAttempt` | 現在採用してよい attempt ID だけを保持する。pending/result を複製しない。 |
| 検証専用 | `tests` と test 名 | assertion の実行記録だけであり、本実装の状態ではない。 |
| View 局所状態 | `tooltipOpen`、表示整形 | tooltip と status 表示だけを扱い、業務規則や兄弟フローを操作しない。 |

Mediator は既存 binding の pending を見て二重送信を拒否し、現在の attempt ID と一致する完了だけを採用する。発送可否は判定しない。注文一覧の取得や他フローはこの Mediator や global FSM に入れない。

## 実行した assertion

| ケース | 実測結果 | 照合した値 |
| --- | --- | --- |
| 通常の未発送キャンセル | 成功 | 完了を採用、pending 解放、`cancelled` 結果。 |
| cached status 後の発送競合 | typed business error | `BusinessError(ORDER_ALREADY_SHIPPED)` をユースケースが返し、View/Mediator に同規則はない。 |
| pending 中の反復要求 | 拒否 | 二つ目は `{ accepted: false, reason: "pending" }`。 |
| 旧成功後の再試行 | 旧結果を除外 | 新しい attempt が pending/current のまま。 |
| 旧失敗後の再試行 | 旧結果を除外 | 新しい attempt が pending/current のまま。 |

実アプリ統合は未実行。実装時は既存 Effect 実行境界／binding がユースケースを実行する。`BusinessError` のような想定内の型付き業務エラーは UI へ返すが、Effect の defect と中断は同じ業務拒否に潰さない。自作 runtime や新規依存は追加しない。
