# r6e: 排他デバイスの抽象判断モデル

成果物は `r6e.mjs`。親 Mediator が録音と校正の排他、最新の開始意図、停止・解放・再試行を純粋遷移として裁定する。Effect 実行境界は `acquire`、`stop`、`release` を実行して結果を ID 付きイベントとして返す。子フローの局所 UI とプロフィール編集はこの状態に参加しない。

| 要件 | 結果 | 根拠 |
| --- | --- | --- |
| 最新意図と待機中の重複 I/O 防止 | ○ | 待機中の `start` は `desired` だけを更新し、進行中の ID と効果を維持する。取得成功後にのみ最新意図と照合する。 |
| 停止・解放の成功待ち、失敗時の明示再試行 | ○ | `stopping` → `releasing` → `acquiring` の順序を固定し、失敗は `blocked`、`retry` は失敗段階だけを新 ID で再発行する。 |
| ID の新規発行と stale 完了の除外 | ○ | 新しい段階・再試行ごとに単調増加 ID を割り当て、現在の `operationId` と一致しない完了は no-op。 |
| Mediator と Effect の責務分離 | ○ | モデルはコマンドを返すだけで I/O、scheduler、runtime を持たない。親が方針を裁定し、Effect が実行・型付きエラー／defect／中断／寿命を扱う。 |
| 子フローとプロフィール編集の独立 | ○ | `profile` は state と effects を変更しない。 |
| モデル・メモ・実行確認の整合 | ○ | 下記の Node assertion を実行済み。 |

実行済み確認: `node docs/evaluations/mvp-mediator-executable/r6e.mjs`。取得中の意図往復で acquire を重複しないこと、停止→解放の順序、release 失敗の block と明示 retry、新 ID、古い失敗の無視、取得失敗から idle、profile no-op を assertion で確認する。

提案のみの確認: 実アプリの Effect 実行境界で、停止・解放の中断、Scope による資源寿命、typed error / defect の通知経路を結線した統合確認。

Trace: Understanding OK（指定スキル、React/Effect 向け条件参照、プロトコル E 節を読了）。Planning OK（親の排他方針と実行境界を分離）。Execution OK（2 ファイルのみ作成し自己確認を実行）。Formatting OK（指定 export と日本語メモを配置）。

不明点: Issue は実行層が返す `ok` / `fail` 以外の区別された終了通知の詳細。Cause はプロトコルが抽象モデルを求め、具体的な Effect API を規定しないこと。General Fix Rule は、実装側で各コマンド ID に結果を対応付け、現在の ID のみを親 Mediator へ完了イベントとして渡すこと。

裁量による補完: acquire 失敗では最新意図を破棄して `idle` に戻す。これは「idle に戻り自動再試行しない」を、次の開始は新しい明示要求と解する最小表現である。retry は失敗段階の再発行だけを行い、待機中の start は intent 更新だけを行う。再試行回数（この実装作業で判断をやり直した回数）: 0。
